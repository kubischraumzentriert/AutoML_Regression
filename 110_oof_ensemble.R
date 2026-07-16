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

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(task_train_small_path)) {
  source(file.path(project_dir, "020_task.R"))
}
if (!file.exists(lightgbm_tuning_instance_path)) {
  stop("LightGBM-Tuning fehlt. Bitte zuerst 100_lightgbm_tuning.R ausfuehren.")
}

task_train_small <- readRDS(task_train_small_path)
tuning_instance <- readRDS(lightgbm_tuning_instance_path)
lightgbm_params <- tuning_instance$result_learner_param_vals
# Pipeline-Parameter sind bereits im Learner gesetzt. Nur die getunten
# LightGBM-Parameter gehoeren in die Wiederherstellung und das DB-Logging.
lightgbm_params <- lightgbm_params[grepl("^regr\\.lightgbm\\.", names(lightgbm_params))]

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

# Ein einziges instanziiertes Resampling garantiert identische OOF-Folds fuer
# beide Basismodelle und damit eine aussagekraeftige Residualkorrelation.
resampling <- rsmp("cv", folds = cv_folds)
resampling$instantiate(task_train_small)

make_oof_predictions <- function(learner_factory, label) {
  row_ids <- task_train_small$row_ids
  truth <- task_train_small$truth(row_ids)
  response <- rep(NA_real_, length(row_ids))
  fold <- rep(NA_integer_, length(row_ids))
  names(response) <- as.character(row_ids)
  names(fold) <- as.character(row_ids)

  started <- proc.time()[["elapsed"]]
  for (iteration in seq_len(cv_folds)) {
    learner <- learner_factory()
    train_ids <- resampling$train_set(iteration)
    test_ids <- resampling$test_set(iteration)
    learner$train(task_train_small, row_ids = train_ids)
    prediction <- learner$predict(task_train_small, row_ids = test_ids)
    response[as.character(test_ids)] <- prediction$response
    fold[as.character(test_ids)] <- iteration
    cat(label, "Fold", iteration, "von", cv_folds, "fertig\n")
  }

  list(
    row_id = row_ids,
    truth = as.numeric(truth),
    response = unname(response),
    fold = unname(fold),
    elapsed_seconds = proc.time()[["elapsed"]] - started
  )
}

lightgbm_oof <- make_oof_predictions(make_tuned_lightgbm, "LightGBM")
catboost_oof <- make_oof_predictions(make_catboost, "CatBoost")

stopifnot(
  !anyNA(lightgbm_oof$response), !anyNA(catboost_oof$response),
  identical(lightgbm_oof$row_id, catboost_oof$row_id),
  identical(lightgbm_oof$fold, catboost_oof$fold)
)

weights <- seq(0, 1, by = 0.05)
ensemble_results <- rbindlist(lapply(weights, function(weight_lightgbm) {
  response <- weight_lightgbm * lightgbm_oof$response +
    (1 - weight_lightgbm) * catboost_oof$response
  as.list(c(weight_lightgbm = weight_lightgbm, metric_values(lightgbm_oof$truth, response)))
}))
setorder(ensemble_results, regr.rmse)
best_weight <- ensemble_results$weight_lightgbm[1]
best_response <- best_weight * lightgbm_oof$response +
  (1 - best_weight) * catboost_oof$response
residual_correlation <- cor(
  lightgbm_oof$response - lightgbm_oof$truth,
  catboost_oof$response - catboost_oof$truth
)

