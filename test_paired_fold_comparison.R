# =====================================================================
# test_paired_fold_comparison.R -- Verifikation von
# paired_fold_comparison.R (extract_folds()/run_variant_on_folds()/
# paired_fold_delta()).
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
})
project_dir <- normalizePath(".")
source(file.path(project_dir, "modules", "paired_fold_comparison.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}
near <- function(a, b, tol = 1e-9) isTRUE(all(abs(a - b) < tol))

# --- extract_folds(): korrekte Anzahl/Inhalt aus einem CV-Resampling ---
set.seed(1)
dt <- data.table(x = rnorm(100), y = rnorm(100))
task <- as_task_regr(dt, target = "y")
rsmp_cv <- rsmp("cv", folds = 4L)
rsmp_cv$instantiate(task)
folds <- extract_folds(rsmp_cv)
check("extract_folds(): 4 Folds", length(folds) == 4L)
check("extract_folds(): jedes Fold hat train+test",
      all(vapply(folds, function(f) length(f$train) > 0 && length(f$test) > 0, logical(1))))
check("extract_folds(): train+test disjunkt je Fold",
      all(vapply(folds, function(f) length(intersect(f$train, f$test)) == 0, logical(1))))
check("extract_folds() bricht bei nicht-instantiiertem Resampling ab",
      inherits(tryCatch(extract_folds(rsmp("cv", folds = 3L)), error = function(e) e), "error"))

# --- run_variant_on_folds() + paired_fold_delta(): BEKANNTE Zahlen -----
# 3 Folds, deterministische variant_fn (keine echten Modelle - nur
# nachrechenbare Konstanten), um die Arithmetik exakt zu pruefen.
folds3 <- list(list(train = 1:2, test = 3:4), list(train = 5:6, test = 7:8),
              list(train = 9:10, test = 11:12))

baseline_fn <- function(train_ids, test_ids) c(rmse = 10, mae = 5)
variant_fn_better <- function(train_ids, test_ids) c(rmse = 8, mae = 4)  # konstant besser
# Ratio-Test: konstantes Delta -> SD=0 -> ratio ist NaN/Inf (Grenzfall,
# realistischer mit variierendem Delta je Fold pruefen:
variant_fn_varying <- local({
  i <- 0
  function(train_ids, test_ids) { i <<- i + 1; c(rmse = 10 + c(-1, 0, 3)[i], mae = 5) }
})

base_res <- run_variant_on_folds(folds3, baseline_fn)
check("run_variant_on_folds(): Matrix hat 3 Zeilen (Folds)", nrow(base_res) == 3L)
check("run_variant_on_folds(): Spaltennamen korrekt", identical(colnames(base_res), c("rmse", "mae")))
check("run_variant_on_folds(): Werte korrekt (alle Folds gleich)",
      near(base_res[, "rmse"], c(10, 10, 10)) && near(base_res[, "mae"], c(5, 5, 5)))

better_res <- run_variant_on_folds(folds3, variant_fn_better)
delta_better <- paired_fold_delta(base_res, better_res, label = "besser")
check("paired_fold_delta(): delta rmse = -2 (konstant besser)",
      near(delta_better[metrik == "rmse"]$delta, -2))
check("paired_fold_delta(): delta mae = -1",
      near(delta_better[metrik == "mae"]$delta, -1))

varying_res <- run_variant_on_folds(folds3, variant_fn_varying)
delta_varying <- paired_fold_delta(base_res, varying_res, metrics = "rmse", label = "variabel")
# Deltas je Fold: -1, 0, 3 -> Mittel = 0.6667, SD = sd(c(-1,0,3))
expected_mean <- mean(c(-1, 0, 3))
expected_sd <- sd(c(-1, 0, 3))
check("paired_fold_delta(): Mittel manuell nachgerechnet",
      near(delta_varying$delta, expected_mean))
check("paired_fold_delta(): SD manuell nachgerechnet",
      near(delta_varying$sd_fold_delta, expected_sd))
check("paired_fold_delta(): ratio = delta/sd",
      near(delta_varying$ratio, expected_mean / expected_sd))

# --- Integrationscheck: echtes mlr3-Modell auf einem echten Task -------
set.seed(2)
n <- 400
dt2 <- data.table(x1 = rnorm(n), x2 = rnorm(n))
dt2[, y := x1 + rnorm(n, sd = 0.1)]  # x1 ist informativ, x2 ist reines Rauschen
task2 <- as_task_regr(dt2, target = "y", id = "paired_fold_integration")
rsmp2 <- rsmp("cv", folds = 3L)
rsmp2$instantiate(task2)
folds2 <- extract_folds(rsmp2)

variant_with_x2 <- function(train_ids, test_ids) {
  lr <- lrn("regr.lm")
  lr$train(task2, row_ids = train_ids)
  p <- lr$predict(task2, row_ids = test_ids)
  c(rmse = sqrt(mean((p$truth - p$response)^2)))
}
variant_without_x2 <- function(train_ids, test_ids) {
  tsk_sub <- task2$clone(deep = TRUE)$select("x1")
  lr <- lrn("regr.lm")
  lr$train(tsk_sub, row_ids = train_ids)
  p <- lr$predict(tsk_sub, row_ids = test_ids)
  c(rmse = sqrt(mean((p$truth - p$response)^2)))
}

res_with <- run_variant_on_folds(folds2, variant_with_x2)
res_without <- run_variant_on_folds(folds2, variant_without_x2)
delta_x2 <- paired_fold_delta(res_with, res_without, label = "ohne x2 (reines Rauschen entfernt)")
cat("\nIntegrationscheck (x2 ist reines Rauschen, sollte kaum Unterschied machen):\n")
print(delta_x2)
check("Integrationscheck: Entfernen von Rauschen-Feature x2 macht kaum Unterschied (|delta| < 0.05)",
      abs(delta_x2$delta) < 0.05)

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
