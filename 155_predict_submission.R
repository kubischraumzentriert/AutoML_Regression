rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
})

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

db_con <- db_connect()
model_path <- db_get_latest_model_artifact_path(db_con, submission_model_name)
DBI::dbDisconnect(db_con)

if (is.na(model_path) || !file.exists(model_path)) {
  source(file.path(project_dir, "150_train_full_model.R"))
  db_con <- db_connect()
  model_path <- db_get_latest_model_artifact_path(db_con, submission_model_name)
  DBI::dbDisconnect(db_con)
}

model_bundle <- readRDS(model_path)
test <- fread(test_path)
test_ids <- test[[id_col]]
test[, (id_col) := NULL]

for (col in names(model_bundle$feature_levels)) {
  test[[col]] <- factor(test[[col]], levels = model_bundle$feature_levels[[col]])
}

predictions <- model_bundle$learner$predict_newdata(test)$response
predictions <- pmin(prediction_bounds[2], pmax(prediction_bounds[1], predictions))

if (anyNA(predictions)) {
  stop("Die Submission enthaelt fehlende Vorhersagen.")
}

submission <- data.table(id = test_ids, response = predictions)
setnames(submission, "id", id_col)
setnames(submission, "response", target_col)
fwrite(submission, submission_path)

cat("=== Regression-Submission erzeugt ===\n")
cat("Zeilen:", nrow(submission), "\n")
print(summary(submission[[target_col]]))
cat("\nGespeichert:", submission_path, "\n")
