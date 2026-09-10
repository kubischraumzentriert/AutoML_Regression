suppressPackageStartupMessages(library(data.table))

# =============================================================================
# composition_reweighting.R -- label-freie CV<->LB-/Holdout-Kompositions-
# diagnose (Backport 2026-09-10; identisch zum Klassifikations-Template
# MLR3_Classifikation, wie group_resampling.R/availability_masking.R).
# =============================================================================
# Herkunft: AStepAheadOfdrought (`ML_Learning`, lokal), Phase 9
# (`140_phase9_cvlb_gap_decomposition.R`, dortiges `PHASE9_REPORT.md`) - dort
# aus der Frage entstanden, WARUM die lokale CV (~0.61) so viel besser war
# als der Leaderboard (~0.74).
#
# LUECKE, die dieses Modul schliesst: eine CV-/Holdout-Metrik (RMSE, MAE,
# Devianz, ...) kann vom echten Leaderboard/Test deutlich abweichen, OHNE
# dass ein Modell-Bug oder Leak vorliegt - naemlich wenn Train/CV und Test
# in der Verteilung EINER Segmentspalte (Kategorie, Verfuegbarkeits-/
# Missingness-Flag, Zeit-seit-Ereignis-Bin, Fensterlaenge, ...)
# unterschiedlich zusammengesetzt sind. Dieses Modul beantwortet "ist die
# Luecke (ganz oder teilweise) ein KOMPOSITIONSEFFEKT" - rein LABEL-FREI,
# denn die Segmentzugehoerigkeit muss nur aus TEST-FEATURES ableitbar sein,
# nie aus Test-Labels.
#
# Natuerlicher Partner im Regressions-Template: `125_segment_metrics.R`
# liefert die je Segment stratifizierte Metrik, die
# `reweight_metric_by_test_composition()` dann mit der Test-Segment-
# verteilung neu gewichtet. Ergaenzt `018_adversarial_validation.R` (dort:
# ist Train/Test ueberhaupt trennbar) um die Frage, ob eine gefundene
# Trennbarkeit die CV-LB-Luecke auch quantitativ erklaert.
#
# ZWEI FUNKTIONEN, bewusst getrennt (billig -> teuer):
#   segment_composition_shift() - billiger Vorab-Check: unterscheidet sich
#     Train/Test in der Verteilung EINER Segmentspalte ueberhaupt spuerbar?
#   reweight_metric_by_test_composition() - der teure Schritt: eine bereits
#     vorliegende, NACH SEGMENT stratifizierte CV-/Holdout-Metrik wird mit
#     der ECHTEN Test-Segmentverteilung neu gewichtet statt mit der
#     Train-/CV-Segmentverteilung.
# composition_diagnosis_report() kombiniert beide zu einem Gesamtbefund.
#
# BESTAETIGT AN 5 PROJEKTEN (2026-09-09, ADR-003 erfuellt, n=2-Minimum klar
# ueberschritten - volle Herleitung in den TEMPLATE_FRICTION.md-Dateien der
# jeweiligen ML_Learning-Projekte):
#   AStepAheadOfdrought (Panel/Zeit, Regression): Komposition (Missingness-
#     Fensterlaenge) erklaerte >90% der CV-LB-Luecke.
#   geoai-aquaculture-pond-identification-challenge (Panel/Zeit,
#     Klassifikation): Komposition erklaerte nur ~0.4% - ein Werte-Shift
#     dominierte die Luecke; die Methode erkannte das KORREKT, statt
#     faelschlich "Komposition" zu behaupten.
#   rossmann-store-sales-forecasting (Panel/Zeit, Regression): +1.21% RMSE,
#     klein, aber ein echter Kompositionsbeitrag.
#   PumpItUp, drivendata_richter (beide generische IID-Tabellenwettbewerbe,
#     zufaelliger Split): KEIN nennenswerter Kompositionsunterschied - der
#     billige Vorab-Check (`segment_composition_shift()`) allein reichte,
#     um das festzustellen, keine teure Stufe-2-Analyse noetig.
# MUSTER: die Methode ist gezielt fuer Panel-/Zeitreihen-/Forecasting-
# Projekte mit STRUKTURELL (nicht zufaellig) getrenntem Train/Test wertvoll
# - bei einem echten IID-Split gibt es nichts zu komponieren.

