# =============================================================================
# label_update_frequency.R -- prueft, ob die Zielspalte SELTENER
# aktualisiert wird als die Zeilenfrequenz der Rohdaten nahelegt.
# =============================================================================
# Anlass (BACKLOG.md, Kandidat "Mining Process Label-Update-Frequenz",
# `ML_Learning/kaggle-mining-process-quality/README.md` Abschnitt 2):
# ein Kaggle-Datensatz im 20-Sekunden-Takt (737 453 Zeilen), dessen
# Labor-gemessene Zielspalte aber nur STUENDLICH aktualisiert wird -
# 93,9% aller Zeilen hatten denselben Zielwert wie die unmittelbar
# vorherige Zeile. Ein Random-Split auf Rohgranularitaet haette nahezu
# identische Zeilen aus DERSELBEN Update-Periode in Train UND Test
# verteilt (ein bekannter, in oeffentlichen Kaggle-Kernels haeufig
# unbemerkter Leak-Fallstrick bei Sensor-/Prozessdaten mit periodisch
# aktualisierten Labor-/Batch-Messwerten).
#
# Diese Funktion macht den Befund (die 93,9%-Kennzahl) zu einem
# wiederholbaren, fruehen Check statt eines manuellen Ad-hoc-Vergleichs -
# EINMAL am Anfang eines neuen Zeitreihen-/Panel-Projekts aufrufen, bevor
# eine Split-Strategie gewaehlt wird.
#
# STATUS: 1-Projekt-Kandidat (Mining Process) - noch kein ADR-003-Backport
# (2. unabhaengiges Projekt fehlt), siehe BACKLOG.md. Rein additive
# Diagnosefunktion ohne Seiteneffekt auf bestehende Workflows, daher
# bereits verfuegbar (opt-in), aber noch nicht in eine Standard-Skript-
# Reihenfolge (z.B. 012/013) verdrahtet.

suppressPackageStartupMessages(library(data.table))

#' Anteil der Zeilen, deren Zielwert identisch zur (zeitlich) vorherigen
#' Zeile ist - hoher Anteil deutet darauf hin, dass die Zielspalte in
#' einer GROBEREN Frequenz aktualisiert wird als die Zeilenfrequenz der
#' Rohdaten (z.B. stuendliches Laborergebnis bei 20-Sekunden-Sensordaten).
#'
#' @param dt data.table/data.frame mit mindestens `target_col` und
#'   `order_col`.
#' @param target_col Spaltenname der Zielspalte.
#' @param order_col Spaltenname, nach dem chronologisch sortiert werden
#'   soll (z.B. ein Zeitstempel). Erforderlich - ohne definierte
#'   Reihenfolge ist "vorherige Zeile" bedeutungslos.
#' @param group_col Optional: Spaltenname einer Entity-/Gruppenspalte
#'   (z.B. Station/Charge) - der Vergleich zur Vorzeile erfolgt dann NUR
#'   innerhalb derselben Gruppe (`shift()` je Gruppe), nicht ueber
#'   Gruppengrenzen hinweg.
#' @return `list(share_unchanged, n_rows, n_unchanged, run_length_summary)`
#'   - `run_length_summary` ist `summary()` der Laengen aufeinander-
#'   folgender Zeilen mit identischem Zielwert (zeigt die TYPISCHE
#'   Update-Periode, z.B. ~180 Zeilen bei 20s-Takt/stuendlichem Update).
check_label_update_frequency <- function(dt, target_col, order_col, group_col = NULL) {
  stopifnot(
    "target_col muss eine Spalte von dt sein" = target_col %in% names(dt),
    "order_col muss eine Spalte von dt sein" = order_col %in% names(dt)
  )
  dt <- data.table::as.data.table(dt)
  if (!is.null(group_col)) {
    stopifnot("group_col muss eine Spalte von dt sein" = group_col %in% names(dt))
    data.table::setorderv(dt, c(group_col, order_col))
    prev_val <- dt[, shift(.SD[[1]]), by = group_col, .SDcols = target_col][[2]]
  } else {
    data.table::setorderv(dt, order_col)
    prev_val <- shift(dt[[target_col]])
  }

  unchanged <- dt[[target_col]] == prev_val
  unchanged[is.na(unchanged)] <- FALSE
  n_rows <- nrow(dt)
  n_unchanged <- sum(unchanged)

  # Lauflaengen aufeinanderfolgender identischer Werte (rle()) - die
  # typische Lauflaenge zeigt die Update-Periode direkt (z.B. Median 180
  # bei stuendlichem Update im 20s-Takt).
  run_lengths <- rle(dt[[target_col]])$lengths

  list(
    share_unchanged = n_unchanged / n_rows,
    n_rows = n_rows,
    n_unchanged = n_unchanged,
    run_length_summary = summary(run_lengths)
  )
}

#' Konsolen-Report um `check_label_update_frequency()` - warnt, wenn der
#' Anteil unveraenderter Zielwerte eine Schwelle ueberschreitet (Default
#' 0.5 - bewusst hoch, ein "normales" stetiges Ziel hat praktisch nie
#' >50% exakt identische Nachbarwerte, es sei denn die Update-Frequenz
#' ist tatsaechlich groeber als die Zeilenfrequenz).
report_label_update_frequency <- function(dt, target_col, order_col, group_col = NULL, warn_threshold = 0.5) {
  res <- check_label_update_frequency(dt, target_col, order_col, group_col)
  cat(sprintf(
    "\n=== Label-Update-Frequenz-Check (%s) ===\n", target_col
  ))
  cat(sprintf(
    "Anteil Zeilen mit identischem Zielwert wie die Vorzeile: %.1f%% (%d von %d)\n",
    res$share_unchanged * 100, res$n_unchanged, res$n_rows
  ))
  cat("Lauflaengen-Zusammenfassung (Zeilen je unveraendertem Zielwert-Block):\n")
  print(res$run_length_summary)
  if (res$share_unchanged > warn_threshold) {
    cat(sprintf(
      "\nWARNUNG: %.1f%% > %.0f%%-Schwelle - die Zielspalte wird vermutlich\n",
      res$share_unchanged * 100, warn_threshold * 100
    ))
    cat("SELTENER aktualisiert als die Zeilenfrequenz. Ein Random-Split wuerde\n")
    cat("Zeilen aus derselben Update-Periode in Train UND Test verteilen -\n")
    cat("vor jeder Split-Entscheidung pruefen, ob eine Aggregation auf die\n")
    cat("natuerliche Update-Granularitaet (z.B. Stunde) noetig ist.\n")
  }
  invisible(res)
}
