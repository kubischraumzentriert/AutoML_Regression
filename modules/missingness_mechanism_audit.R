# =============================================================================
# missingness_mechanism_audit.R -- ist Fehlen in einem Feature informativ,
# statt naiv per Median/Modus zu imputieren?
# =============================================================================
# BACKLOG.md-Kandidat 27 (Herkunft: Bestandsaufnahme 2026-09-14). Luecke im
# bestehenden Trust-Layer: `target_leak_audit_helpers.R` prueft Leaks,
# `univariate_drift.R` prueft Train-vs-Test-Drift, `composition_reweighting.R`
# prueft Kompositionseffekte - aber nichts prueft, OB das Fehlmuster selbst
# eine der drei klassischen Kategorien ist:
#   MCAR (Missing Completely At Random) - Fehlen ist reiner Zufall, naive
#     Imputation (Median/Modus) ist unbedenklich.
#   MAR (Missing At Random) - Fehlen haengt von ANDEREN beobachteten
#     Features ab (z.B. "Sensor X faellt bei Regen haeufiger aus"). Median-
#     Imputation verzerrt dann bedingte Zusammenhaenge.
#   MNAR (Missing Not At Random) - Fehlen haengt vom (unbeobachteten) WERT
#     der Spalte selbst oder vom ZIEL ab (z.B. "hohe Werte werden seltener
#     gemessen"). Das ist der gefaehrlichste Fall - naive Imputation kann
#     hier systematische Verzerrung ins Modell einbauen.
#
# Diese Datei kann MCAR nicht von MNAR-durch-den-eigenen-Wert unterscheiden
# (der wahre Wert ist ja unbekannt) - sie prueft die zwei PRUEFBAREN Signale:
# haengt das Fehlen mit dem ZIEL zusammen (Hinweis auf MNAR bzgl. des Ziels
# oder eine starke MAR/Ziel-Korrelation) und haengt das Fehlen mit ANDEREN
# beobachteten Features zusammen (Hinweis auf MAR)? Zeigt keins von beidem
# ein Signal, ist das KONSISTENT mit MCAR (kein Beweis, siehe "Nicht
# automatisieren"-Disziplin des Templates - immer als Hinweis lesen, nie als
# Beweis).
#
# Baut auf `univariate_drift.R` auf (KS-Test fuer stetige, Chi-Quadrat fuer
# kategoriale Spalten, BH-korrigiert) - der "missing vs. nicht-missing"-
# Vergleich ist strukturell identisch zum "Train vs. Test"-Vergleich dort,
# nur die beiden Gruppen sind anders definiert. Voraussetzung: `univariate_
# drift.R` ist bereits gesourct (definiert `run_univariate_drift_tests()`).
#
# **Effektgroessen-Schwellenwert (`min_effect_size`, ergaenzt 2026-09-14)**:
# reale Anwendung an `beijing-air-quality-panel` (n=360.966) zeigte den
# bekannten Grosse-Stichproben-Effekt aus `univariate_drift.R`s eigenem
# Kopfkommentar in voller Staerke - bei so grossem n wird fast JEDE noch so
# kleine Abweichung "signifikant" (Beispiel: CO dort KS-D=0,02, aber
# p_adj=2,9e-05). `min_effect_size` ist optional (Default `NULL` = nur
# p_adj_BH < alpha, rueckwirkungskompatibles altes Verhalten) - gesetzt,
# zaehlt ein Hinweis nur, wenn ZUSAETZLICH zur Signifikanz die Effektgroesse
# (KS-D bzw. Cramers V, beide 0-1, aus dem `effect_size`-String von
# `univariate_drift.R` geparst) die Schwelle erreicht. Trennt "statistisch
# nachweisbar" von "praktisch relevant".

