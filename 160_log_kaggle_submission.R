rm(list = ls())

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

# Vor Ausfuehrung die nach einer Kaggle-Einreichung gemeldeten Werte setzen.
kaggle_platform <- "kaggle"
kaggle_competition <- project_name
kaggle_status <- "submitted"
kaggle_public_score <- NA_real_
kaggle_private_score <- NA_real_
# "final_model" fuer `155_predict_submission.R`, "target_mean" fuer die
# Kalibrierungsdatei aus `165_mean_submission.R`.
submission_candidate <- "final_model"

if (is.na(kaggle_public_score) && is.na(kaggle_private_score)) {
  stop("Vor Ausfuehrung mindestens einen Kaggle-Score im Skript setzen.")
}

if (submission_candidate == "final_model") {
  submission_file_path <- submission_path
  model_algorithm <- submission_model_algorithm
  workflow_name <- "150_train_full_model.R"
  default_notes <- "Vom Nutzer gemeldete Kaggle-Ergebnisse des finalen Modells."
} else if (submission_candidate == "target_mean") {
  submission_file_path <- mean_submission_path
  model_algorithm <- "target_mean"
  workflow_name <- "165_mean_submission.R"
  default_notes <- "No-skill-Kalibrierung: Vorhersage ist der Trainingsmittelwert."
} else {
  stop("Unbekannter submission_candidate: ", submission_candidate)
}

if (!file.exists(submission_file_path)) {
  stop("Submission-Datei fehlt: ", submission_file_path)
}

db_con <- db_connect()
mconf_id <- db_get_latest_model_config_id(db_con, model_algorithm, workflow_name)
if (is.na(mconf_id)) {
  DBI::dbDisconnect(db_con)
  stop(
    "Keine Modellkonfiguration fuer Algorithmus '", model_algorithm,
    "' aus '", workflow_name, "' gefunden."
  )
}

submission_id <- db_log_submission_result(
  db_con,
  mconf_id = mconf_id,
  platform = kaggle_platform,
  competition = kaggle_competition,
  file_path = submission_file_path,
  status = kaggle_status,
  metric_name = primary_measure_id,
  public_score = kaggle_public_score,
  private_score = kaggle_private_score,
  notes = default_notes
)
DBI::dbDisconnect(db_con)

cat("=== Kaggle-Submission protokolliert ===\n")
cat("Kandidat     :", submission_candidate, "\n")
cat("Submission-ID:", submission_id, "\n")
cat("Public Score :", kaggle_public_score, "\n")
cat("Private Score:", kaggle_private_score, "\n")
