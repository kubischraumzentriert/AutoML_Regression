# =====================================================================
# test_missingness_mechanism_audit.R -- Verifikation von
# missingness_mechanism_audit.R (diagnose_missingness_mechanism()/
# missingness_mechanism_report()). Identisch zu den testthat-Faellen im
# Klassifikations-Template (test-missingness_mechanism_audit.R), nur im
# hiesigen manuellen Teststil (siehe test_composition_reweighting.R).
# =====================================================================
rm(list = ls())
project_dir <- normalizePath(".")
source(file.path(project_dir, "univariate_drift.R"))
source(file.path(project_dir, "missingness_mechanism_audit.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}

# --- MCAR: Fehlen unabhaengig von Ziel UND anderen Features -----------
set.seed(1)
n <- 1000
dt <- data.table::data.table(x_other = rnorm(n), y = rnorm(n), z = rnorm(n))
dt[sample(.N, 200), z := NA]
r1 <- diagnose_missingness_mechanism(dt, feature = "z", target_col = "y")
check("MCAR: target_p_adj > 0.05", r1$target_p_adj > 0.05)
check("MCAR: 0 Feature-Hinweise", r1$n_feature_hints == 0L)
check("MCAR: Verdict nennt 'kein Hinweis'", grepl("kein Hinweis", r1$verdict))

# --- MNAR bzgl. Ziel (numerisch): Fehlen haengt vom ZIEL ab ------------
set.seed(2)
y <- rnorm(n)
dt2 <- data.table::data.table(x_other = rnorm(n), y = y, z = rnorm(n))
miss_idx <- order(y, decreasing = TRUE)[1:250]
dt2[miss_idx, z := NA]
r2 <- diagnose_missingness_mechanism(dt2, feature = "z", target_col = "y")
check("MNAR-Ziel: target_p_adj < 0.01", r2$target_p_adj < 0.01)
check("MNAR-Ziel: Verdict nennt 'Ziel-Hinweis'", grepl("Ziel-Hinweis", r2$verdict))

# --- MAR: Fehlen haengt von ANDEREM Feature ab, nicht vom Ziel ---------
set.seed(3)
x_other <- rnorm(n)
y3 <- rnorm(n)
dt3 <- data.table::data.table(x_other = x_other, y = y3, z = rnorm(n))
miss_idx3 <- order(x_other, decreasing = TRUE)[1:250]
dt3[miss_idx3, z := NA]
r3 <- diagnose_missingness_mechanism(dt3, feature = "z", target_col = "y")
check("MAR: target_p_adj > 0.05 (Ziel unbeteiligt)", r3$target_p_adj > 0.05)
check("MAR: >0 Feature-Hinweise", r3$n_feature_hints > 0L)
check("MAR: top_feature_hint == 'x_other'", r3$top_feature_hint == "x_other")
check("MAR: Verdict nennt 'Feature-Hinweis'", grepl("Feature-Hinweis", r3$verdict))

# --- n_missing == 0 wird sauber uebersprungen --------------------------
dt4 <- data.table::data.table(x = rnorm(100), y = rnorm(100), z = rnorm(100))
r4 <- diagnose_missingness_mechanism(dt4, feature = "z", target_col = "y")
check("kein Fehlen: n_missing == 0", r4$n_missing == 0L)
check("kein Fehlen: Verdict nennt 'uebersprungen'", grepl("uebersprungen", r4$verdict))

# --- missingness_mechanism_report(): eine Zeile je Spalte, sortiert ----
set.seed(5)
n5 <- 500
y5 <- rnorm(n5)
dt5 <- data.table::data.table(a = rnorm(n5), b = rnorm(n5), y = y5)
dt5[sample(.N, 50), a := NA]
miss_idx5 <- order(y5, decreasing = TRUE)[1:100]
dt5[miss_idx5, b := NA]
res5 <- missingness_mechanism_report(dt5, target_col = "y")
check("Report: 2 Zeilen (a, b)", nrow(res5) == 2L && all(c("a", "b") %in% res5$feature))
check("Report: b hat Ziel-Hinweis", grepl("Ziel-Hinweis", res5[feature == "b"]$verdict))

# --- Report ohne fehlende Werte -> leere Tabelle -----------------------
dt6 <- data.table::data.table(a = rnorm(50), y = rnorm(50))
res6 <- missingness_mechanism_report(dt6, target_col = "y")
check("Report ohne Missingness: 0 Zeilen", nrow(res6) == 0L)

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