#' Parst den `effect_size`-String aus `run_univariate_drift_tests()`
#' ("D=0.140"/"CramersV=0.045"/"n/a (...)") zu einer Zahl in [0, 1].
#' @return Numerisch, `NA` bei "n/a"-Faellen (konstant/zu wenig Werte/Fehler).
.parse_missingness_effect_size <- function(effect_str) {
  suppressWarnings(as.numeric(sub("^[A-Za-z]+=", "", effect_str)))
}

#' Missingness-Mechanismus-Diagnose fuer EIN Feature.
#'
#' @param dt data.table/data.frame.
#' @param feature Spaltenname mit (mindestens teilweise) fehlenden Werten.
#' @param target_col Zielspalte (numerisch ODER kategorial - `univariate_
#'   drift.R` erkennt den Typ automatisch).
#' @param other_cols Spalten, gegen die auf MAR-Hinweise geprueft wird.
#'   Default: alle Spalten ausser `feature`/`target_col`.
#' @param alpha Signifikanzschwelle NACH BH-Korrektur (Default 0.05).
#' @param min_effect_size Optionale Mindest-Effektgroesse (KS-D/Cramers V,
#'   0-1) ZUSAETZLICH zur Signifikanz, damit ein Hinweis zaehlt. Default
#'   `NULL` = nur `p_adj_BH < alpha` (altes Verhalten). Empfohlen bei
#'   grossen Datensaetzen (siehe Kopfkommentar).
#' @return Liste mit Diagnosefeldern (siehe `verdict` fuer die Kurzfassung).
diagnose_missingness_mechanism <- function(dt, feature, target_col, other_cols = NULL,
                                            alpha = 0.05, min_effect_size = NULL) {
  stopifnot(
    "feature muss eine Spalte von dt sein" = feature %in% names(dt),
    "target_col muss eine Spalte von dt sein" = target_col %in% names(dt)
  )
  dt <- data.table::as.data.table(dt)
  missing_ind <- is.na(dt[[feature]])
  n <- nrow(dt)
  n_missing <- sum(missing_ind)

  if (n_missing == 0L || n_missing == n) {
    return(list(feature = feature, n_missing = n_missing, missing_share = n_missing / n,
                target_p_adj = NA_real_, target_effect = NA_character_, target_effect_value = NA_real_,
                n_feature_hints = NA_integer_, n_features_tested = 0L,
                top_feature_hint = NA_character_, top_feature_effect_value = NA_real_,
                verdict = "uebersprungen (keine oder alle Werte fehlen)"))
  }

  if (is.null(other_cols)) other_cols <- setdiff(names(dt), c(feature, target_col))
  other_cols <- other_cols[other_cols != feature]

  # --- MNAR-/Ziel-Hinweis: unterscheidet sich das ZIEL zwischen Zeilen mit
  # und ohne fehlenden Wert? ---------------------------------------------
  target_ref <- data.frame(target = dt[[target_col]][!missing_ind])
  target_new <- data.frame(target = dt[[target_col]][missing_ind])
  target_res <- run_univariate_drift_tests(target_ref, target_new)
  target_effect_value <- .parse_missingness_effect_size(target_res$effect_size[1])

  # --- MAR-Hinweis: unterscheiden sich ANDERE Features zwischen den
  # beiden Gruppen? (identischer Mechanismus wie Train-vs-Test-Drift) -----
  feat_res <- if (length(other_cols) > 0L) {
    run_univariate_drift_tests(
      as.data.frame(dt[!missing_ind, other_cols, with = FALSE]),
      as.data.frame(dt[missing_ind, other_cols, with = FALSE]))
  } else {
    data.table::data.table()
  }
  if (nrow(feat_res) > 0L) {
    feat_res[, effect_value := .parse_missingness_effect_size(effect_size)]
  }

  effect_ok <- function(v) is.null(min_effect_size) || (!is.na(v) && v >= min_effect_size)

  target_sig <- isTRUE(target_res$p_adj_BH[1] < alpha) && effect_ok(target_effect_value)
  feat_hits <- if (nrow(feat_res) > 0L) {
    feat_res[p_adj_BH < alpha & vapply(effect_value, effect_ok, logical(1))]
  } else {
    feat_res
  }
  n_feat_sig <- nrow(feat_hits)

  verdict <- if (target_sig && n_feat_sig > 0L) {
    "Ziel- UND Feature-Hinweis (MNAR-bzgl.-Ziel UND MAR-Signal gleichzeitig)"
  } else if (target_sig) {
    "Ziel-Hinweis (moeglich MNAR bzgl. des Ziels - Fehlen haengt mit dem Ziel zusammen)"
  } else if (n_feat_sig > 0L) {
    sprintf("Feature-Hinweis (moeglich MAR - %d von %d anderen Features unterscheiden sich)",
            n_feat_sig, nrow(feat_res))
  } else {
    "kein Hinweis auf Nicht-Zufaelligkeit (konsistent mit MCAR, kein Beweis)"
  }

  list(feature = feature, n_missing = n_missing, missing_share = n_missing / n,
       target_p_adj = target_res$p_adj_BH[1], target_effect = target_res$effect_size[1],
       target_effect_value = target_effect_value,
       n_feature_hints = n_feat_sig, n_features_tested = nrow(feat_res),
       top_feature_hint = if (n_feat_sig > 0L) feat_hits$feature[1] else NA_character_,
       top_feature_effect_value = if (n_feat_sig > 0L) feat_hits$effect_value[1] else NA_real_,
       verdict = verdict)
}

