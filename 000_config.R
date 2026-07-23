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
full_holdout_train_ratio <- 0.80
full_holdout_seed <- 2026
ranger_baseline_trees <- 100

task_id_prefix <- paste0(target_col, "_", subset_fraction * 100, "pct")

artifact_dir <- file.path(project_dir, "_artifacts")
experiments_db_path <- file.path(artifact_dir, "experiments.db")
task_train_small_path <- file.path(artifact_dir, "task_train_small.rds")
signal_diagnostics_path <- file.path(artifact_dir, "signal_diagnostics.csv")
signal_correlations_path <- file.path(artifact_dir, "signal_correlations.csv")
feature_availability_summary_path <- file.path(artifact_dir, "feature_availability_summary.csv")
feature_availability_missingness_path <- file.path(artifact_dir, "feature_availability_missingness.csv")
feature_availability_report_path <- file.path(artifact_dir, "feature_availability_report.txt")
feature_availability_sentinel_values <- c(-999, -9999, 999, 9999)

adversarial_validation_sample_n <- 150000L
adversarial_validation_folds <- 3L
adversarial_validation_results_path <- file.path(artifact_dir, "adversarial_validation_results.csv")
adversarial_validation_prediction_path <- file.path(artifact_dir, "adversarial_validation_predictions.csv")
adversarial_exclude_cols <- c(id_col, target_col)

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
lightgbm_selection_path <- file.path(artifact_dir, "lightgbm_selection.rds")
ensemble_results_path <- file.path(artifact_dir, "ensemble_results.csv")
ensemble_oof_predictions_path <- file.path(artifact_dir, "ensemble_oof_predictions.csv")
ensemble_lightgbm_weight <- 0.60
full_holdout_results_path <- file.path(artifact_dir, "full_holdout_confirmation_results.csv")
full_holdout_predictions_path <- file.path(artifact_dir, "full_holdout_confirmation_predictions.csv")
segment_metric_cols <- character()
segment_metrics_path <- file.path(artifact_dir, "segment_metrics.csv")

# `100_lightgbm_tuning.R` bestimmt die Variante per CV und speichert sie in
# `lightgbm_selection_path`; nachfolgende Schritte lesen dieses Artefakt.
submission_model_name <- "lightgbm_selected"
submission_model_algorithm <- "lightgbm"
submission_path <- file.path(project_dir, "submission.csv")
mean_submission_path <- file.path(project_dir, "submission_mean.csv")
prediction_bounds <- c(0, 1)
reference_submission_path <- NA_character_
submission_diff_check_path <- file.path(artifact_dir, "submission_diff_check.csv")

# Externe Quellen fuer Feature-Engineering bewusst klassifizieren. Werte:
# "allowed_input", "inspiration_only", "blocked_or_unclear".
external_source_policy <- data.frame(
  source = character(),
  policy = character(),
  notes = character(),
  stringsAsFactors = FALSE
)

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
