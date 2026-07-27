# =====================================================================
# test_deviance.R -- Verifikation der Devianz-Kernfunktionen
# =====================================================================
# Prueft deviance_measures.R gegen unabhaengige Referenzen:
#   (a) Poisson-Devianz == Residualdevianz eines Poisson-GLM (glm())
#   (b) Tweedie(p=2) == Gamma-Devianz eines Gamma-GLM
#   (c) Tweedie(p=1) == Poisson-Devianz (Grenzfall)
#   (d) Tweedie(p=0) == mittlere quadrat. Abweichung (Normal/L2)
#   (e) Randfall Nullmasse: y=0 traegt endlich bei (kein NaN/Inf)
#   (f) mlr3-Measure liefert denselben Wert wie die Kernfunktion
# "nachrechnen" statt vertrauen.
rm(list = ls())
project_dir <- normalizePath(".")
source(file.path(project_dir, "deviance_measures.R"))

ok <- TRUE
check <- function(name, a, b, tol = 1e-6) {
  passed <- isTRUE(all.equal(a, b, tolerance = tol))
  cat(sprintf("  [%s] %-45s  eigen=%.8f ref=%.8f\n",
              if (passed) "OK" else "FAIL", name, a, b))
  if (!passed) ok <<- FALSE
}

set.seed(1)
n <- 500
x <- rnorm(n)
# Poisson-Daten mit Struktur
mu_true <- exp(0.3 + 0.5 * x)
y_pois <- rpois(n, mu_true)

# (a) Poisson-Devianz vs. glm-Residualdevianz.
# glm(y~x, poisson) minimiert die Devianz; deviance(fit) = SUMME der Unit-
# Devianzen. Unsere Funktion ist der MITTELWERT -> mal n.
fit_p <- glm(y_pois ~ x, family = poisson())
mu_hat <- fitted(fit_p)
check("Poisson == glm-Residualdevianz/n",
      poisson_deviance(y_pois, mu_hat),
      deviance(fit_p) / n)

# (b) Tweedie p=2 vs. Gamma-GLM-Residualdevianz. Gamma verlangt y>0.
y_gam <- rgamma(n, shape = 2, rate = 2 / mu_true)
fit_g <- glm(y_gam ~ x, family = Gamma(link = "log"))
mu_g <- fitted(fit_g)
check("Tweedie(p=2) == Gamma-glm-Residualdevianz/n",
      tweedie_deviance(y_gam, mu_g, power = 2),
      deviance(fit_g) / n)

# (c) Tweedie(p=1) == Poisson-Devianz.
check("Tweedie(p=1) == poisson_deviance",
      tweedie_deviance(y_pois, mu_hat, power = 1),
      poisson_deviance(y_pois, mu_hat))

# (d) Tweedie(p=0) == mittlere quadratische Abweichung.
check("Tweedie(p=0) == mean((y-mu)^2)",
      tweedie_deviance(y_pois, mu_hat, power = 0),
      mean((y_pois - mu_hat)^2))

# (e) Nullmasse: viele y=0, mu>0 -> endlich, nicht-negativ.
y0 <- c(0, 0, 0, 1, 2, 5)
mu0 <- c(0.1, 0.5, 1.0, 0.8, 2.0, 4.0)
pd <- poisson_deviance(y0, mu0)
td <- tweedie_deviance(y0, mu0, power = 1.5)
cat(sprintf("  [%s] %-45s  pois=%.6f tweedie=%.6f\n",
            if (is.finite(pd) && is.finite(td) && pd >= 0 && td >= 0) "OK" else "FAIL",
            "Nullmasse endlich & >= 0", pd, td))
if (!(is.finite(pd) && is.finite(td) && pd >= 0 && td >= 0)) ok <- FALSE

# (f) mlr3-Measure == Kernfunktion.
suppressPackageStartupMessages(library(mlr3))
register_deviance_measures(tweedie_power = 1.5)
truth <- y_pois; response <- mu_hat
p <- PredictionRegr$new(
  row_ids = seq_len(n), truth = as.numeric(truth), response = as.numeric(response)
)
check("mlr3 regr.poisson_deviance == Kernfkt",
      as.numeric(p$score(msr("regr.poisson_deviance"))),
      poisson_deviance(truth, response))
check("mlr3 regr.tweedie_deviance == Kernfkt",
      as.numeric(p$score(msr("regr.tweedie_deviance"))),
      tweedie_deviance(truth, response, power = 1.5))

cat("\n", if (ok) "=== ALLE TESTS BESTANDEN ===" else "=== TESTS FEHLGESCHLAGEN ===", "\n")
if (!ok) quit(status = 1)
