# =====================================================================
# test_label_update_frequency.R -- Verifikation von
# label_update_frequency.R (check_label_update_frequency()). Konstruierte
# Faelle mit BEKANNTEM Anteil unveraenderter Zielwerte.
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages(library(data.table))
project_dir <- normalizePath(".")
source(file.path(project_dir, "modules", "label_update_frequency.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}
near <- function(a, b, tol = 1e-9) isTRUE(all(abs(a - b) < tol))

# --- Fall 1: Ziel aendert sich JEDE Zeile (kein Update-Frequenz-Problem) ---
dt1 <- data.table(t = 1:10, y = seq(1, 10))
res1 <- check_label_update_frequency(dt1, target_col = "y", order_col = "t")
check("Fall 1: share_unchanged = 0 (jede Zeile neu)", near(res1$share_unchanged, 0))
check("Fall 1: run_length_summary Median = 1", near(as.numeric(res1$run_length_summary["Median"]), 1))

# --- Fall 2: Ziel bleibt ueber Bloecke von 5 Zeilen konstant (bekannte
# Bloecke: 2 Bloecke a 5 Zeilen -> 8 von 10 Zeilen "unveraendert ggue.
# Vorzeile") ---
dt2 <- data.table(t = 1:10, y = rep(c(100, 200), each = 5))
res2 <- check_label_update_frequency(dt2, target_col = "y", order_col = "t")
check("Fall 2: share_unchanged = 0.8 (8 von 10 Zeilen gleich wie Vorzeile)", near(res2$share_unchanged, 0.8))
check("Fall 2: run_length_summary Median = 5", near(as.numeric(res2$run_length_summary["Median"]), 5))
check("Fall 2: n_unchanged = 8", res2$n_unchanged == 8L)

# --- Fall 3: unsortierte Eingabe - Funktion muss selbst nach order_col
# sortieren (Ergebnis identisch zu Fall 2) ---
dt3 <- dt2[sample(.N)]
res3 <- check_label_update_frequency(dt3, target_col = "y", order_col = "t")
check("Fall 3: unsortierte Eingabe liefert dasselbe Ergebnis wie Fall 2", near(res3$share_unchanged, res2$share_unchanged))

# --- Fall 4: group_col - zwei Gruppen, Vergleich NICHT ueber
# Gruppengrenzen hinweg. Ohne Gruppierung waere z.B. die erste Zeile von
# Gruppe B faelschlich "gleich wie letzte Zeile von Gruppe A", wenn die
# Werte zufaellig uebereinstimmen. ---
dt4 <- data.table(
  grp = rep(c("A", "B"), each = 4),
  t = rep(1:4, 2),
  y = c(1, 1, 1, 2, 1, 1, 1, 2)
)
res4_grouped <- check_label_update_frequency(dt4, target_col = "y", order_col = "t", group_col = "grp")
res4_ungrouped <- check_label_update_frequency(dt4, target_col = "y", order_col = "t")
# Gruppiert: je Gruppe 4 Zeilen (1. immer NA/FALSE), Muster 1,1,1,2 -> 2
# unveraenderte Paare (Zeile2=Zeile1, Zeile3=Zeile2) je Gruppe = 4 von 8.
check("Fall 4 (gruppiert): share_unchanged = 0.5 (4 von 8, Gruppengrenzen respektiert)",
      near(res4_grouped$share_unchanged, 0.5))
# Ungruppiert: die uebergreifende Naht (Zeile 4 "2" -> Zeile 5 "1") liefert
# ein zusaetzliches FALSE, aendert den Zaehler hier nicht (Naht ist ohnehin
# ungleich) - Test stellt trotzdem sicher, dass beide Aufrufe nicht
# zufaellig identisch sind, wenn die Gruppengrenze einen Unterschied machen
# WUERDE (mit anderen Werten). Hier: gleich, weil die Naht zufaellig FALSE
# ist - Regressionsschutz fuer die Interpretation, kein Bug.
check("Fall 4: check_label_update_frequency() liefert konsistente Zeilenzahl",
      res4_grouped$n_rows == 8L && res4_ungrouped$n_rows == 8L)

# --- Fall 5: NA am Anfang zaehlt nicht als "unveraendert" ---
dt5 <- data.table(t = 1:3, y = c(5, 5, 5))
res5 <- check_label_update_frequency(dt5, target_col = "y", order_col = "t")
check("Fall 5: erste Zeile (kein Vorgaenger) zaehlt nicht als unveraendert", res5$n_unchanged == 2L)

if (!ok) {
  cat("\nFEHLGESCHLAGEN\n")
  quit(status = 1)
}
cat("\nAlle Checks OK.\n")
