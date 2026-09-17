# =====================================================================
# test_composition_reweighting.R -- Verifikation von
# composition_reweighting.R (segment_composition_shift() /
# reweight_metric_by_test_composition() / composition_diagnosis_report()).
# Synthetisch auf konstruierten Faellen mit BEKANNTER Komposition/Metrik.
# "nachrechnen" statt vertrauen. Identisch zu den testthat-Faellen im
# Klassifikations-Template (MLR3_Classifikation/tests/testthat/
# test-composition_reweighting.R), nur im hiesigen manuellen Teststil.
# =====================================================================
rm(list = ls())
project_dir <- normalizePath(".")
source(file.path(project_dir, "modules", "composition_reweighting.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}
near <- function(a, b, tol = 1e-9) isTRUE(abs(a - b) < tol)

# --- segment_composition_shift() ------------------------------------------
set.seed(1)
tr <- sample(c("A", "B", "C"), 1000, replace = TRUE, prob = c(0.5, 0.3, 0.2))
te <- sample(c("A", "B", "C"), 1000, replace = TRUE, prob = c(0.5, 0.3, 0.2))
r <- segment_composition_shift(tr, te, tvd_threshold = 0.05)
check("identische Verteilung -> TVD < 0.05, unauffaellig", r$tvd < 0.05 && !r$auffaellig)
check("shares summieren je Seite zu 1",
      near(sum(r$shares$train_share), 1) && near(sum(r$shares$test_share), 1))

tr2 <- rep(c("kurz", "lang"), c(900, 100)) # 90/10
te2 <- rep(c("kurz", "lang"), c(100, 900)) # 10/90
r2 <- segment_composition_shift(tr2, te2, tvd_threshold = 0.05)
check("stark verschoben -> auffaellig, TVD == 0.8", r2$auffaellig && near(r2$tvd, 0.8))

r3 <- segment_composition_shift(rep("A", 100), c(rep("A", 80), rep("B", 20)))
b_row <- r3$shares[segment == "B"]
check("im Train fehlendes Testsegment -> train_share 0, test_share 0.2",
      near(b_row$train_share, 0) && near(b_row$test_share, 0.2))

# --- reweight_metric_by_test_composition() -------------------------------
sm <- data.table::data.table(segment = c("2", "3", "4"), metric = c(0.5, 0.7, 0.9))
ts <- c("2" = 0.2, "3" = 0.3, "4" = 0.5)
rw <- reweight_metric_by_test_composition(sm, ts)
check("einfacher gewichteter Mittelwert reproduziert",
      near(rw$composition_corrected_estimate, 0.2 * 0.5 + 0.3 * 0.7 + 0.5 * 0.9) &&
        near(rw$coverage, 1))

sm_flat <- data.table::data.table(segment = c("A", "B"), metric = c(0.8, 0.8))
rw_flat <- reweight_metric_by_test_composition(sm_flat, c(A = 0.9, B = 0.1), c(A = 0.1, B = 0.9))
check("segment-unabhaengige Metrik -> Neugewichtung aendert nichts",
      near(rw_flat$composition_corrected_estimate, 0.8) && near(rw_flat$cv_weighted_estimate, 0.8))

sm_seg <- data.table::data.table(segment = c("kurz", "lang"), metric = c(0.60, 0.95))
rw_seg <- reweight_metric_by_test_composition(sm_seg, c(kurz = 0.9, lang = 0.1), c(kurz = 0.1, lang = 0.9))
check("segmentabhaengige Metrik -> Test-Komposition schlechter als CV-Komposition",
      near(rw_seg$cv_weighted_estimate, 0.1 * 0.60 + 0.9 * 0.95) &&
        near(rw_seg$composition_corrected_estimate, 0.9 * 0.60 + 0.1 * 0.95) &&
        rw_seg$composition_corrected_estimate < rw_seg$cv_weighted_estimate)

rw_cov <- reweight_metric_by_test_composition(
  data.table::data.table(segment = "A", metric = 0.9), c(A = 0.7, B = 0.3))
check("unvollstaendige Deckung wird gemeldet (coverage 0.7)",
      near(rw_cov$coverage, 0.7) && near(rw_cov$composition_corrected_estimate, 0.9))

rw_dt <- reweight_metric_by_test_composition(
  data.table::data.table(segment = c("A", "B"), metric = c(0.4, 0.6)),
  data.table::data.table(segment = c("A", "B"), share = c(0.25, 0.75)))
check("test_shares als data.table akzeptiert",
      near(rw_dt$composition_corrected_estimate, 0.25 * 0.4 + 0.75 * 0.6))

dup_errored <- tryCatch({
  reweight_metric_by_test_composition(
    data.table::data.table(segment = c("A", "A"), metric = c(0.4, 0.5)), c(A = 1))
  FALSE
}, error = function(e) grepl("EINE Zeile", conditionMessage(e)))
check("doppelte Segmente in segment_metric -> kontrollierter Abbruch", dup_errored)

# --- composition_diagnosis_report() ------------------------------------
sink(tempfile())
set.seed(2)
tr_iid <- sample(c("A", "B"), 500, replace = TRUE)
te_iid <- sample(c("A", "B"), 500, replace = TRUE)
res_iid <- composition_diagnosis_report(
  tr_iid, te_iid, data.table::data.table(segment = c("A", "B"), metric = c(0.8, 0.9)),
  label = "iid")
res_shift <- composition_diagnosis_report(
  rep(c("kurz", "lang"), c(100, 900)), rep(c("kurz", "lang"), c(900, 100)),
  data.table::data.table(segment = c("kurz", "lang"), metric = c(0.6, 0.95)), label = "shift")
res_force <- composition_diagnosis_report(
  tr_iid, te_iid, data.table::data.table(segment = c("A", "B"), metric = c(0.8, 0.9)),
  label = "force", force = TRUE)
sink()
check("Report: unauffaelliger Vorab-Check -> Stufe 2 NICHT gerechnet",
      !res_iid$auffaellig && is.na(res_iid$composition_corrected_estimate))
check("Report: auffaelliger Vorab-Check -> Stufe 2 automatisch, dominiert vom kurz-Segment",
      res_shift$auffaellig && !is.na(res_shift$composition_corrected_estimate) &&
        res_shift$composition_corrected_estimate < 0.95)
check("Report: force=TRUE -> Stufe 2 auch bei unauffaelligem Vorab-Check",
      !res_force$auffaellig && !is.na(res_force$composition_corrected_estimate))

cat("\n", if (ok) "=== ALLE TESTS BESTANDEN ===" else "=== TESTS FEHLGESCHLAGEN ===", "\n")
if (!ok) quit(status = 1)
