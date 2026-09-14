# =====================================================================
# test_feature_importance_stability.R -- Verifikation von
# feature_importance_stability.R (collect_importance_across_folds()/
# pairwise_rank_correlation()/pairwise_topk_overlap()/feature_
# importance_stability_report()). Identisch zu den testthat-Faellen im
# Klassifikations-Template, nur im hiesigen manuellen Teststil.
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
})
project_dir <- normalizePath(".")
source(file.path(project_dir, "feature_importance_stability.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}
near <- function(a, b, tol = 1e-9) isTRUE(all(abs(a - b) < tol))

# --- collect_importance_across_folds(): Matrix + 0 statt NA ------------
imp_list <- list(c(a = 5, b = 3, c = 1), c(a = 6, b = 2, c = 0), c(a = 4, b = 4))
i <- 0
train_fn0 <- function(train_ids) {
  i <<- i + 1
  structure(list(importance = function() imp_list[[i]]), class = "fake_learner")
}
folds0 <- list(list(train = 1:5), list(train = 6:10), list(train = 11:15))
mat0 <- collect_importance_across_folds(folds0, train_fn0)
check("Matrix hat korrekte Dimension", all(dim(mat0) == c(3, 3)))
check("Werte korrekt uebernommen", near(mat0["a", ], c(5, 6, 4)))
check("fehlendes Feature -> 0, nicht NA", near(unname(mat0["c", 3]), 0))

# --- pairwise_rank_correlation(): identische Rangfolge -> 1 ------------
mat1 <- cbind(f1 = c(a = 10, b = 5, c = 1), f2 = c(a = 20, b = 8, c = 2), f3 = c(a = 15, b = 6, c = 0.5))
r1 <- pairwise_rank_correlation(mat1)
check("identische Rangfolge: 3 Paare", nrow(r1$pairwise) == 3L)
check("identische Rangfolge: mean_correlation = 1", near(r1$mean_correlation, 1))

# --- pairwise_rank_correlation(): umgekehrte Rangfolge -> -1 -----------
mat2 <- cbind(f1 = c(a = 10, b = 5, c = 1), f2 = c(a = 1, b = 5.5, c = 10))
r2 <- pairwise_rank_correlation(mat2)
check("umgekehrte Rangfolge: mean_correlation = -1", near(r2$mean_correlation, -1))

# --- pairwise_topk_overlap(): identisch -> 1, disjunkt -> 0 -------------
mat3 <- cbind(f1 = c(a = 10, b = 8, c = 1, d = 0.5), f2 = c(a = 20, b = 15, c = 0.1, d = 0.05))
check("identische Top-k: Jaccard = 1", near(pairwise_topk_overlap(mat3, k = 2)$mean_jaccard, 1))
mat4 <- cbind(f1 = c(a = 10, b = 8, c = 1, d = 0.5), f2 = c(a = 0.1, b = 0.2, c = 10, d = 8))
check("disjunkte Top-k: Jaccard = 0", near(pairwise_topk_overlap(mat4, k = 2)$mean_jaccard, 0))

# --- feature_importance_stability_report(): stabiles Feature -----------
mat5 <- cbind(f1 = c(a = 10, b = 5, c = 1), f2 = c(a = 10, b = 1, c = 5), f3 = c(a = 10, b = 5, c = 1))
rep5 <- feature_importance_stability_report(mat5, k = 1)
a_row <- rep5[feature == "a"]
check("stabiles Feature: sd_rank = 0", near(a_row$sd_rank, 0))
check("stabiles Feature: topk_share = 1", near(a_row$topk_share, 1))
check("Sortierung: bestes Feature zuerst", rep5$feature[1] == "a")

# --- Integrationscheck: echtes mlr3-Modell, starkes vs. Rauschen -------
set.seed(1)
n <- 1500
noise_dt <- as.data.table(matrix(rnorm(n * 10), ncol = 10))
setnames(noise_dt, paste0("x_noise", 1:10))
dt6 <- data.table(x_strong = rnorm(n))
dt6 <- cbind(dt6, noise_dt)
dt6[, y := x_strong + rnorm(n, sd = 0.3)]  # Regression statt Klassifikation
task6 <- as_task_regr(dt6, target = "y", id = "importance_stability_test")

set.seed(2)
rsmp_cv <- rsmp("cv", folds = 5L)
rsmp_cv$instantiate(task6)
folds6 <- lapply(seq_len(rsmp_cv$iters), function(i) list(train = rsmp_cv$train_set(i)))

train_fn6 <- function(train_ids) {
  lr <- lrn("regr.ranger", importance = "impurity")
  lr$train(task6, row_ids = train_ids)
  lr
}
mat6 <- collect_importance_across_folds(folds6, train_fn6)
report6 <- feature_importance_stability_report(mat6, k = 1)
strong_row <- report6[feature == "x_strong"]
noise_rows <- report6[feature != "x_strong"]
check("Integrationscheck: x_strong Rang 1", near(strong_row$mean_rank, 1))
check("Integrationscheck: x_strong sd_rank = 0", near(strong_row$sd_rank, 0))
check("Integrationscheck: Rauschen im Mittel instabiler", mean(noise_rows$sd_rank) > strong_row$sd_rank)

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
