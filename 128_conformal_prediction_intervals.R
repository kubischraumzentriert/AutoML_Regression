rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")
source(file.path(project_dir, "conformal_prediction.R"))

# Split-Conformal Prediction Intervals (siehe conformal_prediction.R fuer
# Methodik/Referenzen). Baut auf dem `120_full_holdout_confirmation.R`-
# Artefakt auf, kein erneutes Training - loses Kopplungsmuster wie
# `125_segment_metrics.R`. Teilt den dortigen (vom Training unabhaengigen)
# Holdout weiter in eine Kalibrierungs- und eine Coverage-Pruefmenge -
# beide Teilmengen hat das Basismodell nie gesehen, das ist fuer
# Split-Conformal ausreichend (kein drittes Retraining noetig).
if (is.na(conformal_target_coverage)) {
  cat("Kein conformal_target_coverage in 000_config.R gesetzt. Conformal Prediction uebersprungen.\n")
  quit(save = "no", status = 0)
}
if (!file.exists(full_holdout_predictions_path)) {
  stop("Holdout-Predictions fehlen. Erst 120_full_holdout_confirmation.R ausfuehren.")
}

pred_dt <- fread(full_holdout_predictions_path)

prediction_col <- conformal_prediction_col
candidate_cols <- setdiff(names(pred_dt), c("row_id", "truth"))
if (is.na(prediction_col)) {
  # RMSE direkt aus den vorhandenen Predictions berechnen statt ueber den
  # `algorithm`-Spaltennamen in full_holdout_results_path zu matchen - deren
  # Benennung muss nicht 1:1 mit den Predictions-Spalten uebereinstimmen
  # (z.B. "lightgbm" vs. "lightgbm_selected"/"lightgbm_tuned", projektabhaengig).
  rmse_by_col <- vapply(candidate_cols, function(col) sqrt(mean((pred_dt$truth - pred_dt[[col]])^2)), numeric(1))
  prediction_col <- names(which.min(rmse_by_col))
  cat("conformal_prediction_col nicht gesetzt - verwende bestes Modell nach RMSE aus", full_holdout_predictions_path, ":", prediction_col, "\n")
}
if (!prediction_col %in% names(pred_dt)) {
  stop("Spalte '", prediction_col, "' nicht in ", full_holdout_predictions_path, " gefunden. Verfuegbar: ",
       paste(candidate_cols, collapse = ", "))
}

alpha <- 1 - conformal_target_coverage
set.seed(seed)
n <- nrow(pred_dt)
calib_idx <- sample(n, round(conformal_calib_ratio * n))
eval_idx <- setdiff(seq_len(n), calib_idx)

margin <- split_conformal_calibrate(pred_dt$truth[calib_idx], pred_dt[[prediction_col]][calib_idx], alpha)
coverage_check <- check_conformal_coverage(pred_dt$truth[eval_idx], pred_dt[[prediction_col]][eval_idx], margin, alpha)

intervals <- split_conformal_predict_interval(pred_dt[[prediction_col]][eval_idx], margin)
intervals[, `:=`(row_id = pred_dt$row_id[eval_idx], truth = pred_dt$truth[eval_idx])]
setcolorder(intervals, c("row_id", "truth", "pred", "lower", "upper"))
fwrite(intervals, conformal_intervals_path)

cat("=== Split-Conformal Prediction Intervals (Modell:", prediction_col, ") ===\n")
cat(sprintf("Kalibrierung: n=%d, Coverage-Pruefung: n=%d\n", length(calib_idx), length(eval_idx)))
cat(sprintf("Margin (symmetrisch): %.4f\n", margin))
cat(sprintf("Ziel-Coverage=%.3f  empirisch=%.3f  mittlere Intervallbreite=%.4f\n",
            coverage_check$target_coverage, coverage_check$empirical_coverage, coverage_check$mean_width))

coverage_gap <- abs(coverage_check$empirical_coverage - coverage_check$target_coverage)
if (coverage_gap > 0.05) {
  cat(sprintf("\nWARNUNG: empirische Coverage weicht > 0.05 vom Ziel ab (Gap=%.3f).\n", coverage_gap))
  cat("Moegliche Ursache: Distribution Shift zwischen Kalibrierungs- und Pruefmenge,\n")
  cat("oder zu kleine Kalibrierungsmenge. Vor Verwendung der Intervalle pruefen -\n")
  cat("siehe adversarial_validation/univariate_drift fuer eine Shift-Diagnose.\n")
} else {
  cat("\nCoverage nah am Ziel - unauffaellig.\n")
}
cat("\nGespeichert:", conformal_intervals_path, "\n")
