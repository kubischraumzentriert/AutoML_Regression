rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")
source(file.path(project_dir, "sanity_checks.R"))

# Modell-Sanity-Checks (Perturbation/Invarianz/Directional Expectation nach
# Huyen 2022 Kap. 6) - siehe REFERENZ_MODEL_SANITY_CHECKS.md im
# Klassifikations-Template fuer den theoretischen Hintergrund (identisch,
# aufgabentyp-unabhaengig). Baut auf dem `120_full_holdout_confirmation.R`-
# Artefakt auf, kein erneutes Training - loses Kopplungsmuster wie
# `125_segment_metrics.R`/`128_conformal_prediction_intervals.R`.
if (!length(perturbation_test_cols) && !length(invariance_test_cols) && !length(directional_expectation_specs)) {
  cat("Keine perturbation_test_cols/invariance_test_cols/directional_expectation_specs in 000_config.R gesetzt. Sanity-Checks uebersprungen.\n")
  quit(save = "no", status = 0)
}
if (!file.exists(full_holdout_models_path)) {
  stop("Holdout-Modelle fehlen. Erst 120_full_holdout_confirmation.R ausfuehren (aktuelle Version, die full_holdout_models_path speichert).")
}

models <- readRDS(full_holdout_models_path)
eval_dt <- as.data.frame(models$eval_data)
truth <- models$truth

predict_lightgbm <- function(nd) models$learner_lightgbm$predict_newdata(nd)$response
predict_catboost <- function(nd) models$learner_catboost$predict_newdata(nd)$response
predict_blend <- function(nd) {
  models$blend_weight_lightgbm * predict_lightgbm(nd) + (1 - models$blend_weight_lightgbm) * predict_catboost(nd)
}

model_choice <- sanity_check_model
if (is.na(model_choice)) {
  rmse_fn <- function(pred) sqrt(mean((truth - pred)^2))
  rmse_by_model <- c(
    lightgbm = rmse_fn(predict_lightgbm(eval_dt)),
    catboost = rmse_fn(predict_catboost(eval_dt)),
    blend = rmse_fn(predict_blend(eval_dt))
  )
  model_choice <- names(which.min(rmse_by_model))
  cat("sanity_check_model nicht gesetzt - verwende bestes Modell nach RMSE:", model_choice, "\n")
}
predict_response <- switch(model_choice,
  lightgbm = predict_lightgbm, catboost = predict_catboost, blend = predict_blend,
  stop("sanity_check_model muss 'lightgbm'/'catboost'/'blend'/NA sein, war: ", model_choice)
)

results <- list()

# --- 1) Perturbation ---------------------------------------------------------
if (length(perturbation_test_cols)) {
  missing_cols <- setdiff(perturbation_test_cols, names(eval_dt))
  if (length(missing_cols)) stop("perturbation_test_cols nicht im Eval-Set: ", paste(missing_cols, collapse = ", "))

  rmse_fn <- function(truth, pred) sqrt(mean((truth - pred)^2))
  res <- run_perturbation_test(predict_response, eval_dt, perturbation_test_cols, truth,
                                rmse_fn, noise_sd_frac = perturbation_noise_sd_frac, higher_is_better = FALSE)
  warn <- res$drop > perturbation_warn_drop
  cat(sprintf("=== Perturbation-Test (%s, %.0f%% SD-Rauschen, Modell=%s) ===\n",
              paste(perturbation_test_cols, collapse = ", "), perturbation_noise_sd_frac * 100, model_choice))
  cat(sprintf("baseline RMSE=%.4f  perturbed RMSE=%.4f (sd=%.4f)  drop=%.4f%s\n\n",
              res$baseline_metric, res$perturbed_metric_mean, res$perturbed_metric_sd, res$drop,
              if (warn) sprintf(" -- WARNUNG: Drop > %.2f", perturbation_warn_drop) else ""))
  results$perturbation <- data.table(
    test = "perturbation", feature = paste(perturbation_test_cols, collapse = "+"),
    value = res$drop, metric = "rmse_drop", warn = warn
  )
}

