# =====================================================================
# test_quantile_regression.R -- Verifikation von quantile_regression.R
# (train_quantile_learners()/quantile_predict_interval()/check_quantile_
# coverage()). Konstruierter HETEROSKEDASTISCHER Fall (Streuung waechst
# mit x) mit bekannter Ground Truth - genau der Fall, in dem Quantil-
# regression gegenueber Split-Conformals KONSTANTER Margin einen Vorteil
# haben sollte (schaerfere/schmalere Intervalle bei gleicher Coverage).
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3extralearners)
  library(mlr3pipelines)
})
project_dir <- normalizePath(".")
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "conformal_prediction.R"))
source(file.path(project_dir, "quantile_regression.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}

# --- Heteroskedastischer synthetischer Datensatz -----------------------
# y = x + Rauschen, dessen SD mit x waechst (0.2 bei x=0 bis 4 bei x=10).
set.seed(42)
n <- 6000
x <- runif(n, 0, 10)
noise_sd <- 0.2 + 0.4 * x
y <- x + rnorm(n, sd = noise_sd)
dt <- data.table(x = x, y = y)
task <- as_task_regr(dt, target = "y", id = "heteroskedastic_test")

set.seed(1)
idx <- sample(n)
train_rows <- idx[1:3000]
calib_rows <- idx[3001:4500]
eval_rows <- idx[4501:6000]

# --- Quantilregression: 90%-Intervall (5%/95%) --------------------------
q_learners <- train_quantile_learners(task, train_rows, lower_tau = 0.05, upper_tau = 0.95,
                                      num_iterations = 150)
check("beide Learner trainiert", !is.null(q_learners$lower_learner) && !is.null(q_learners$upper_learner))

q_interval <- quantile_predict_interval(q_learners, task, eval_rows)
check("Intervall hat eine Zeile je eval_rows", nrow(q_interval) == length(eval_rows))
check("kein verbleibendes Crossing nach Reparatur", all(q_interval$lower <= q_interval$upper))

eval_truth <- as.numeric(task$truth(eval_rows))
q_cov <- check_quantile_coverage(eval_truth, q_interval$lower, q_interval$upper, target_coverage = 0.90)
# Groessere Toleranz als bei Conformal beabsichtigt: Quantilregression hat
# KEINE verteilungsfreie Coverage-Garantie (siehe Kopfkommentar) - eine
# Abweichung von mehreren Prozentpunkten ist erwartbares Verhalten, kein Bug.
check("Quantil-Coverage im plausiblen Bereich (0.90 +/- 0.10)", abs(q_cov$empirical_coverage - 0.90) < 0.10)
cat(sprintf("  Quantil: Coverage=%.3f, mittlere Breite=%.3f\n", q_cov$empirical_coverage, q_cov$mean_width))

# --- Split-Conformal zum Vergleich: PUNKT-Modell + konstante Margin -----
point_learner <- make_encoded_imputed_learner(lrn("regr.lightgbm", num_iterations = 150))
point_learner$train(task, row_ids = train_rows)
calib_pred <- point_learner$predict(task, row_ids = calib_rows)$response
calib_truth <- as.numeric(task$truth(calib_rows))
margin <- split_conformal_calibrate(calib_truth, calib_pred, alpha = 0.10)

eval_pred <- point_learner$predict(task, row_ids = eval_rows)$response
c_cov <- check_conformal_coverage(eval_truth, eval_pred, margin, alpha = 0.10)
cat(sprintf("  Conformal: Coverage=%.3f, mittlere Breite=%.3f (konstante Margin=%.3f)\n",
            c_cov$empirical_coverage, c_cov$mean_width, margin))

check("beide Methoden erreichen brauchbare Coverage (>0.80)",
      q_cov$empirical_coverage > 0.80 && c_cov$empirical_coverage > 0.80)

# --- Kernhypothese: bei starker Heteroskedastizitaet ist die Quantil-
# Intervallbreite an der Stelle mit WENIG Rauschen schmaler als Conformals
# konstante Margin, und an der Stelle mit VIEL Rauschen breiter - waehrend
# Conformal ueberall gleich breit ist (per Konstruktion). ---------------
eval_x <- dt$x[eval_rows]
low_noise_idx <- which(eval_x < 2)   # noise_sd ~0.2-1.0
high_noise_idx <- which(eval_x > 8)  # noise_sd ~3.4-4.2
q_width_low <- mean(q_interval$upper[low_noise_idx] - q_interval$lower[low_noise_idx])
q_width_high <- mean(q_interval$upper[high_noise_idx] - q_interval$lower[high_noise_idx])
cat(sprintf("  Quantil-Breite bei x<2 (wenig Rauschen): %.3f | bei x>8 (viel Rauschen): %.3f\n",
            q_width_low, q_width_high))
check("Quantil-Intervalle sind LOKAL adaptiv (schmaler bei wenig, breiter bei viel Rauschen)",
      q_width_low < q_width_high)
check("Quantil-Intervall bei wenig Rauschen schmaler als Conformals konstante Margin",
      q_width_low < 2 * margin)

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
