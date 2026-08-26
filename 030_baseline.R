rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "005_benchmark_runtime.R"))
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "db_logging.R"))

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(task_train_small_path)) {
  source(file.path(project_dir, "020_task.R"))
}

task_train_small <- readRDS(task_train_small_path)

learners <- list(
  make_imputed_learner(lrn("regr.rpart", minsplit = 20)),
  make_imputed_learner(lrn(
    "regr.ranger",
    num.trees = ranger_baseline_trees,
    respect.unordered.factors = "order",
    seed = seed
  ))
)

timed_benchmark <- run_timed_benchmark(
  tasks = list(task_train_small),
  learners = learners,
  resampling = rsmp("cv", folds = cv_folds),
  measures = msrs(baseline_measure_ids)
)

baseline_results <- timed_benchmark$results[
  ,
  c("task_id", "learner_id", "resampling_id", baseline_measure_ids, "elapsed_seconds"),
  with = FALSE
]

fwrite(baseline_results, baseline_results_path)
saveRDS(timed_benchmark$benchmarks, baseline_benchmark_path)

# Optionale Persistence-Baseline (BACKLOG.md Nr. 2, siehe 000_config.R fuer
# die Begruendung) - default-inert (NULL -> uebersprungen). Berichtet IMMER
# neben, nie statt der obigen naiven/Ranger-Baselines.
if (!is.null(baseline_persistence_entity_col)) {
  full_dt <- task_train_small$data()
  setorderv(full_dt, c(baseline_persistence_entity_col, baseline_persistence_date_col))
  full_dt[, .persistence_pred := shift(get(target_col), baseline_persistence_lag),
          by = baseline_persistence_entity_col]
  valid_mask <- !is.na(full_dt$.persistence_pred)
  persistence_rmse <- sqrt(mean((full_dt$.persistence_pred[valid_mask] - full_dt[[target_col]][valid_mask])^2))
  naive_mean_rmse <- sqrt(mean((mean(full_dt[[target_col]]) - full_dt[[target_col]][valid_mask])^2))
  cat(sprintf(
    "\n=== Persistence-Baseline (Lag=%d, Entity=%s) ===\nnaive_mean: %.4f | persistence: %.4f (n=%d, %.1f%% mit gueltigem Lag)\n",
    baseline_persistence_lag, baseline_persistence_entity_col, naive_mean_rmse, persistence_rmse,
    sum(valid_mask), 100 * mean(valid_mask)
  ))
  fwrite(
    data.table(measure = c("naive_mean_rmse", "persistence_rmse"), value = c(naive_mean_rmse, persistence_rmse)),
    file.path(artifact_dir, "baseline_persistence_results.csv")
  )
}

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "030_baseline.R")
db_run_id <- db_create_run(db_con, db_wf_id, seed = seed, notes = "Regression-baseline: rpart und Ranger (100 Baeume)")
db_log_run_config(db_con, db_run_id, list(
  cv_folds = cv_folds,
  primary_measure_id = primary_measure_id,
  resampling_stratified = FALSE
))

db_log_timed_benchmark(
  db_con, db_run_id, timed_benchmark, measure_names = baseline_measure_ids,
  model_config_fn = function(row) list(
    task_type = "regr",
    algorithm = algorithm_from_learner_id(row$learner_id[1]),
    feature_set = "raw",
    preprocessing = "impute_median_mode",
    class_weight_power = NA_real_,
    task_id = row$task_id[1]
  ),
  resampling_strategy = "cv", resampling_folds = cv_folds, resampling_seed = seed
)

db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== Regression-Baselines (5-fache CV) ===\n")
print(baseline_results)
cat("\nGespeichert:\n")
cat("Ergebnisse:", baseline_results_path, "\n")
cat("Benchmark :", baseline_benchmark_path, "\n")
cat("Experiment-DB:", experiments_db_path, "\n")
