rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")

if (is.na(reference_submission_path) || !nzchar(reference_submission_path)) {
  stop("reference_submission_path in 000_config.R setzen, bevor dieser Check laeuft.")
}
if (!file.exists(reference_submission_path)) {
  stop("Referenzsubmission fehlt: ", reference_submission_path)
}
if (!file.exists(submission_path)) {
  stop("Aktuelle Submission fehlt: ", submission_path)
}

reference <- fread(reference_submission_path)
current <- fread(submission_path)

required_cols <- c(id_col, target_col)
if (!all(required_cols %in% names(reference))) {
  stop("Referenzsubmission braucht die Spalten: ", paste(required_cols, collapse = ", "))
}
if (!all(required_cols %in% names(current))) {
  stop("Aktuelle Submission braucht die Spalten: ", paste(required_cols, collapse = ", "))
}

match_idx <- match(current[[id_col]], reference[[id_col]])
if (anyNA(match_idx)) {
  stop("Nicht alle aktuellen IDs wurden in der Referenzsubmission gefunden.")
}

diff_target <- current[[target_col]] - reference[[target_col]][match_idx]
results <- data.table(
  current_file = normalizePath(submission_path, winslash = "/", mustWork = FALSE),
  reference_file = normalizePath(reference_submission_path, winslash = "/", mustWork = FALSE),
  same_row_count = nrow(current) == nrow(reference),
  same_id_order = identical(current[[id_col]], reference[[id_col]]),
  n_rows = nrow(current),
  n_different_predictions = sum(abs(diff_target) > 1e-12),
  share_different_predictions = mean(abs(diff_target) > 1e-12),
  max_abs_diff = max(abs(diff_target)),
  mean_abs_diff = mean(abs(diff_target)),
  rmse_diff = sqrt(mean(diff_target ^ 2))
)

fwrite(results, submission_diff_check_path)

cat("=== Submission Diff Check ===\n")
print(results)
if (results$n_different_predictions == 0) {
  cat("\nWarnung: Die aktuelle Submission ist prediction-identisch zur Referenz.\n")
}
cat("\nGespeichert:", submission_diff_check_path, "\n")
