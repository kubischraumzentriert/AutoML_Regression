# Split-Conformal Prediction (Vovk et al. 2005; siehe auch das MLOps/UQ-
# Semiconductor-Paper aus der Literaturbewertung, C:\Git\literatur\
# bewertung.md): erzeugt Prediction-Intervals mit einer verteilungsfreien,
# endlich-Stichproben-GUELTIGEN Coverage-Garantie fuer ein BEREITS
# trainiertes Punktvorhersage-Modell - kein erneutes Training des
# Basismodells noetig, retrofit-faehig auf jede vorhandene Vorhersage.
#
# Mechanik: eine unabhaengige Kalibrierungsmenge (Modell hat sie nie
# gesehen) liefert Nonconformity-Scores |y_true - y_pred|. Der (n+1)(1-alpha)/n-
# Quantil-Score wird als symmetrische Margin auf neue Punktvorhersagen
# addiert/subtrahiert. Die Coverage-Garantie ist MARGINAL (ueber die gesamte
# Verteilung gemittelt) und gilt unter Exchangeability zwischen Kalibrierungs-
# und Testdaten - bei Distribution Shift (siehe REFERENZ_DISTRIBUTION_SHIFT.md
# im Klassifikations-Template) ist die Garantie NICHT mehr verlaesslich.
# Intervallbreite ist konstant (nicht lokal an Heteroskedastizitaet
# angepasst) - das betrifft nur die EFFIZIENZ (Intervallbreite), nicht die
# GUELTIGKEIT (Coverage) der Methode.

# calib_truth/calib_pred: Vektoren gleicher Laenge, Punktvorhersagen auf
# einer Kalibrierungsmenge, die das Modell nie zum Training gesehen hat.
# alpha: 1 - Ziel-Coverage (z.B. 0.1 fuer 90% Coverage).
# Gibt die symmetrische Margin zurueck (Prediction Interval = pred +/- margin).
split_conformal_calibrate <- function(calib_truth, calib_pred, alpha) {
  n <- length(calib_truth)
  if (n < 30) {
    warning("Kalibrierungsmenge sehr klein (n=", n, ") - Quantilschaetzung instabil.")
  }
  scores <- abs(calib_truth - calib_pred)
  q_level <- min(1, ceiling((n + 1) * (1 - alpha)) / n)
  as.numeric(stats::quantile(scores, probs = q_level, type = 1, names = FALSE))
}

# pred: Punktvorhersagen auf neuen Daten. margin: aus split_conformal_calibrate().
split_conformal_predict_interval <- function(pred, margin) {
  data.table::data.table(pred = pred, lower = pred - margin, upper = pred + margin)
}

# Prueft die empirische Coverage auf einer EVAL-Menge, die weder fuers
# Modelltraining noch fuer die Kalibrierung verwendet wurde. Vergleicht mit
# der Ziel-Coverage (1-alpha) - sollte nah dran liegen (Vovk-Garantie ist
# marginal, keine Punktgarantie, daher realistische Toleranz einplanen,
# insb. bei kleinem eval_n).
check_conformal_coverage <- function(eval_truth, eval_pred, margin, alpha) {
  interval <- split_conformal_predict_interval(eval_pred, margin)
  covered <- eval_truth >= interval$lower & eval_truth <= interval$upper
  list(
    empirical_coverage = mean(covered),
    target_coverage = 1 - alpha,
    mean_width = mean(interval$upper - interval$lower),
    n = length(eval_truth)
  )
}
