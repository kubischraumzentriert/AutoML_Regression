rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3extralearners)
  library(mlr3pipelines)
  library(mlr3tuning)
  library(mlr3mbo)
  library(paradox)
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

make_lightgbm_learner <- function(id) {
  learner <- make_encoded_imputed_learner(lrn(
    "regr.lightgbm",
    num_iterations = lightgbm_baseline_iterations,
    learning_rate = 0.05,
    seed = seed,
    verbose = -1
  ))
  learner$id <- id
  learner
}

search_space <- ps(
  regr.lightgbm.learning_rate = p_dbl(0.01, 0.12),
  regr.lightgbm.num_leaves = p_int(15, 127),
  regr.lightgbm.min_data_in_leaf = p_int(10, 150),
  regr.lightgbm.feature_fraction = p_dbl(0.6, 1.0),
  regr.lightgbm.bagging_fraction = p_dbl(0.6, 1.0)
)

tuning_instance <- ti(
  task = task_train_small,
  learner = make_lightgbm_learner("lightgbm_search"),
  resampling = rsmp("holdout", ratio = validation_ratio),
  measures = msr(primary_measure_id),
  search_space = search_space,
  terminator = trm("evals", n_evals = lightgbm_tuning_evals)
)

tnr("mbo")$optimize(tuning_instance)

archive_dt <- as.data.table(tuning_instance$archive$data)
list_cols <- names(archive_dt)[vapply(archive_dt, is.list, logical(1))]
fwrite(archive_dt[, setdiff(names(archive_dt), list_cols), with = FALSE], lightgbm_tuning_search_results_path)
saveRDS(tuning_instance, lightgbm_tuning_instance_path)

best_params <- tuning_instance$result_learner_param_vals
# Der GraphLearner liefert auch feste Pipeline-Parameter (darunter eine
# Funktion) zurueck. Fuer das Modell und die DB sind nur LightGBM-Parameter
# relevant und serialisierbar.
lightgbm_params <- best_params[grepl("^regr\\.lightgbm\\.", names(best_params))]
learner_default <- make_lightgbm_learner("lightgbm_default")
learner_tuned <- make_lightgbm_learner("lightgbm_tuned")
learner_tuned$param_set$values <- utils::modifyList(learner_tuned$param_set$values, lightgbm_params)

timed_benchmark <- run_timed_benchmark(
  tasks = list(task_train_small),
  learners = list(learner_default, learner_tuned),
  resampling = rsmp("cv", folds = cv_folds),
  measures = msrs(baseline_measure_ids)
)

final_results <- timed_benchmark$results[
  ,
  c("task_id", "learner_id", "resampling_id", baseline_measure_ids, "elapsed_seconds"),
  with = FALSE
]
fwrite(final_results, lightgbm_tuning_final_results_path)

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "100_lightgbm_tuning.R")
db_run_id <- db_create_run(db_con, db_wf_id, seed = seed, notes = "LightGBM-Tuning per Bayesian Optimization")
db_log_run_config(db_con, db_run_id, list(
  cv_folds = cv_folds,
  validation_ratio = validation_ratio,
  primary_measure_id = primary_measure_id,
  lightgbm_iterations = lightgbm_baseline_iterations,
  lightgbm_tuning_evals = lightgbm_tuning_evals
))

db_rsmp_search_id <- db_create_resampling(
  db_con, db_run_id, strategy = "holdout", ratio = validation_ratio, seed = seed
)
for (i in seq_len(nrow(archive_dt))) {
  row <- archive_dt[i]
  mconf_id <- db_create_model_config(
    db_con, db_run_id,
    task_type = "regr", algorithm = "lightgbm", feature_set = "raw",
    preprocessing = "impute_median_mode_one_hot", class_weight_power = NA_real_,
    task_id = task_train_small$id,
    hyperparams = list(
      num_iterations = lightgbm_baseline_iterations,
      learning_rate = row$regr.lightgbm.learning_rate,
      num_leaves = row$regr.lightgbm.num_leaves,
      min_data_in_leaf = row$regr.lightgbm.min_data_in_leaf,
      feature_fraction = row$regr.lightgbm.feature_fraction,
      bagging_fraction = row$regr.lightgbm.bagging_fraction
    )
  )
  db_log_metric_result(db_con, mconf_id, db_rsmp_search_id, primary_measure_id, row[[primary_measure_id]])
}

tuned_hyperparams <- lightgbm_params
names(tuned_hyperparams) <- sub("^regr\\.lightgbm\\.", "", names(tuned_hyperparams))
tuned_hyperparams$num_iterations <- lightgbm_baseline_iterations

db_log_timed_benchmark(
  db_con, db_run_id, timed_benchmark, measure_names = baseline_measure_ids,
  model_config_fn = function(row) list(
    task_type = "regr",
    algorithm = "lightgbm",
    feature_set = "raw",
    preprocessing = "impute_median_mode_one_hot",
    class_weight_power = NA_real_,
    task_id = row$task_id[1],
    hyperparams = if (grepl("tuned", row$learner_id[1])) tuned_hyperparams else list(
      num_iterations = lightgbm_baseline_iterations,
      learning_rate = 0.05
    )
  ),
  resampling_strategy = "cv", resampling_folds = cv_folds, resampling_seed = seed
)

db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== LightGBM-Tuning (RMSE, 5-fache CV) ===\n")
cat("Beste Suchkonfiguration:\n")
print(best_params)
cat("\nFinalvergleich:\n")
print(final_results)
cat("\nGespeichert:\n")
cat("Suchergebnisse:", lightgbm_tuning_search_results_path, "\n")
cat("Finalvergleich :", lightgbm_tuning_final_results_path, "\n")
cat("Tuning-Instanz :", lightgbm_tuning_instance_path, "\n")
cat("Experiment-DB  :", experiments_db_path, "\n")
