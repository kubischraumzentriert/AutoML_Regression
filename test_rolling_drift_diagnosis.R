# =====================================================================
# test_rolling_drift_diagnosis.R -- Verifikation von
# rolling_drift_diagnosis.R (assign_time_windows()/rolling_univariate_
# drift()/drift_trend_test()). Konstruierte Faelle mit BEKANNTEM
# Verlauf (kein Drift / echter monotoner Trend / Fenster-Ausreisser
# ohne Trend) - "nachrechnen" statt vertrauen.
# =====================================================================
rm(list = ls())
project_dir <- normalizePath(".")
source(file.path(project_dir, "univariate_drift.R"))
source(file.path(project_dir, "rolling_drift_diagnosis.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}

# --- assign_time_windows(): korrekte, chronologische Fenstereinteilung -
set.seed(1)
n <- 1000
time <- sample(seq_len(n))  # absichtlich durcheinandergemischt
w <- assign_time_windows(time, k = 5L)
check("5 Fenster erzeugt", length(unique(w)) == 5L)
check("Fenster 1 enthaelt die chronologisch fruehesten Zeilen",
      all(time[w == 1] <= 200))
check("Fenster 5 enthaelt die chronologisch spaetesten Zeilen",
      all(time[w == 5] > 800))
check("etwa gleich grosse Fenster (+/- 1)", max(table(w)) - min(table(w)) <= 1)

# --- rolling_univariate_drift() + drift_trend_test(): KEIN Drift -------
set.seed(2)
n2 <- 5000
dt_nodrift <- data.table::data.table(time = seq_len(n2), x = rnorm(n2), y = rnorm(n2))
w2 <- assign_time_windows(dt_nodrift$time, k = 6L)
res_nodrift <- rolling_univariate_drift(dt_nodrift, w2, feature_cols = c("x", "y"))
trend_nodrift <- drift_trend_test(res_nodrift)
check("kein Drift: 5 Fenster-Zeilen (6 Fenster - 1 Referenz)", nrow(res_nodrift) == 5L)
check("kein Drift: kein Trend erkannt", !trend_nodrift$trend_detected)

# --- Echter monotoner Trend: x-Mittelwert waechst linear mit der Zeit --
set.seed(3)
n3 <- 6000
time3 <- seq_len(n3)
dt_trend <- data.table::data.table(time = time3, x = time3 / n3 * 5 + rnorm(n3, sd = 0.3))
w3 <- assign_time_windows(dt_trend$time, k = 6L)
res_trend <- rolling_univariate_drift(dt_trend, w3, feature_cols = "x")
trend_trend <- drift_trend_test(res_trend)
check("echter Trend: Drift-Staerke waechst mit dem Fenster-Index",
      all(diff(res_trend$mean_effect_size) >= -0.05))  # im Wesentlichen monoton steigend
check("echter Trend: Trend erkannt", trend_trend$trend_detected)
check("echter Trend: rho stark positiv", trend_trend$rho > 0.8)

# --- Fenster-Ausreisser OHNE systematischen Trend -----------------------
# Nur Fenster 4 (von 6) weicht ab, der Rest ist identisch verteilt -
# eine einmalige Verschiebung ist KEIN monotoner Trend.
set.seed(4)
n4 <- 6000
time4 <- seq_len(n4)
w4 <- assign_time_windows(time4, k = 6L)
x4 <- rnorm(n4)
x4[w4 == 4] <- x4[w4 == 4] + 3  # nur dieses eine Fenster ist verschoben
dt_outlier <- data.table::data.table(time = time4, x = x4)
res_outlier <- rolling_univariate_drift(dt_outlier, w4, feature_cols = "x")
trend_outlier <- drift_trend_test(res_outlier)
check("Fenster-Ausreisser: Fenster 4 hat die groesste Effektgroesse",
      res_outlier[which.max(mean_effect_size)]$window_id == 4L)
check("Fenster-Ausreisser: KEIN monotoner Trend erkannt (einmaliger Ausreisser != Trend)",
      !trend_outlier$trend_detected)

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
