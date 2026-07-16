rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3extralearners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "db_logging.R"))

dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)
if (!file.exists(lightgbm_tuning_instance_path)) {
  stop("LightGBM-Tuning fehlt. Bitte zuerst 100_lightgbm_tuning.R ausfuehren.")
}

train <- fread(train_path)
train[, (id_col) := NULL]
feature_char_cols <- setdiff(names(train)[vapply(train, is.character, logical(1))], target_col)
train[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
train[, (target_col) := as.numeric(get(target_col))]
task_full <- as_task_regr(train, target = target_col, id = paste0(target_col, "_full_holdout"))

tuning_instance <- readRDS(lightgbm_tuning_instance_path)
lightgbm_params <- tuning_instance$result_learner_param_vals
lightgbm_params <- lightgbm_params[grepl("^regr\\.lightgbm\\.", names(lightgbm_params))]
blend_weight_lightgbm <- ensemble_lightgbm_weight
if (is.na(blend_weight_lightgbm) || blend_weight_lightgbm < 0 || blend_weight_lightgbm > 1) {
  stop("ensemble_lightgbm_weight muss nach dem OOF-Schritt zwischen 0 und 1 gesetzt werden.")
}

make_tuned_lightgbm <- function() {
  learner <- make_encoded_imputed_learner(lrn(
    "regr.lightgbm",
    num_iterations = lightgbm_baseline_iterations,
    learning_rate = 0.05,
    seed = seed,
    verbose = -1
  ))
  learner$param_set$values <- utils::modifyList(learner$param_set$values, lightgbm_params)
  learner
}

make_catboost <- function() {
  make_encoded_imputed_learner(lrn(
    "regr.catboost",
    iterations = catboost_baseline_iterations,
    learning_rate = 0.05,
    random_seed = seed,
    logging_level = "Silent",
    allow_writing_files = FALSE
  ))
}

metric_values <- function(truth, response) {
  c(
    "regr.rmse" = sqrt(mean((truth - response) ^ 2)),
    "regr.mae" = mean(abs(truth - response)),
    "regr.rsq" = 1 - sum((truth - response) ^ 2) / sum((truth - mean(truth)) ^ 2)
  )
}

# Der abweichende Seed macht diesen Holdout unabhaengig von der OOF-Gewichtssuche.
set.seed(full_holdout_seed)
resampling <- rsmp("holdout", ratio = full_holdout_train_ratio)
resampling$instantiate(task_full)
train_ids <- resampling$train_set(1)
test_ids <- resampling$test_set(1)
truth <- as.numeric(task_full$truth(test_ids))

fit_and_predict <- function(learner_factory, label) {
  learner <- learner_factory()
  started <- proc.time()[["elapsed"]]
  learner$train(task_full, row_ids = train_ids)
  prediction <- learner$predict(task_full, row_ids = test_ids)$response
  elapsed_seconds <- proc.time()[["elapsed"]] - started
  cat(label, "fertig (", round(elapsed_seconds, 1), "s)\n", sep = "")
  list(response = prediction, elapsed_seconds = elapsed_seconds)
}

lightgbm_result <- fit_and_predict(make_tuned_lightgbm, "LightGBM")
catboost_result <- fit_and_predict(make_catboost, "CatBoost")
blend_response <- blend_weight_lightgbm * lightgbm_result$response +
  (1 - blend_weight_lightgbm) * catboost_result$response

results <- rbindlist(list(
  c(list(algorithm = "lightgbm"), as.list(metric_values(truth, lightgbm_result$response)),
    list(elapsed_seconds = lightgbm_result$elapsed_seconds)),
  c(list(algorithm = "catboost"), as.list(metric_values(truth, catboost_result$response)),
    list(elapsed_seconds = catboost_result$elapsed_seconds)),
  c(list(algorithm = "blend_lightgbm_catboost"), as.list(metric_values(truth, blend_response)),
    list(elapsed_seconds = NA_real_))
))
setorder(results, regr.rmse)
holdout_predictions <- data.table(
  row_id = test_ids,
  truth = truth,
  lightgbm_tuned = lightgbm_result$response,
  catboost = catboost_result$response,
  blend_fixed_60_40 = blend_response
)
fwrite(results, full_holdout_results_path)
fwrite(holdout_predictions, full_holdout_predictions_path)

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "120_full_holdout_confirmation.R")
db_run_id <- db_create_run(
  db_con, db_wf_id, seed = full_holdout_seed,
  notes = "Unabhaengige Voll-Daten-Holdout-Bestaetigung; Blendgewicht vorab aus OOF fixiert"
)
db_log_run_config(db_con, db_run_id, list(
  train_ratio = full_holdout_train_ratio,
  holdout_seed = full_holdout_seed,
  primary_measure_id = primary_measure_id,
  blend_weight_lightgbm = blend_weight_lightgbm,
  blend_weight_catboost = 1 - blend_weight_lightgbm
))
db_rsmp_id <- db_create_resampling(
  db_con, db_run_id, "holdout", ratio = full_holdout_train_ratio, seed = full_holdout_seed
)

log_holdout_model <- function(algorithm, response, elapsed_seconds, hyperparams) {
  mconf_id <- db_create_model_config(
    db_con, db_run_id, task_type = "regr", algorithm = algorithm,
    feature_set = "raw", preprocessing = "impute_median_mode_one_hot",
    task_id = task_full$id, hyperparams = hyperparams
  )
  metrics <- metric_values(truth, response)
  for (measure in names(metrics)) {
    db_log_metric_result(db_con, mconf_id, db_rsmp_id, measure, metrics[[measure]],
                         elapsed_seconds = elapsed_seconds)
  }
  db_log_regression_predictions(db_con, mconf_id, db_rsmp_id, test_ids, truth, response)
}

tuned_hyperparams <- lightgbm_params
names(tuned_hyperparams) <- sub("^regr\\.lightgbm\\.", "", names(tuned_hyperparams))
log_holdout_model("lightgbm", lightgbm_result$response, lightgbm_result$elapsed_seconds,
                  tuned_hyperparams)
log_holdout_model("catboost", catboost_result$response, catboost_result$elapsed_seconds,
                  list(iterations = catboost_baseline_iterations, learning_rate = 0.05))
log_holdout_model("blend_lightgbm_catboost", blend_response, NA_real_, list(
  weight_lightgbm = blend_weight_lightgbm,
  weight_catboost = 1 - blend_weight_lightgbm,
  weight_source = "110_oof_ensemble.R"
))

db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== Voll-Daten-Holdout-Bestaetigung ===\n")
print(results)
cat("\nGespeichert:\n")
cat("Ergebnisse:", full_holdout_results_path, "\n")
cat("Vorhersagen:", full_holdout_predictions_path, "\n")
cat("Experiment-DB:", experiments_db_path, "\n")
