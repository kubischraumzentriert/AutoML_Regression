# Drei Modell-Sanity-Checks nach Huyen (2022) "Designing Machine Learning
# Systems", Kap. 6 "Evaluation Methods" - ergaenzen die bestehende
# Fehleranalyse um Fragen, die eine reine Holdout-Metrik nicht beantwortet:
# ist das Modell robust gegen kleine, realistische Stoerungen (Perturbation),
# reagiert es NICHT auf Spalten ohne kausale Bedeutung (Invarianz), und
# bewegt es sich bei einem Feature mit bekannter monotoner Domainbeziehung in
# die erwartete Richtung (Directional Expectation)? Verifiziert an
# synthetischer Ground Truth + 2 realen Projekten (health_condition,
# drivendata-pump-it-up), siehe TARGETS.md (Klassifikation). Theoretischer
# Hintergrund/Mechanik je Test: REFERENZ_MODEL_SANITY_CHECKS.md.
#
# Aufgabentyp-unabhaengig (identisch in beide Templates uebernommen, wie
# univariate_drift.R): alle drei Funktionen sind modell-agnostisch
# (predict_fn/predict_prob_fn als Parameter) - nur die Konfiguration (welche
# Spalten, welche Richtung, higher_is_better) ist projektspezifisch, siehe
# 000_config.R.

# higher_is_better: TRUE fuer Metriken wie BAcc/AUC (hoeher=besser), FALSE
# fuer Fehlermetriken wie RMSE/MAE (niedriger=besser) - bestimmt nur das
# Vorzeichen von `drop` (immer positiv = "wurde schlechter", unabhaengig von
# der Metrik-Richtung).
run_perturbation_test <- function(predict_fn, data, perturb_cols, truth, metric_fn,
                                   noise_sd_frac = 0.05, n_reps = 5, seed = 1,
                                   higher_is_better = TRUE) {
  set.seed(seed)
  baseline_pred <- predict_fn(data)
  baseline_metric <- metric_fn(truth, baseline_pred)

  reps <- vapply(seq_len(n_reps), function(i) {
    perturbed <- data
    for (col in perturb_cols) {
      col_sd <- stats::sd(data[[col]], na.rm = TRUE)
      noise <- stats::rnorm(nrow(data), mean = 0, sd = noise_sd_frac * col_sd)
      perturbed[[col]] <- perturbed[[col]] + noise
    }
    metric_fn(truth, predict_fn(perturbed))
  }, numeric(1))

  drop <- if (higher_is_better) baseline_metric - mean(reps) else mean(reps) - baseline_metric
  list(
    baseline_metric = baseline_metric,
    perturbed_metric_mean = mean(reps),
    perturbed_metric_sd = stats::sd(reps),
    drop = drop
  )
}

# Fuer kategoriale Responses (Klassifikation): flip_rate = Anteil geaenderter
# Klassen-Labels. Fuer numerische Responses (Regression): flip_rate = Anteil
# der Zeilen, deren Vorhersage sich um mehr als `tolerance` aendert (Default
# 0 - bei einem Tree-Ensemble, das die Spalte in KEINEM Split verwendet, ist
# die Vorhersage exakt bitidentisch, kein Rauschen zu erwarten). Zusaetzlich
# mean_abs_change als Magnitude-Diagnostik (nur bei numerischer Response
# sinnvoll, bei kategorialer NA).
run_invariance_test <- function(predict_fn, data, invariant_col, n_reps = 5, seed = 1,
                                 tolerance = 0) {
  set.seed(seed)
  baseline_pred <- predict_fn(data)
  is_numeric_response <- is.numeric(baseline_pred)

  reps <- lapply(seq_len(n_reps), function(i) {
    perturbed <- data
    perturbed[[invariant_col]] <- sample(data[[invariant_col]])
    perturbed_pred <- predict_fn(perturbed)
    if (is_numeric_response) {
      diff <- abs(perturbed_pred - baseline_pred)
      list(flip_rate = mean(diff > tolerance), mean_abs_change = mean(diff))
    } else {
      list(flip_rate = mean(as.character(perturbed_pred) != as.character(baseline_pred)), mean_abs_change = NA_real_)
    }
  })
  flip_rates <- vapply(reps, function(r) r$flip_rate, numeric(1))
  mean_abs_changes <- vapply(reps, function(r) r$mean_abs_change, numeric(1))

  list(
    flip_rate_mean = mean(flip_rates), flip_rate_sd = stats::sd(flip_rates),
    mean_abs_change = if (is_numeric_response) mean(mean_abs_changes) else NA_real_
  )
}

# Verschiebt ein numerisches Feature um `delta`, erhaelt den urspruenglichen
# Typ (wichtig fuer int-typisierte Spalten wie Zaehler/Codes - mlr3s
# predict_newdata()-Typcheck verweigert sonst numeric->integer mit
# Nachkommastellen, siehe TARGETS.md/PumpItUp-Erfahrung).
build_numeric_shift_fn <- function(delta) {
  function(x) {
    shifted <- x + delta
    if (is.integer(x)) shifted <- as.integer(round(shifted))
    shifted
  }
}

# shift_fn: function(x) -> x, verschoben "in die erwartete positive Richtung"
#           (numerisch: + delta; ordinal: siehe build_ordinal_shift_fn())
# direction: "increasing" = P soll bei der Verschiebung nicht SINKEN,
#            "decreasing" = P soll bei der Verschiebung nicht STEIGEN
run_directional_test <- function(predict_prob_fn, data, feature_col, shift_fn,
                                  direction = c("increasing", "decreasing"),
                                  tolerance = 1e-6) {
  direction <- match.arg(direction)
  base_prob <- predict_prob_fn(data)

  shifted <- data
  shifted[[feature_col]] <- shift_fn(data[[feature_col]])
  shifted_prob <- predict_prob_fn(shifted)

  diff <- shifted_prob - base_prob
  violation <- if (direction == "increasing") diff < -tolerance else diff > tolerance

  list(violation_rate = mean(violation), mean_diff = mean(diff), diff = diff, violation = violation)
}

# Baut eine Stufen-Shift-Funktion fuer ein ordinales Kategorie-Feature aus
# einer aufsteigend sortierten Level-Reihenfolge (z.B. c("low","medium","high")).
# Das oberste Level bleibt bei sich selbst (kein weiterer Schritt moeglich,
# diff=0 zaehlt dann nicht als Verletzung). Leerstring (NA-Sentinel, siehe
# TARGETS.md sentinel_to_na()-Kandidat) bleibt unveraendert.
build_ordinal_shift_fn <- function(level_order) {
  mapping <- setNames(c(level_order[-1], level_order[length(level_order)]), level_order)
  function(x) {
    x <- as.character(x)
    out <- ifelse(x == "" | is.na(x), x, mapping[x])
    out[is.na(out)] <- x[is.na(out)]
    out
  }
}
