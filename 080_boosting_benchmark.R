rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3extralearners)
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
  make_encoded_imputed_learner(lrn(
    "regr.lightgbm",
    num_iterations = lightgbm_baseline_iterations,
    learning_rate = 0.05,
    seed = seed,
    verbose = -1
  )),
  make_encoded_imputed_learner(lrn(
    "regr.catboost",
    iterations = catboost_baseline_iterations,
    learning_rate = 0.05,
    random_seed = seed,
    logging_level = "Silent",
    allow_writing_files = FALSE
  ))
)

timed_benchmark <- run_timed_benchmark(
  tasks = list(task_train_small),
  learners = learners,
  resampling = rsmp("cv", folds = cv_folds),
  measures = msrs(baseline_measure_ids)
)

boosting_results <- timed_benchmark$results[
  ,
  c("task_id", "learner_id", "resampling_id", baseline_measure_ids, "elapsed_seconds"),
  with = FALSE
]

fwrite(boosting_results, boosting_results_path)
saveRDS(timed_benchmark$benchmarks, boosting_benchmark_path)

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "080_boosting_benchmark.R")
db_run_id <- db_create_run(db_con, db_wf_id, seed = seed, notes = "Boosting-Benchmark: LightGBM und CatBoost (je 200 Iterationen)")
db_log_run_config(db_con, db_run_id, list(
  cv_folds = cv_folds,
  primary_measure_id = primary_measure_id,
  lightgbm_iterations = lightgbm_baseline_iterations,
  catboost_iterations = catboost_baseline_iterations,
  encoded_categoricals = TRUE
))

db_log_timed_benchmark(
  db_con, db_run_id, timed_benchmark, measure_names = baseline_measure_ids,
  model_config_fn = function(row) list(
    task_type = "regr",
    algorithm = algorithm_from_learner_id(row$learner_id[1]),
    feature_set = "raw",
    preprocessing = "impute_median_mode_one_hot",
    class_weight_power = NA_real_,
    task_id = row$task_id[1]
  ),
  resampling_strategy = "cv", resampling_folds = cv_folds, resampling_seed = seed
)

db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== Boosting-Benchmark (5-fache CV) ===\n")
print(boosting_results)
cat("\nGespeichert:\n")
cat("Ergebnisse:", boosting_results_path, "\n")
cat("Benchmark :", boosting_benchmark_path, "\n")
cat("Experiment-DB:", experiments_db_path, "\n")