#' Billiger Vorab-Check: unterscheidet sich die Verteilung einer
#' Segmentspalte zwischen Train und Test spuerbar? Rein aus FEATURES (keine
#' Labels noetig). Vor der teureren `reweight_metric_by_test_composition()`
#' aufrufen - bei einem unauffaelligen Ergebnis (echter IID-Split) lohnt
#' sich Stufe 2 meist nicht (an 2/5 Projekten bestaetigt: PumpItUp,
#' drivendata_richter).
#' @param train_values Vektor (Charakter/Faktor/Integer) der Segmentspalte
#'   im Training
#' @param test_values derselbe Vektor im Test (nur aus Test-FEATURES)
#' @param tvd_threshold Schwelle fuer "auffaellig" (Default 0.05 = 5
#'   Prozentpunkte kumulierte Differenz - grob an den 5 Projekten
#'   kalibriert: Drought/geoai/Rossmann lagen deutlich darueber, PumpItUp/
#'   drivendata_richter klar darunter, siehe Kopfkommentar)
#' @return list(shares = data.table(segment, train_share, test_share, diff),
#'   tvd = Gesamt-Total-Variation-Distance (0-1), auffaellig = tvd > tvd_threshold)
segment_composition_shift <- function(train_values, test_values, tvd_threshold = 0.05) {
  train_values <- as.character(train_values)
  test_values <- as.character(test_values)
  train_share <- prop.table(table(train_values))
  test_share <- prop.table(table(test_values))
  all_levels <- union(names(train_share), names(test_share))
  tr <- setNames(rep(0, length(all_levels)), all_levels)
  te <- setNames(rep(0, length(all_levels)), all_levels)
  tr[names(train_share)] <- as.numeric(train_share)
  te[names(test_share)] <- as.numeric(test_share)
  diff <- abs(tr - te)

  shares <- data.table::data.table(
    segment = all_levels,
    train_share = as.numeric(tr[all_levels]),
    test_share = as.numeric(te[all_levels]),
    diff = as.numeric(diff[all_levels])
  )
  data.table::setorder(shares, -diff)
  tvd <- sum(diff) / 2 # Total-Variation-Distance: 0 = identische Verteilung, 1 = disjunkt

  list(shares = shares, tvd = tvd, auffaellig = tvd > tvd_threshold)
}

#' Test-komponierte Metrik-Schaetzung: eine bereits vorliegende, NACH
#' SEGMENT stratifizierte CV-/Holdout-Metrik wird mit der ECHTEN
#' Test-Segmentverteilung neu gewichtet statt mit der Train-/CV-
#' Segmentverteilung - beantwortet label-frei, ob eine CV-LB-Luecke (ganz
#' oder teilweise) ein Kompositionseffekt ist.
#' @param segment_metric data.frame/data.table mit GENAU EINER Zeile je
#'   Segmentwert: Spalte `segment` (Wert, muss zu `test_shares` passen
#'   koennen) und Spalte `metric` (die je Segment gemessene CV-/Holdout-
#'   Metrik, z.B. RMSE/MAE/Devianz je Fensterlaenge/Kategorie). Mehrere
#'   Messungen je Segment (z.B. CV-Folds) VORHER aggregieren (Mittelwert).
#' @param test_shares benannter numerischer Vektor ODER data.table(segment,
#'   share) - die ECHTE Verteilung des Segments im Test, ausschliesslich aus
#'   Test-FEATURES berechnet (keine Labels)
#' @param cv_shares optional: die Verteilung, mit der `segment_metric`
#'   implizit bereits gewichtet war (z.B. Stichprobengroesse je Segment in
#'   der CV) - nur fuer den Vergleichswert `cv_weighted_estimate`, NICHT
#'   fuer die eigentliche test-komponierte Schaetzung noetig
#' @return list(composition_corrected_estimate = gewichteter Mittelwert mit
#'   test_shares, cv_weighted_estimate = gewichteter Mittelwert mit
#'   cv_shares (NA, falls `cv_shares` nicht angegeben), coverage = Anteil
#'   der test_shares-Masse, der tatsaechlich durch gemessene Segmente
#'   gedeckt ist (< 1, wenn ein im Test vorkommendes Segment nie in
#'   `segment_metric` gemessen wurde - dann ist die Schaetzung eine
#'   Untergrenze/Approximation, siehe Phase-9-Vorbild in `AStepAheadOfdrought`))
reweight_metric_by_test_composition <- function(segment_metric, test_shares, cv_shares = NULL) {
  segment_metric <- data.table::as.data.table(segment_metric)
  stopifnot(
    "segment_metric braucht die Spalten 'segment' und 'metric'" =
      all(c("segment", "metric") %in% names(segment_metric))
  )
  segment_metric[, segment := as.character(segment)]
  stopifnot(
    "segment_metric darf je Segment nur EINE Zeile haben (vorher aggregieren)" =
      !anyDuplicated(segment_metric$segment)
  )

  test_shares <- .as_named_share_vector(test_shares)

  matched <- intersect(names(test_shares), segment_metric$segment)
  stopifnot("Kein gemeinsames Segment zwischen segment_metric und test_shares" = length(matched) > 0)
  coverage <- sum(test_shares[matched]) / sum(test_shares)

  w <- test_shares[matched]
  m <- segment_metric[data.table::data.table(segment = matched), on = "segment"]$metric
  composition_corrected_estimate <- sum(w * m) / sum(w)

  cv_weighted_estimate <- NA_real_
  if (!is.null(cv_shares)) {
    cv_shares <- .as_named_share_vector(cv_shares)
    matched_cv <- intersect(names(cv_shares), segment_metric$segment)
    if (length(matched_cv) > 0) {
      w_cv <- cv_shares[matched_cv]
      m_cv <- segment_metric[data.table::data.table(segment = matched_cv), on = "segment"]$metric
      cv_weighted_estimate <- sum(w_cv * m_cv) / sum(w_cv)
    }
  }

  list(
    composition_corrected_estimate = composition_corrected_estimate,
    cv_weighted_estimate = cv_weighted_estimate,
    coverage = coverage
  )
}

