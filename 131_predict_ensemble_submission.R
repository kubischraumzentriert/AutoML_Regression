rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3extralearners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

# Analog zu 155_predict_submission.R, aber fuer das Greedy-Ensemble aus
# 130_train_full_ensemble.R: mittelt die Vorhersagen mehrerer Mitglieder
# GEWICHTET (Gewicht = Selektionshaeufigkeit aus 129) statt eines einzelnen
# Learners. Schreibt nach submission_ensemble_path, NICHT submission_path -
# ueberschreibt die bestehende Einzelmodell-Submission nicht.
db_con <- db_connect()
model_path <- db_get_latest_model_artifact_path(db_con, "ensemble", workflow_name = "130_train_full_ensemble.R")
DBI::dbDisconnect(db_con)

if (is.na(model_path) || !file.exists(model_path)) {
  source(file.path(project_dir, "130_train_full_ensemble.R"))
  db_con <- db_connect()
  model_path <- db_get_latest_model_artifact_path(db_con, "ensemble", workflow_name = "130_train_full_ensemble.R")
  DBI::dbDisconnect(db_con)
}

model_bundle <- readRDS(model_path)
members <- model_bundle$members
target_col_name <- model_bundle$target_col_name

test <- fread(test_path)
test_ids <- test[[id_col]]
test[, (id_col) := NULL]
for (col in names(model_bundle$feature_levels)) {
  test[[col]] <- factor(test[[col]], levels = model_bundle$feature_levels[[col]])
}

cat(sprintf("=== Ensemble-Vorhersage: %d Mitglieder ===\n", length(members)))
total_weight <- sum(vapply(members, `[[`, integer(1), "weight"))
pred_sum <- rep(0, nrow(test))
for (member in members) {
  pred <- member$learner$predict_newdata(test)$response
  cat(sprintf("  %s (Gewicht %d/%d)\n", member$label, member$weight, total_weight))
  pred_sum <- pred_sum + pred * member$weight
}
predictions <- pred_sum / total_weight
predictions <- pmin(prediction_bounds[2], pmax(prediction_bounds[1], predictions))

if (anyNA(predictions)) {
  stop("Die Ensemble-Submission enthaelt fehlende Vorhersagen.")
}

submission <- data.table(id = test_ids, response = predictions)
setnames(submission, "id", id_col)
setnames(submission, "response", target_col_name)
fwrite(submission, submission_ensemble_path)

cat("\n=== Ensemble-Submission erzeugt ===\n")
cat("Zeilen:", nrow(submission), "\n")
print(summary(submission[[target_col_name]]))
cat("\nGespeichert:", submission_ensemble_path, "\n")
cat("(bestehende submission.csv/Einzelmodell unveraendert)\n")
