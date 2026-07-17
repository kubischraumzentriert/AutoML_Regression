rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3extralearners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "045_lightgbm_selection.R"))
source(file.path(project_dir, "db_logging.R"))

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

if (!submission_model_algorithm %in% c("ranger", "lightgbm")) {
  stop("Unterstuetzte finale Algorithmen: ranger, lightgbm.")
}

train <- fread(train_path)
train[, (id_col) := NULL]
feature_char_cols <- setdiff(names(train)[vapply(train, is.character, logical(1))], target_col)
train[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
train[, (target_col) := as.numeric(get(target_col))]
feature_levels <- lapply(train[, ..feature_char_cols], levels)

task_full <- as_task_regr(
  train,
  target = target_col,
  id = paste0(target_col, "_full_", submission_model_name)
)

if (identical(submission_model_algorithm, "ranger")) {
  learner_full <- make_imputed_learner(lrn(
    "regr.ranger", num.trees = ranger_baseline_trees,
    respect.unordered.factors = "order", seed = seed
  ))
  final_hyperparams <- list(num_trees = ranger_baseline_trees)
} else {
  lightgbm_selection <- read_lightgbm_selection()
  learner_full <- make_selected_lightgbm(lightgbm_selection)
  final_hyperparams <- selected_lightgbm_hyperparams(lightgbm_selection)
}

started <- proc.time()[["elapsed"]]
learner_full$train(task_full)
training_seconds <- proc.time()[["elapsed"]] - started

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "150_train_full_model.R")
db_run_id <- db_create_run(
  db_con, db_wf_id, seed = seed,
  notes = "Finales LightGBM auf dem vollen Datensatz; Variante per 100_lightgbm_tuning.R gewaehlt"
)
model_path <- final_model_full_path(submission_model_name, db_run_id)

saveRDS(
  list(learner = learner_full, feature_levels = feature_levels),
  model_path
)

db_create_model_config(
  db_con, db_run_id,
  task_type = "regr", algorithm = submission_model_algorithm, feature_set = "raw",
  preprocessing = "impute_median_mode_one_hot", class_weight_power = NA_real_,
  task_id = task_full$id,
  hyperparams = c(final_hyperparams, list(model_artifact_path = model_path, training_seconds = training_seconds))
)
db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== Finales Regressionstraining ===\n")
cat("Modell:", submission_model_name, "\n")
cat("Trainingszeit:", round(training_seconds, 1), "s\n")
cat("Gespeichert:", model_path, "\n")
cat("Experiment-DB:", experiments_db_path, "(run_id", db_run_id, ")\n")