# Interner Helfer: data.table(segment, share) ODER benannter Vektor -> immer
# benannter numerischer Vektor.
.as_named_share_vector <- function(x) {
  if (is.data.frame(x) || data.table::is.data.table(x)) {
    x <- data.table::as.data.table(x)
    stopifnot(all(c("segment", "share") %in% names(x)))
    return(setNames(as.numeric(x$share), as.character(x$segment)))
  }
  stopifnot("share-Argument braucht Namen (Segmentwerte)" = !is.null(names(x)))
  x
}

#' Gesamtbefund: Vorab-Check + (falls auffaellig oder erzwungen) die
#' test-komponierte Schaetzung, mit Einordnung gegen die bisherige CV-Praxis.
#' @param force Stufe 2 auch bei unauffaelligem Vorab-Check rechnen (Default
#'   FALSE - an 5 Projekten war das nie noetig, siehe Kopfkommentar)
#' @param cv_practice_estimate optional: der bisherige CV-/Holdout-Wert
#'   (ungewichtet oder mit der bisherigen Praxis-Gewichtung), fuer die
#'   ausgewiesene Differenz `composition_correction`
composition_diagnosis_report <- function(train_values, test_values, segment_metric,
                                          test_shares = NULL, cv_practice_estimate = NA_real_,
                                          tvd_threshold = 0.05, force = FALSE,
                                          label = "composition-diagnosis") {
  shift <- segment_composition_shift(train_values, test_values, tvd_threshold)

  cat(sprintf("\n=== Kompositions-Diagnose: %s ===\n", label))
  cat(sprintf("Total-Variation-Distance Train vs. Test: %.4f (Schwelle %.4f)\n",
              shift$tvd, tvd_threshold))
  cat(if (shift$auffaellig)
    "=> AUFFAELLIG: Train/Test unterscheiden sich in diesem Segment spuerbar - Stufe 2 lohnt sich.\n"
    else "=> unauffaellig: kein nennenswerter Kompositionsunterschied - vermutlich IID-Split, Stufe 2 meist nicht noetig.\n")

  result <- list(shift = shift, reweighted = NULL)

  if (shift$auffaellig || force) {
    if (is.null(test_shares)) {
      test_shares <- setNames(shift$shares$test_share, shift$shares$segment)
    }
    reweighted <- reweight_metric_by_test_composition(segment_metric, test_shares)
    result$reweighted <- reweighted

    cat(sprintf("Test-komponierte Schaetzung: %.4f (Deckung %.1f%% der Test-Masse)\n",
                reweighted$composition_corrected_estimate, 100 * reweighted$coverage))
    if (!is.na(cv_practice_estimate)) {
      cat(sprintf("Bisherige CV-Praxis: %.4f  Kompositionsbeitrag: %.4f\n",
                  cv_practice_estimate,
                  cv_practice_estimate - reweighted$composition_corrected_estimate))
    }
  }

  data.table::data.table(
    label = label,
    tvd = shift$tvd,
    auffaellig = shift$auffaellig,
    composition_corrected_estimate = if (is.null(result$reweighted)) NA_real_ else result$reweighted$composition_corrected_estimate,
    coverage = if (is.null(result$reweighted)) NA_real_ else result$reweighted$coverage,
    cv_practice_estimate = cv_practice_estimate
  )
}
