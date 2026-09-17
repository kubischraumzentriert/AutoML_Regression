# =====================================================================
# test_regular_lags_helper.R -- Verifikation von regular_lags_helper.R
# (add_regular_lags()). Konstruierter Fall mit BEKANNTEN Lag-/Rolling-
# Werten (2 Entities, kurze regelmaessige Reihe), "nachrechnen" statt
# vertrauen.
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages(library(data.table))
project_dir <- normalizePath(".")
source(file.path(project_dir, "modules", "regular_lags_helper.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}
near <- function(a, b, tol = 1e-9) isTRUE(all(abs(a - b) < tol | (is.na(a) & is.na(b))))

# 2 Entities, 6 regelmaessige Zeitschritte, Werte bewusst einfach (1..6 / 10..60).
dt <- data.table(
  ent = rep(c("A", "B"), each = 6),
  t = rep(1:6, 2),
  x = c(1, 2, 3, 4, 5, 6, 10, 20, 30, 40, 50, 60)
)
# Absichtlich durcheinandergemischt - der Helfer muss selbst sortieren.
dt <- dt[sample(.N)]

res <- add_regular_lags(dt, entity = "ent", time = "t", value = "x",
                        lags = c(1L, 2L),
                        roll_windows = list(w2 = c(1L, 2L), w2from2 = c(2L, 2L)))

setorder(res, ent, t)
a <- res[ent == "A"]

check("lag_1 korrekt (NA, 1,2,3,4,5)", near(a$x_lag_1, c(NA, 1, 2, 3, 4, 5)))
check("lag_2 korrekt (NA,NA,1,2,3,4)", near(a$x_lag_2, c(NA, NA, 1, 2, 3, 4)))

# roll_mean_w2 = Mittel der letzten 2 Werte VOR der aktuellen Zeile:
# t=1: NA, t=2: mean(x_lag1=1) unvollstaendig -> NA (frollmean braucht window voll),
# t=3: mean(1,2)=1.5, t=4: mean(2,3)=2.5, t=5: mean(3,4)=3.5, t=6: mean(4,5)=4.5
check("roll_mean_w2 korrekt", near(a$x_roll_mean_w2, c(NA, NA, 1.5, 2.5, 3.5, 4.5)))

# SD-Formel gegen sd() der jeweils 2 zugrundeliegenden Werte gegenpruefen.
expected_sd <- c(NA, NA, sd(c(1, 2)), sd(c(2, 3)), sd(c(3, 4)), sd(c(4, 5)))
# sd() nutzt n-1, die vektorisierte Populationsformel (E[x^2]-E[x]^2) nutzt n -
# bei genau 2 Werten ist die Populations-SD = sd()/sqrt(2). Direkt nachrechnen
# statt sd() zu vergleichen.
pop_sd <- function(v) sqrt(mean(v^2) - mean(v)^2)
expected_pop_sd <- c(NA, NA, pop_sd(c(1, 2)), pop_sd(c(2, 3)), pop_sd(c(3, 4)), pop_sd(c(4, 5)))
check("roll_sd_w2 korrekt (Populationsformel)", near(a$x_roll_sd_w2, expected_pop_sd))

# roll_mean_w2from2 = Fenster startet 2 Schritte zurueck, Breite 2:
# t=4: mean(x[t=1], x[t=2]) = mean(1,2) = 1.5; t=5: mean(2,3)=2.5; t=6: mean(3,4)=3.5
check("roll_mean_w2from2 korrekt (verschobenes Fenster)",
      near(a$x_roll_mean_w2from2, c(NA, NA, NA, 1.5, 2.5, 3.5)))

# Entity B unabhaengig von A (keine Vermischung ueber Entity-Grenzen).
b <- res[ent == "B"]
check("Entity B unabhaengig von A (lag_1)", near(b$x_lag_1, c(NA, 10, 20, 30, 40, 50)))

# Leere lags/roll_windows -> Funktion laeuft durch, keine neuen Spalten.
res_empty <- add_regular_lags(dt, entity = "ent", time = "t", value = "x")
check("ohne lags/roll_windows keine neuen Spalten",
      identical(sort(names(res_empty)), sort(names(dt))))

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