#' Laeuft ueber ALLE Spalten mit fehlenden Werten, Konsolen-Report + CSV.
#'
#' @param feature_cols Zu pruefende Spalten (Default: alle ausser `target_col`).
#' @param min_effect_size Siehe `diagnose_missingness_mechanism()`. Bei
#'   grossen Datensaetzen (grobe Faustregel: > ~50.000 Zeilen) empfohlen,
#'   z.B. `0.1` (KS-D/Cramers V) - ohne Schwelle wird dort fast jede Spalte
#'   "signifikant" markiert (siehe Kopfkommentar).
#' @param out_path Optional: Pfad fuer `fwrite()`. NULL = nicht speichern.
missingness_mechanism_report <- function(dt, target_col, feature_cols = NULL,
                                          alpha = 0.05, min_effect_size = NULL, out_path = NULL) {
  dt <- data.table::as.data.table(dt)
  if (is.null(feature_cols)) feature_cols <- setdiff(names(dt), target_col)
  miss_cols <- feature_cols[vapply(feature_cols, function(f) anyNA(dt[[f]]), logical(1))]

  cat(sprintf("\n=== Missing-Data-Mechanismus-Audit (alpha=%.2f%s) ===\n", alpha,
              if (is.null(min_effect_size)) "" else sprintf(", min_effect_size=%.2f", min_effect_size)))
  if (length(miss_cols) == 0L) {
    cat("Keine fehlenden Werte in den geprueften Spalten - Audit uebersprungen.\n")
    return(invisible(data.table::data.table()))
  }

  res <- data.table::rbindlist(lapply(miss_cols, function(f)
    data.table::as.data.table(diagnose_missingness_mechanism(dt, f, target_col, other_cols = feature_cols,
                                                              alpha = alpha, min_effect_size = min_effect_size))
  ))
  data.table::setorder(res, -n_feature_hints, target_p_adj, na.last = TRUE)

  cat(sprintf("%d Spalte(n) mit fehlenden Werten geprueft.\n", nrow(res)))
  print(res[, .(feature, n_missing, missing_share = round(missing_share, 4),
               target_effect_value = round(target_effect_value, 3), verdict)])

  if (!is.null(out_path)) {
    data.table::fwrite(res, out_path)
    cat("Gespeichert:", out_path, "\n")
  }
  invisible(res)
}
