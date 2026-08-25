rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3extralearners)
})

source("000_config.R")

# =====================================================================
# multilayer_stack_test.R -- 4. Bestaetigung des Multi-Layer-Stacking-Tests
# (siehe MLR3_Classifikation/TARGETS.md), erste auf der REGRESSIONSSEITE -
# strukturell am unterschiedlichsten zu den 3 Klassifikationslaeufen (health_
# condition/s6e6/s6e8: gemischtes Bild, mal gewinnt Mehrschichten, mal
# einlagig, mal keins der beiden gegen den bestehenden Greedy-Ensemble/
# Blend). Baut auf dem bestehenden 127-Pool auf (`pred_list`, numerische
# Vorhersagen statt Wahrscheinlichkeiten), kein neues Basis-Training.
# RMSE MINIMIEREN statt BAcc/AUC MAXIMIEREN - sonst identische Architektur:
# Layer-1 (3 Regressions-Meta-Learner-Familien) lernt aus den rohen Basis-
# Vorhersagen, Layer-2 (glmnet) lernt NUR aus den Layer-1-Vorhersagen.
ensemble_candidate_pool_path <- file.path(artifact_dir, "ensemble_candidate_pool.rds")
if (!file.exists(ensemble_candidate_pool_path)) {
  stop("Kandidaten-Pool fehlt. Erst 127_ensemble_candidate_pool.R ausfuehren.")
}
pool <- readRDS(ensemble_candidate_pool_path)
truth <- pool$truth
n_candidates <- length(pool$pred_list)
n_eval <- length(truth)
rmse <- function(truth_subset, pred) sqrt(mean((truth_subset - pred)^2))

set.seed(seed)
n <- n_eval
cuts <- round(cumsum(c(0.35, 0.35, 0.30)) * n)
idx_shuffled <- sample(seq_len(n))
layer1_ids <- idx_shuffled[seq_len(cuts[1])]
layer2_ids <- idx_shuffled[(cuts[1] + 1):cuts[2]]
confirmation_ids <- idx_shuffled[(cuts[2] + 1):n]
selection_ids <- c(layer1_ids, layer2_ids)
cat(sprintf("Eval-Split: %d Zeilen -> Layer1=%d, Layer2=%d, Bestaetigung=%d (Selektion gesamt=%d)\n",
            n_eval, length(layer1_ids), length(layer2_ids), length(confirmation_ids), length(selection_ids)))

truth_sel <- truth[selection_ids]; truth_l1 <- truth[layer1_ids]; truth_l2 <- truth[layer2_ids]; truth_conf <- truth[confirmation_ids]
preds_sel <- lapply(pool$pred_list, function(p) p[selection_ids])
preds_conf <- lapply(pool$pred_list, function(p) p[confirmation_ids])

# --- Baselines ---------------------------------------------------------------
rmse_sel_per_candidate <- vapply(preds_sel, rmse, numeric(1), truth_subset = truth_sel)
best_idx <- which.min(rmse_sel_per_candidate)
best_single_rmse <- rmse(truth_conf, preds_conf[[best_idx]])
mean_pred_conf_all <- Reduce(`+`, preds_conf) / n_candidates
blend_equal_rmse <- rmse(truth_conf, mean_pred_conf_all)

selected <- integer(0); running_sum_sel <- rep(0, length(selection_ids)); best_sel_rmse_so_far <- Inf; best_selected_at_step <- integer(0)
for (round in seq_len(ensemble_selection_rounds)) {
  losses <- vapply(seq_len(n_candidates), function(i) {
    trial_mean <- (running_sum_sel + preds_sel[[i]]) / (length(selected) + 1)
    rmse(truth_sel, trial_mean)
  }, numeric(1))
  best_idx_round <- which.min(losses)
  selected <- c(selected, best_idx_round)
  running_sum_sel <- running_sum_sel + preds_sel[[best_idx_round]]
  if (losses[best_idx_round] < best_sel_rmse_so_far) { best_sel_rmse_so_far <- losses[best_idx_round]; best_selected_at_step <- selected }
}
greedy_pred_conf <- Reduce(`+`, preds_conf[best_selected_at_step]) / length(best_selected_at_step)
greedy_rmse <- rmse(truth_conf, greedy_pred_conf)
cat(sprintf("\nBestes Einzelmodell: %.4f | Gleichgewichteter Blend: %.4f | Greedy Ensemble (%d Modelle): %.4f\n",
            best_single_rmse, blend_equal_rmse, length(unique(best_selected_at_step)), greedy_rmse))

