# =====================================================================
# quantile_regression.R -- Pinball-Loss-Quantilregression als Alternative/
# Ergaenzung zu Split-Conformal Prediction (conformal_prediction.R).
# =====================================================================
# BACKLOG.md-Kandidat 28. Split-Conformal nimmt ein bereits trainiertes
# PUNKT-Modell und legt eine KONSTANTE Margin drauf - retrofit-faehig,
# verteilungsfrei GUELTIG (endlich-Stichproben-Coverage-Garantie unter
# Exchangeability), aber die Intervallbreite ist NICHT lokal an
# Heteroskedastizitaet angepasst (nur die Effizienz/Schaerfe leidet
# darunter, nicht die Gueltigkeit). Quantilregression trainiert
# STATTDESSEN zwei eigene Modelle direkt auf die Ziel-Quantile (z.B.
# 5%/95% fuer ein 90%-Intervall) per Pinball-Loss - potenziell SCHAERFERE
# (schmalere) Intervalle bei starker Heteroskedastizitaet, aber KEINE
# verteilungsfreie Coverage-Garantie (haengt von der Modellguete ab, kann
# je nach Datenbereich unter- oder ueberdecken). Die beiden Ansaetze sind
# komplementaer, nicht Ersatz freinander - immer BEIDE auf denselben
# Daten vergleichen (Coverage + mittlere Intervallbreite), nicht blind
# eines bevorzugen.
#
# Nutzt `regr.lightgbm` mit `objective = "quantile"` (natives LightGBM-
# Feature, kein Pipelines-Workaround noetig) - erwartet, dass
# `make_encoded_imputed_learner()` (aus `040_preprocessing.R`) bereits
# gesourct ist.

#' Trainiert zwei LightGBM-Quantilregressions-Modelle (unteres + oberes
#' Quantil) auf DEMSELBEN Task/Trainingssplit.
#'
#' @param task mlr3 `TaskRegr`.
#' @param train_rows Row-Ids fuer das Training.
#' @param lower_tau,upper_tau Ziel-Quantile (z.B. 0.05/0.95 fuer ein
#'   90%-Intervall - symmetrisch um die Mitte, muss aber nicht).
#' @param num_iterations LightGBM-Iterationen (Default 300).
#' @return Liste mit `lower_learner`/`upper_learner` (trainierte Learner)
#'   sowie `lower_tau`/`upper_tau` zur Dokumentation.
train_quantile_learners <- function(task, train_rows, lower_tau = 0.05, upper_tau = 0.95,
                                     num_iterations = 300) {
  stopifnot(lower_tau < upper_tau, lower_tau > 0, lower_tau < 1, upper_tau > 0, upper_tau < 1)
  make_q <- function(tau) {
    lr <- make_encoded_imputed_learner(mlr3::lrn("regr.lightgbm", objective = "quantile",
                                                 alpha = tau, num_iterations = num_iterations))
    lr$train(task, row_ids = train_rows)
    lr
  }
  list(lower_learner = make_q(lower_tau), upper_learner = make_q(upper_tau),
       lower_tau = lower_tau, upper_tau = upper_tau)
}

#' Intervall-Vorhersage aus zwei trainierten Quantil-Learnern.
#'
#' @param learners Rueckgabe von `train_quantile_learners()`.
#' @return `data.table` mit `lower`/`upper`/`crossed` (TRUE an Zeilen, wo
#'   das obere Quantil-Modell unter das untere vorhergesagt hat - ein
#'   bekanntes Artefakt separat trainierter Quantilmodelle, kein Bug;
#'   wird durch Sortieren der beiden Werte repariert, nicht verworfen).
quantile_predict_interval <- function(learners, task, row_ids) {
  lower <- learners$lower_learner$predict(task, row_ids = row_ids)$response
  upper <- learners$upper_learner$predict(task, row_ids = row_ids)$response
  crossed <- lower > upper
  if (any(crossed)) {
    lo <- pmin(lower, upper)
    hi <- pmax(lower, upper)
    lower <- lo
    upper <- hi
  }
  data.table::data.table(lower = lower, upper = upper, crossed = crossed)
}

#' Coverage-Check - absichtlich STRUKTURGLEICH zu
#' `check_conformal_coverage()` (dieselben Feldnamen), damit beide
#' Ergebnisse direkt nebeneinander gelesen/verglichen werden koennen.
#'
#' @param target_coverage Nur zur Dokumentation im Rueckgabewert (die
#'   Quantile selbst bestimmen die tatsaechliche Ziel-Coverage; bei
#'   `lower_tau`/`upper_tau` symmetrisch um 0.5 entspricht sie
#'   `upper_tau - lower_tau`).
check_quantile_coverage <- function(eval_truth, lower, upper, target_coverage) {
  covered <- eval_truth >= lower & eval_truth <= upper
  list(
    empirical_coverage = mean(covered),
    target_coverage = target_coverage,
    mean_width = mean(upper - lower),
    n = length(eval_truth)
  )
}
