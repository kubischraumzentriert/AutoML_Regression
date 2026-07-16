if (!exists("project_dir")) {
  config_path <- normalizePath(sys.frame(1)$ofile)
  project_dir <- dirname(config_path)
}

train_path <- file.path(project_dir, "train.csv")
test_path <- file.path(project_dir, "test.csv")
sample_submission_path <- file.path(project_dir, "sample_submission.csv")

id_col <- "id"
target_col <- "accident_risk"
project_name <- "playground-series-s5e10-road-accident-risk"

# Kaggle bewertet die Vorhersagen mit RMSE; kleinere Werte sind besser.
primary_measure_id <- "regr.rmse"
baseline_measure_ids <- c("regr.rmse", "regr.mae", "regr.rsq")

seed <- 42
subset_fraction <- 0.10
validation_ratio <- 0.80
cv_folds <- 5
ranger_baseline_trees <- 100

task_id_prefix <- paste0(target_col, "_", subset_fraction * 100, "pct")

artifact_dir <- file.path(project_dir, "_artifacts")
experiments_db_path <- file.path(artifact_dir, "experiments.db")
task_train_small_path <- file.path(artifact_dir, "task_train_small.rds")
baseline_results_path <- file.path(artifact_dir, "baseline_results.csv")
baseline_benchmark_path <- file.path(artifact_dir, "baseline_benchmark.rds")
boosting_results_path <- file.path(artifact_dir, "boosting_results.csv")
boosting_benchmark_path <- file.path(artifact_dir, "boosting_benchmark.rds")
lightgbm_baseline_iterations <- 200
catboost_baseline_iterations <- 200
lightgbm_tuning_evals <- 20
lightgbm_tuning_search_results_path <- file.path(artifact_dir, "lightgbm_tuning_search_results.csv")
lightgbm_tuning_final_results_path <- file.path(artifact_dir, "lightgbm_tuning_final_results.csv")
lightgbm_tuning_instance_path <- file.path(artifact_dir, "lightgbm_tuning_instance.rds")
ensemble_results_path <- file.path(artifact_dir, "ensemble_results.csv")
ensemble_oof_predictions_path <- file.path(artifact_dir, "ensemble_oof_predictions.csv")

submission_model_name <- "ranger"
submission_path <- file.path(project_dir, "submission.csv")
prediction_bounds <- c(0, 1)

final_model_full_path <- function(model_name, run_id) {
  file.path(artifact_dir, paste0("final_model_", model_name, "_full_", run_id, ".rds"))
}

algorithm_from_learner_id <- function(learner_id) {
  algorithms <- c("rpart", "ranger", "lightgbm", "catboost")
  matched <- algorithms[vapply(algorithms, function(algorithm) {
    grepl(paste0("regr\\.", algorithm), learner_id)
  }, logical(1))]

  if (length(matched) != 1) {
    stop("Algorithmus konnte nicht aus learner_id abgeleitet werden: ", learner_id)
  }

  matched
}
