rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3extralearners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "quantile_regression.R"))

# Quantilregression als Alternative/Ergaenzung zu 128_conformal_prediction_
# intervals.R (siehe quantile_regression.R fuer Methodik). Nutzt DIESELBE
# `conformal_target_coverage`/`conformal_calib_ratio`-Konfiguration wie 128,
# um direkt vergleichbare Coverage/Breite-Zahlen zu erzeugen - beide Skripte
# sind eigenstaendig lauffaehig, aber fuer den Methodenvergleich gedacht,
# auf demselben Holdout-Split wie 120_full_holdout_confirmation.R.
if (is.na(conformal_target_coverage)) {
  cat("Kein conformal_target_coverage in 000_config.R gesetzt. Quantilregression uebersprungen.\n")
  quit(save = "no", status = 0)
}
if (!file.exists(full_holdout_predictions_path)) {
  stop("Holdout-Predictions fehlen. Erst 120_full_holdout_confirmation.R ausfuehren.")
}

# --- Denselben Task + denselben Holdout-Split wie 120 REBUILDEN (loses
# Kopplungsmuster, kein gespeichertes Task-Objekt noetig - deterministisch
# ueber denselben Seed/Ratio). ------------------------------------------
train <- fread(train_path)
train[, (id_col) := NULL]
feature_char_cols <- setdiff(names(train)[vapply(train, is.character, logical(1))], target_col)
train[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
train[, (target_col) := as.numeric(get(target_col))]
task_full <- as_task_regr(train, target = target_col, id = paste0(target_col, "_quantile_holdout"))

set.seed(full_holdout_seed)
resampling <- rsmp("holdout", ratio = full_holdout_train_ratio)
resampling$instantiate(task_full)
train_ids <- resampling$train_set(1)
test_ids <- resampling$test_set(1)

alpha <- 1 - conformal_target_coverage
lower_tau <- alpha / 2
upper_tau <- 1 - alpha / 2

cat(sprintf("=== Quantilregression (lower_tau=%.3f, upper_tau=%.3f) ===\n", lower_tau, upper_tau))
learners <- train_quantile_learners(task_full, train_ids, lower_tau = lower_tau, upper_tau = upper_tau)

# --- Auf demselben `eval_idx`-Teil des Holdouts auswerten, den auch 128
# fuer die Coverage-Pruefung nutzt (identischer Seed/Ratio) - direkt
# vergleichbare Zahlen, keine Kalibrierungsmenge noetig (struktureller
# Vorteil der Quantilregression: sie braucht keine). --------------------
pred_dt <- fread(full_holdout_predictions_path)
set.seed(seed)
n <- nrow(pred_dt)
calib_idx <- sample(n, round(conformal_calib_ratio * n))
eval_idx <- setdiff(seq_len(n), calib_idx)

eval_row_ids <- pred_dt$row_id[eval_idx]
interval <- quantile_predict_interval(learners, task_full, eval_row_ids)
interval[, `:=`(row_id = eval_row_ids, truth = pred_dt$truth[eval_idx])]
setcolorder(interval, c("row_id", "truth", "lower", "upper", "crossed"))

coverage_check <- check_quantile_coverage(interval$truth, interval$lower, interval$upper,
                                          target_coverage = conformal_target_coverage)

quantile_intervals_path <- file.path(artifact_dir, "quantile_prediction_intervals.csv")
fwrite(interval, quantile_intervals_path)

cat(sprintf("Coverage-Pruefmenge: n=%d (identisch zu 128s eval_idx)\n", nrow(interval)))
cat(sprintf("Quantil-Crossing repariert: %d von %d Zeilen\n", sum(interval$crossed), nrow(interval)))
cat(sprintf("Ziel-Coverage=%.3f  empirisch=%.3f  mittlere Intervallbreite=%.4f\n",
            coverage_check$target_coverage, coverage_check$empirical_coverage, coverage_check$mean_width))

coverage_gap <- abs(coverage_check$empirical_coverage - coverage_check$target_coverage)
if (coverage_gap > 0.05) {
  cat(sprintf("\nHINWEIS: empirische Coverage weicht > 0.05 vom Ziel ab (Gap=%.3f).\n", coverage_gap))
  cat("Anders als bei Split-Conformal ist das KEIN Alarmzeichen fuer Distribution Shift -\n")
  cat("Quantilregression hat keine verteilungsfreie Coverage-Garantie, die Abweichung kann\n")
  cat("schlicht Modellguete widerspiegeln. Gegen 128_conformal_prediction_intervals.R auf\n")
  cat("denselben Daten vergleichen: Conformal validiert die GUELTIGKEIT, Quantilregression\n")
  cat("kann bei Heteroskedastizitaet SCHAERFERE (lokal adaptive) Intervalle liefern.\n")
} else {
  cat("\nCoverage nah am Ziel.\n")
}
cat("\nGespeichert:", quantile_intervals_path, "\n")