# --- 2) Invarianz ------------------------------------------------------------
if (length(invariance_test_cols)) {
  missing_cols <- setdiff(invariance_test_cols, names(eval_dt))
  if (length(missing_cols)) stop("invariance_test_cols nicht im Eval-Set: ", paste(missing_cols, collapse = ", "))

  results$invariance <- rbindlist(lapply(invariance_test_cols, function(col) {
    res <- run_invariance_test(predict_response, eval_dt, col)
    # Bei numerischer Response zusaetzlich auf die Aenderungsgroesse gaten -
    # eine hohe flip_rate mit winziger mean_abs_change ist bei einem grossen
    # Boosting-Ensemble Rauschen, kein echter Befund (siehe 000_config.R).
    magnitude_relevant <- is.na(res$mean_abs_change) || res$mean_abs_change > invariance_warn_magnitude_threshold
    warn <- res$flip_rate_mean > invariance_warn_flip_rate && magnitude_relevant
    cat(sprintf("=== Invarianz-Test (Spalte '%s' gemischt, Modell=%s) ===\n", col, model_choice))
    cat(sprintf("flip_rate=%.4f (sd=%.4f)  mean_abs_change=%.4f%s\n\n",
                res$flip_rate_mean, res$flip_rate_sd, res$mean_abs_change,
                if (warn) sprintf(" -- WARNUNG: flip_rate > %.2f UND mean_abs_change > %.2f", invariance_warn_flip_rate, invariance_warn_magnitude_threshold) else ""))
    data.table(test = "invariance", feature = col, value = res$flip_rate_mean, metric = "flip_rate",
               mean_abs_change = res$mean_abs_change, warn = warn)
  }), fill = TRUE)
}

# --- 3) Directional Expectation ----------------------------------------------
if (length(directional_expectation_specs)) {
  results$directional <- rbindlist(lapply(directional_expectation_specs, function(spec) {
    if (!spec$feature %in% names(eval_dt)) stop("directional_expectation_specs: Feature nicht im Eval-Set: ", spec$feature)

    shift_fn <- if (identical(spec$type, "ordinal")) {
      build_ordinal_shift_fn(spec$level_order)
    } else {
      build_numeric_shift_fn(spec$delta)
    }

    eval_subset <- eval_dt[!is.na(eval_dt[[spec$feature]]) & eval_dt[[spec$feature]] != "", ]
    res <- run_directional_test(predict_response, eval_subset, spec$feature, shift_fn, direction = spec$direction)
    effect_share <- mean(res$violation & abs(res$diff) > directional_effect_threshold)

    warn <- res$violation_rate > directional_warn_violation_rate || effect_share > directional_warn_effect_share
    cat(sprintf("=== Directional-Expectation-Test (%s, direction=%s, Modell=%s, n=%d) ===\n",
                spec$feature, spec$direction, model_choice, nrow(eval_subset)))
    cat(sprintf("violation_rate=%.4f  mean_diff=%.4f  share mit |diff|>%.2f=%.4f%s\n\n",
                res$violation_rate, res$mean_diff, directional_effect_threshold, effect_share,
                if (warn) " -- WARNUNG" else ""))
    data.table(test = "directional", feature = spec$feature, value = res$violation_rate,
               metric = "violation_rate", effect_share = effect_share, warn = warn)
  }), fill = TRUE)
}

all_results <- rbindlist(results, fill = TRUE)
fwrite(all_results, sanity_check_results_path)

flagged <- all_results[warn == TRUE]
if (nrow(flagged)) {
  cat(sprintf("=== WARNUNG: %d Sanity-Check(s) ueber der Schwelle ===\n", nrow(flagged)))
  print(flagged)
} else {
  cat("Keine Sanity-Check-Warnung ueber der Schwelle - unauffaellig.\n")
}
cat("\nGespeichert:", sanity_check_results_path, "\n")