# --- Flache Feature-Matrix (eine Spalte je Kandidat) ------------------------
feat_sel <- do.call(cbind, lapply(seq_along(preds_sel), function(i) {
  m <- matrix(preds_sel[[i]], ncol = 1); colnames(m) <- pool$labels[i]; m
}))
feat_conf <- do.call(cbind, lapply(seq_along(preds_conf), function(i) {
  m <- matrix(preds_conf[[i]], ncol = 1); colnames(m) <- pool$labels[i]; m
}))
build_meta_task <- function(feat_mat, truth_vec, id) {
  dt <- as.data.table(feat_mat); dt[, target := truth_vec]
  as_task_regr(dt, target = "target", id = id)
}

# --- Einlagiges Stacking (regularisierter linearer Meta-Learner, wie das
# urspruenglich getestete Logits-Stacking auf der Klassifikationsseite) -----
task_stack1_train <- build_meta_task(feat_sel, truth_sel, "stack1_train")
meta_glmnet <- lrn("regr.glmnet")
meta_glmnet$train(task_stack1_train)
pred_stack1 <- meta_glmnet$predict_newdata(as.data.table(feat_conf))
stack1_rmse <- rmse(truth_conf, pred_stack1$response)
cat(sprintf("Einlagiges Stacking (glmnet): %.4f\n", stack1_rmse))

# --- Mehrschichten-Stacking ---------------------------------------------------
task_layer1_train <- build_meta_task(feat_sel[seq_along(layer1_ids), , drop = FALSE], truth_l1, "layer1_train")
feat_layer2 <- feat_sel[(length(layer1_ids) + 1):nrow(feat_sel), , drop = FALSE]

layer1_learners <- list(
  glmnet = lrn("regr.glmnet"),
  ranger = lrn("regr.ranger", num.trees = 200, seed = seed),
  lightgbm = lrn("regr.lightgbm", num_iterations = 100)
)
for (nm in names(layer1_learners)) layer1_learners[[nm]]$train(task_layer1_train)

make_layer2_features <- function(newdata) {
  mats <- lapply(names(layer1_learners), function(nm) {
    p <- matrix(layer1_learners[[nm]]$predict_newdata(newdata)$response, ncol = 1)
    colnames(p) <- paste0("l1_", nm); p
  })
  do.call(cbind, mats)
}
feat_layer2_l2train <- make_layer2_features(as.data.table(feat_layer2))
feat_layer2_confirm <- make_layer2_features(as.data.table(feat_conf))

task_layer2_train <- build_meta_task(feat_layer2_l2train, truth_l2, "layer2_train")
meta_layer2 <- lrn("regr.glmnet")
meta_layer2$train(task_layer2_train)
pred_multilayer <- meta_layer2$predict_newdata(as.data.table(feat_layer2_confirm))
multilayer_rmse <- rmse(truth_conf, pred_multilayer$response)
cat(sprintf("Mehrschichten-Stacking (3 Layer-1 + 1 Layer-2): %.4f\n", multilayer_rmse))

# --- Zusammenfassung -----------------------------------------------------------
summary_dt <- data.table(
  approach = c("best_single", "equal_blend", "greedy_ensemble", "single_layer_stack", "multilayer_stack"),
  rmse_confirmation = c(best_single_rmse, blend_equal_rmse, greedy_rmse, stack1_rmse, multilayer_rmse)
)
setorder(summary_dt, rmse_confirmation)
fwrite(summary_dt, file.path(artifact_dir, "multilayer_stack_test_results.csv"))
cat("\n=== Zusammenfassung (Bestaetigungs-RMSE, niedriger = besser) ===\n"); print(summary_dt)
