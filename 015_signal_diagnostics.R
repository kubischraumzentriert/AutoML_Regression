rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
})

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)
if (!file.exists(task_train_small_path)) {
  source(file.path(project_dir, "020_task.R"))
}

task_train_small <- readRDS(task_train_small_path)
row_ids <- task_train_small$row_ids
truth <- as.numeric(task_train_small$truth(row_ids))

metric_values <- function(truth, response) {
  c(
    "regr.rmse" = sqrt(mean((truth - response) ^ 2)),
    "regr.mae" = mean(abs(truth - response)),
    "regr.rsq" = 1 - sum((truth - response) ^ 2) / sum((truth - mean(truth)) ^ 2)
  )
}

# Kein regulärer Kandidat, sondern ein Signal-Gate: Der Mittelwert wird immer
# nur aus dem jeweiligen Trainingsfold berechnet und ist daher CV-konform.
resampling <- rsmp("cv", folds = cv_folds)
resampling$instantiate(task_train_small)
mean_response <- rep(NA_real_, length(row_ids))
fold <- rep(NA_integer_, length(row_ids))
names(mean_response) <- as.character(row_ids)
names(fold) <- as.character(row_ids)

for (iteration in seq_len(cv_folds)) {
  train_ids <- resampling$train_set(iteration)
  test_ids <- resampling$test_set(iteration)
  mean_response[as.character(test_ids)] <- mean(task_train_small$truth(train_ids))
  fold[as.character(test_ids)] <- iteration
}

aggregate_metrics <- metric_values(truth, unname(mean_response))
feature_data <- task_train_small$data(cols = task_train_small$feature_names)
numeric_features <- names(feature_data)[vapply(feature_data, is.numeric, logical(1))]
correlations <- rbindlist(lapply(numeric_features, function(feature) {
  data.table(
    feature = feature,
    pearson = cor(feature_data[[feature]], truth, method = "pearson"),
    spearman = cor(feature_data[[feature]], truth, method = "spearman")
  )
}))
correlations[, abs_pearson := abs(pearson)]
setorder(correlations, -abs_pearson)

diagnostics <- data.table(
  task_id = task_train_small$id,
  target_mean = mean(truth),
  target_sd = sd(truth),
  regr.rmse = aggregate_metrics[["regr.rmse"]],
  regr.mae = aggregate_metrics[["regr.mae"]],
  regr.rsq = aggregate_metrics[["regr.rsq"]],
  n_numeric_features = length(numeric_features),
  n_non_numeric_features = length(task_train_small$feature_names) - length(numeric_features),
  max_abs_pearson = if (nrow(correlations) > 0) max(abs(correlations$pearson)) else NA_real_,
  max_abs_spearman = if (nrow(correlations) > 0) max(abs(correlations$spearman)) else NA_real_
)
fwrite(diagnostics, signal_diagnostics_path)
fwrite(correlations, signal_correlations_path)

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "015_signal_diagnostics.R")
db_run_id <- db_create_run(
  db_con, db_wf_id, seed = seed,
  notes = "CV-konforme Mittelwertreferenz und Feature-Signal-Diagnostik vor Tuning"
)
db_log_run_config(db_con, db_run_id, list(cv_folds = cv_folds, purpose = "signal_gate"))
db_rsmp_id <- db_create_resampling(db_con, db_run_id, "cv", folds = cv_folds, seed = seed)
db_mconf_id <- db_create_model_config(
  db_con, db_run_id, task_type = "regr", algorithm = "target_mean_diagnostic",
  feature_set = "none", preprocessing = "none", task_id = task_train_small$id
)
for (measure in names(aggregate_metrics)) {
  db_log_metric_result(db_con, db_mconf_id, db_rsmp_id, measure, aggregate_metrics[[measure]])
  for (iteration in seq_len(cv_folds)) {
    in_fold <- unname(fold) == iteration
    fold_metrics <- metric_values(truth[in_fold], unname(mean_response)[in_fold])
    db_log_metric_result(db_con, db_mconf_id, db_rsmp_id, measure, fold_metrics[[measure]], fold = iteration)
  }
}
db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== Signal-Diagnostik (5-fache CV) ===\n")
print(diagnostics)
cat("\nKorrelationen:\n")
print(correlations)
cat("\nGespeichert:\n")
cat("Diagnostik :", signal_diagnostics_path, "\n")
cat("Korrelation:", signal_correlations_path, "\n")
cat("Experiment-DB:", experiments_db_path, "\n")
