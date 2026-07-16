rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

train <- fread(train_path, select = target_col)
test <- fread(test_path, select = id_col)
training_mean <- mean(train[[target_col]])

submission <- data.table(id = test[[id_col]], response = training_mean)
setnames(submission, c("id", "response"), c(id_col, target_col))
fwrite(submission, mean_submission_path)

db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "165_mean_submission.R")
db_run_id <- db_create_run(
  db_con,
  db_wf_id,
  seed = seed,
  notes = "No-skill-Kalibrierung: konstante Vorhersage mit dem Trainingsmittelwert."
)
db_log_run_config(db_con, db_run_id, list(
  target_col = target_col,
  primary_measure_id = primary_measure_id,
  training_mean = training_mean
))
mconf_id <- db_create_model_config(
  db_con,
  db_run_id,
  task_type = "regr",
  algorithm = "target_mean",
  feature_set = "none",
  preprocessing = "none",
  task_id = paste0(target_col, "_full"),
  hyperparams = list(constant_prediction = training_mean)
)
db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("=== Mittelwert-Submission erzeugt ===\n")
cat("Zeilen:", nrow(submission), "\n")
cat("Trainingsmittelwert:", training_mean, "\n")
cat("Modellkonfiguration:", mconf_id, "\n")
cat("Gespeichert:", mean_submission_path, "\n")
