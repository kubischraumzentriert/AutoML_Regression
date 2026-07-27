# =====================================================================
# deviance_measures.R -- Poisson- und Tweedie-Devianz als mlr3-Measures
# =====================================================================
# Neue Reibung fuer das Regressions-Template: mlr3 liefert ab Werk KEINE
# Devianz-Metrik (nur regr.rmse/mae/mse/rsq/...). Fuer Count-/Tweedie-Ziele
# ist die (mittlere) Devianz die richtige, weil sie die Verlustfunktion des
# Modells spiegelt (Poisson/Tweedie-Objective) und Nullmasse + Rechtsschiefe
# korrekt gewichtet, statt sie wie L2/RMSE quadratisch zu ueberstrafen.
#
# Definitionen (mittlere UNIT-Devianz, identisch zu sklearn
# mean_poisson_deviance / mean_tweedie_deviance):
#
#   Poisson:  d(y, mu) = 2 * ( y*log(y/mu) - (y - mu) ),   0*log0 := 0
#   Tweedie:  d_p(y, mu) = 2 * ( y^(2-p)/((1-p)(2-p))
#                                - y*mu^(1-p)/(1-p)
#                                + mu^(2-p)/(2-p) )       fuer p != 1, 2
#             p = 1 -> Poisson (Grenzfall),
#             p = 2 -> Gamma:  d(y,mu) = 2 * ( log(mu/y) + y/mu - 1 )
#             p = 0 -> Normal: d(y,mu) = (y - mu)^2
#   Gueltige Bereiche: y >= 0, mu > 0 (0 <= p < 1 verlangt zusaetzlich y > 0
#   fuer den ersten Term; hier nicht genutzt, da wir 1 <= p <= 2 verwenden).
#
# Verifiziert gegen glm()-Residualdevianz (Poisson/Gamma) in
# test_deviance.R.
# =====================================================================

suppressPackageStartupMessages({
  library(mlr3)
  library(R6)
})

# --- reine numerische Kernfunktionen (ohne mlr3, gut testbar) --------

#' Mittlere Poisson-Unit-Devianz.
#' @param truth numerischer Vektor, y >= 0 (Counts).
#' @param response numerischer Vektor, mu > 0 (vorhergesagte Erwartungswerte).
poisson_deviance <- function(truth, response, eps = 1e-10) {
  stopifnot(length(truth) == length(response))
  if (any(truth < 0)) stop("poisson_deviance: truth muss >= 0 sein.")
  mu <- pmax(response, eps)
  # y*log(y/mu) mit der Konvention 0*log0 = 0
  ylogy <- ifelse(truth > 0, truth * log(truth / mu), 0)
  dev <- 2 * (ylogy - (truth - mu))
  mean(dev)
}

#' Mittlere Tweedie-Unit-Devianz mit Potenzparameter `power` (p).
#' @param power Tweedie-Potenz p. p=1 -> Poisson, 1<p<2 -> Compound
#'   Poisson-Gamma, p=2 -> Gamma, p=0 -> Normal/L2.
tweedie_deviance <- function(truth, response, power = 1.5, eps = 1e-10) {
  stopifnot(length(truth) == length(response))
  p <- power
  if (any(truth < 0)) stop("tweedie_deviance: truth muss >= 0 sein.")
  mu <- pmax(response, eps)

  if (p == 1) {
    return(poisson_deviance(truth, response, eps = eps))
  }
  if (p == 2) {
    # Gamma: verlangt y > 0
    y <- pmax(truth, eps)
    dev <- 2 * (log(mu / y) + y / mu - 1)
    return(mean(dev))
  }
  if (p == 0) {
    return(mean((truth - mu)^2))
  }
  if (p > 0 && p < 1) {
    stop("tweedie_deviance: 0 < power < 1 ist keine gueltige Tweedie-Verteilung.")
  }
  # Allgemeiner Fall (u.a. 1 < p < 2). truth^(2-p) ist 0 bei truth == 0,
  # weil 2-p > 0 -> Nullmasse traegt hier korrekt bei.
  term1 <- truth^(2 - p) / ((1 - p) * (2 - p))
  term2 <- truth * mu^(1 - p) / (1 - p)
  term3 <- mu^(2 - p) / (2 - p)
  dev <- 2 * (term1 - term2 + term3)
  mean(dev)
}

# --- mlr3-Measure-Wrapper -------------------------------------------

MeasureRegrPoissonDeviance <- R6::R6Class(
  "MeasureRegrPoissonDeviance",
  inherit = mlr3::MeasureRegr,
  public = list(
    initialize = function() {
      super$initialize(
        id = "regr.poisson_deviance",
        range = c(0, Inf),
        minimize = TRUE,
        predict_type = "response",
        label = "Mean Poisson Deviance",
        man = NA_character_
      )
    }
  ),
  private = list(
    .score = function(prediction, ...) {
      poisson_deviance(prediction$truth, prediction$response)
    }
  )
)

MeasureRegrTweedieDeviance <- R6::R6Class(
  "MeasureRegrTweedieDeviance",
  inherit = mlr3::MeasureRegr,
  public = list(
    power = NULL,
    initialize = function(power = 1.5) {
      self$power <- power
      super$initialize(
        id = "regr.tweedie_deviance",
        range = c(0, Inf),
        minimize = TRUE,
        predict_type = "response",
        label = "Mean Tweedie Deviance",
        man = NA_character_
      )
    }
  ),
  private = list(
    .score = function(prediction, ...) {
      tweedie_deviance(prediction$truth, prediction$response, power = self$power)
    }
  )
)

#' Registriert beide Measures im mlr3-Dictionary, damit sie ueber
#' msr("regr.poisson_deviance") / msr("regr.tweedie_deviance", power=...)
#' verfuegbar sind. Idempotent.
#' @param tweedie_power Default-Potenz fuer das Tweedie-Measure.
register_deviance_measures <- function(tweedie_power = 1.5) {
  keys <- mlr3::mlr_measures$keys()
  if (!"regr.poisson_deviance" %in% keys) {
    mlr3::mlr_measures$add("regr.poisson_deviance", MeasureRegrPoissonDeviance)
  }
  if (!"regr.tweedie_deviance" %in% keys) {
    mlr3::mlr_measures$add(
      "regr.tweedie_deviance",
      function() MeasureRegrTweedieDeviance$new(power = tweedie_power)
    )
  }
  invisible(TRUE)
}
