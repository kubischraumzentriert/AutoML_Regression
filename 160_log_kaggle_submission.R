rm(list = ls())

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

# Vor Ausfuehrung die nach einer Kaggle-Einreichung gemeldeten Werte setzen.
kaggle_platform <- "kaggle"
kaggle_competition <- project_name
kaggle_status <- "submitted"
kaggle_public_score <- NA_real_
kaggle_private_score <- NA_real_

if (is.na(kaggle_public_score) && is.na(kaggle_private_score)) {
  stop("Vor Ausfuehrung mindestens einen Kaggle-Score im Skript setzen.")
}

if (!file.exists(submission_path)) {
  stop("Submission-Datei fehlt: ", submission_path)
}

db_con <- db_connect()
mconf_id <- db_get_latest_model_config_id(db_con, submission_model_algorithm)
if (is.na(mconf_id)) {
  DBI::dbDisconnect(db_con)
  stop("Kein finales Modell fuer Algorithmus '", submission_model_algorithm, "' gefunden.")
}

submission_id <- db_log_submission_result(
  db_con,
  mconf_id = mconf_id,
  platform = kaggle_platform,
  competition = kaggle_competition,
  file_path = submission_path,
  status = kaggle_status,
  metric_name = primary_measure_id,
  public_score = kaggle_public_score,
  private_score = kaggle_private_score,
  notes = "Vom Nutzer gemeldete Kaggle-Ergebnisse."
)
DBI::dbDisconnect(db_con)

cat("=== Kaggle-Submission protokolliert ===\n")
cat("Submission-ID:", submission_id, "\n")
cat("Public Score :", kaggle_public_score, "\n")
cat("Private Score:", kaggle_private_score, "\n")
