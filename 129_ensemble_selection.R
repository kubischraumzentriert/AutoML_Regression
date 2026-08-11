rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")
source(file.path(project_dir, "db_logging.R"))

# Caruana-Greedy-Ensemble-Selection (Caruana et al. 2004) - siehe
# REFERENZ_ENSEMBLE_SELECTION.md im Klassifikations-Template fuer den
# theoretischen Hintergrund (identisch, aufgabentyp-unabhaengig). Baut auf
# dem `127_ensemble_candidate_pool.R`-Artefakt auf, kein erneutes Training.
# Anders als bei der Klassifikation (BAcc, MAXIMIEREN) wird hier RMSE
# MINIMIERT - der Selektionsschritt sucht in jeder Runde den Kandidaten, der
# den groessten RMSE-Rueckgang bringt.
if (!file.exists(ensemble_candidate_pool_path)) {
  stop("Kandidaten-Pool fehlt. Erst 127_ensemble_candidate_pool.R ausfuehren.")
}
pool <- readRDS(ensemble_candidate_pool_path)
truth <- pool$truth
n_candidates <- length(pool$pred_list)
n_eval <- length(truth)

# Weiterer Split des 120-Test-Splits in Selektions- und Bestaetigungsmenge -
# analog zur Klassifikation, hier ohne Klassenstratifizierung (kontinuierliche
# Zielgroesse).
set.seed(seed)
selection_idx <- sample(n_eval, round(ensemble_selection_valid_ratio * n_eval))
confirmation_idx <- setdiff(seq_len(n_eval), selection_idx)
cat(sprintf("Eval-Split (120): %d Zeilen -> Selektion=%d, Bestaetigung=%d\n",
            n_eval, length(selection_idx), length(confirmation_idx)))

rmse <- function(truth_subset, pred) sqrt(mean((truth_subset - pred)^2))

truth_sel <- truth[selection_idx]
truth_conf <- truth[confirmation_idx]
preds_sel <- lapply(pool$pred_list, function(p) p[selection_idx])
preds_conf <- lapply(pool$pred_list, function(p) p[confirmation_idx])

# --- Bestes Einzelmodell (nach Selektionsmenge) -----------------------------
rmse_sel_per_candidate <- vapply(preds_sel, rmse, numeric(1), truth_subset = truth_sel)
best_idx <- which.min(rmse_sel_per_candidate)
best_single_rmse_conf <- rmse(truth_conf, preds_conf[[best_idx]])
cat(sprintf("\nBestes Einzelmodell (Selektions-RMSE): %s | Selektion=%.4f | Bestaetigung=%.4f\n",
            pool$labels[best_idx], rmse_sel_per_candidate[best_idx], best_single_rmse_conf))

# --- Gleichgewichteter Blend (alle Kandidaten) ------------------------------
mean_pred_conf_all <- Reduce(`+`, preds_conf) / n_candidates
blend_equal_rmse_conf <- rmse(truth_conf, mean_pred_conf_all)
cat(sprintf("Gleichgewichteter Blend (alle %d): Bestaetigung=%.4f\n", n_candidates, blend_equal_rmse_conf))

# --- Caruana Greedy Ensemble Selection (auf der Selektionsmenge, RMSE MINIMIEREN)
cat("\n=== Caruana Greedy Ensemble Selection (Selektionsmenge, RMSE minimieren) ===\n")
selected <- integer(0)
running_sum_sel <- rep(0, length(selection_idx))
best_sel_rmse_so_far <- Inf
best_selected_at_step <- integer(0)
for (round in seq_len(ensemble_selection_rounds)) {
  losses <- vapply(seq_len(n_candidates), function(i) {
    trial_mean <- (running_sum_sel + preds_sel[[i]]) / (length(selected) + 1)
    rmse(truth_sel, trial_mean)
  }, numeric(1))
  best_gain_idx <- which.min(losses)
  selected <- c(selected, best_gain_idx)
  running_sum_sel <- running_sum_sel + preds_sel[[best_gain_idx]]
  if (losses[best_gain_idx] < best_sel_rmse_so_far) {
    best_sel_rmse_so_far <- losses[best_gain_idx]
    best_selected_at_step <- selected
  }
}
cat(sprintf("Beste Selektions-RMSE waehrend der Selektion: %.4f bei Ensemblegroesse %d\n",
            best_sel_rmse_so_far, length(best_selected_at_step)))
sel_counts <- table(pool$labels[best_selected_at_step])
cat("Ausgewaehlte Modelle (mit Haeufigkeit):\n"); print(sel_counts)

ensemble_pred_conf <- Reduce(`+`, preds_conf[best_selected_at_step]) / length(best_selected_at_step)
ensemble_rmse_conf <- rmse(truth_conf, ensemble_pred_conf)
cat(sprintf("\nGreedy-Ensemble Bestaetigungs-RMSE: %.4f\n", ensemble_rmse_conf))

# --- Zusammenfassung ---------------------------------------------------------
summary_dt <- data.table(
  approach = c("best_single", "equal_blend", "greedy_ensemble"),
  n_models = c(1L, n_candidates, length(best_selected_at_step)),
  rmse_confirmation = c(best_single_rmse_conf, blend_equal_rmse_conf, ensemble_rmse_conf)
)
setorder(summary_dt, rmse_confirmation)
fwrite(summary_dt, ensemble_selection_results_path)

cat("\n=== Zusammenfassung (Bestaetigungs-RMSE, unabhaengig von Selektion) ===\n")
print(summary_dt)
cat("\nGespeichert:", ensemble_selection_results_path, "\n")

# --- Experiment-Tracking (SQLite) ------------------------------------------
db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "129_ensemble_selection.R")
db_run_id <- db_create_run(db_con, db_wf_id, seed = seed, notes = sprintf(
  "Caruana Greedy Ensemble Selection auf %d Kandidaten (%s)", n_candidates, paste(unique(pool$families), collapse = "/")
))
db_log_run_config(db_con, db_run_id, list(
  n_candidates = n_candidates, ensemble_selection_rounds = ensemble_selection_rounds,
  ensemble_selection_valid_ratio = ensemble_selection_valid_ratio,
  selected_ensemble_size = length(best_selected_at_step)
))
db_rsmp_id <- db_create_resampling(db_con, db_run_id, strategy = "custom_split", ratio = ensemble_selection_valid_ratio, seed = seed)

for (i in seq_len(nrow(summary_dt))) {
  mconf_id <- db_create_model_config(
    db_con, db_run_id, task_type = "regr", algorithm = summary_dt$approach[i],
    feature_set = "raw", preprocessing = "impute_median_mode", class_weight_power = NA_real_,
    task_id = pool$target_col_name, hyperparams = list(n_models = summary_dt$n_models[i])
  )
  db_log_metric_result(db_con, mconf_id, db_rsmp_id, "regr.rmse", summary_dt$rmse_confirmation[i])
}

db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)
cat("Experiment-DB   :", experiments_db_path, "\n")