oof_predictions <- data.table(
  row_id = lightgbm_oof$row_id,
  fold = lightgbm_oof$fold,
  truth = lightgbm_oof$truth,
  lightgbm_tuned = lightgbm_oof$response,
  catboost = catboost_oof$response,
  blend_best = best_response
)
fwrite(ensemble_results, ensemble_results_path)
fwrite(oof_predictions, ensemble_oof_predictions_path)

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "110_oof_ensemble.R")
db_run_id <- db_create_run(
  db_con, db_wf_id, seed = seed,
  notes = "OOF-Ensemble: getuntes LightGBM und CatBoost, Gewichtsgrid 0.00 bis 1.00"
)
db_log_run_config(db_con, db_run_id, list(
  cv_folds = cv_folds,
  primary_measure_id = primary_measure_id,
  lightgbm_iterations = lightgbm_baseline_iterations,
  catboost_iterations = catboost_baseline_iterations,
  weight_grid_step = 0.05,
  residual_correlation = residual_correlation
))
db_rsmp_id <- db_create_resampling(db_con, db_run_id, "cv", folds = cv_folds, seed = seed)

log_oof_model <- function(algorithm, response, elapsed_seconds, hyperparams, save_predictions = FALSE) {
  mconf_id <- db_create_model_config(
    db_con, db_run_id, task_type = "regr", algorithm = algorithm,
    feature_set = "raw", preprocessing = "impute_median_mode_one_hot",
    task_id = task_train_small$id, hyperparams = hyperparams
  )
  aggregate_metrics <- metric_values(lightgbm_oof$truth, response)
  for (measure in names(aggregate_metrics)) {
    db_log_metric_result(db_con, mconf_id, db_rsmp_id, measure, aggregate_metrics[[measure]],
                         elapsed_seconds = elapsed_seconds)
    for (iteration in seq_len(cv_folds)) {
      in_fold <- lightgbm_oof$fold == iteration
      fold_metrics <- metric_values(lightgbm_oof$truth[in_fold], response[in_fold])
      db_log_metric_result(db_con, mconf_id, db_rsmp_id, measure, fold_metrics[[measure]], fold = iteration)
    }
  }
  if (save_predictions) {
    db_log_regression_predictions(
      db_con, mconf_id, db_rsmp_id, lightgbm_oof$row_id, lightgbm_oof$truth, response,
      fold = lightgbm_oof$fold
    )
  }
  mconf_id
}

tuned_hyperparams <- lightgbm_params
names(tuned_hyperparams) <- sub("^regr\\.lightgbm\\.", "", names(tuned_hyperparams))
tuned_hyperparams$num_iterations <- lightgbm_baseline_iterations
log_oof_model("lightgbm", lightgbm_oof$response, lightgbm_oof$elapsed_seconds,
              tuned_hyperparams, save_predictions = TRUE)
log_oof_model("catboost", catboost_oof$response, catboost_oof$elapsed_seconds, list(
  iterations = catboost_baseline_iterations, learning_rate = 0.05
), save_predictions = TRUE)

for (i in seq_len(nrow(ensemble_results))) {
  weight_lightgbm <- ensemble_results$weight_lightgbm[i]
  response <- weight_lightgbm * lightgbm_oof$response +
    (1 - weight_lightgbm) * catboost_oof$response
  is_best <- isTRUE(all.equal(weight_lightgbm, best_weight))
  log_oof_model(
    "blend_lightgbm_catboost", response, NA_real_,
    list(weight_lightgbm = weight_lightgbm, weight_catboost = 1 - weight_lightgbm,
         residual_correlation = residual_correlation),
    save_predictions = is_best
  )
}

db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== OOF-Ensemble (5-fache CV) ===\n")
cat("Residualkorrelation LightGBM/CatBoost:", round(residual_correlation, 5), "\n")
cat("Beste Mischung: LightGBM", sprintf("%.0f%%", 100 * best_weight),
    "+ CatBoost", sprintf("%.0f%%", 100 * (1 - best_weight)), "\n")
print(ensemble_results[1:5])
cat("\nGespeichert:\n")
cat("Gewichte     :", ensemble_results_path, "\n")
cat("OOF-Prognosen:", ensemble_oof_predictions_path, "\n")
cat("Experiment-DB:", experiments_db_path, "\n")
