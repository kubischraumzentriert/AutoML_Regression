# =====================================================================
# regular_lags_helper.R -- generischer Helfer fuer regelmaessige,
# hochfrequente Lag-/Rolling-Features je Entity.
# =====================================================================
# BACKLOG.md-Kandidat Nr. 25 (Herkunft: beijing-air-quality-panel). Deckt
# eine Luecke, die `entity_history.R` (Kandidat 5) bewusst NICHT abdeckt:
# `entity_history.R` ist fuer "Zeit seit einem bekannten Ereignis" gebaut
# (unregelmaessig, ein Ereignis pro Entity), nicht fuer regelmaessige
# Zeitreihen-Lags (viele Beobachtungen je Entity, konstanter Zeittakt -
# stuendlich, taeglich, ...). Dieser Helfer schliesst genau diese Luecke.
#
# Setzt eine REGELMAESSIGE Zeitachse je Entity voraus (z.B. stuendlich
# ohne Luecken) - Lags/Rolling-Fenster sind ZEILEN-basiert (per `shift()`
# innerhalb der Entity-Gruppe), NICHT zeit-basiert. Bei unregelmaessigen
# Zeitachsen (fehlende Zeilen) muesste `dt` vorher auf ein vollstaendiges
# Zeitraster reindiziert werden (nicht Teil dieses Helfers).
#
# ADR-003-Historie: 1. Anwendung `beijing-air-quality-panel` (Kandidat-
# Funktion, projektspezifisch in 025_forecast_features.R), 2. Anwendung
# `electricity-load-panel` (direkt ueber diesen generischen Helfer), 3.
# rueckwirkende Umstellung von beijing-air-quality-panel auf denselben
# Helfer (Generalitaet nachgewiesen statt nur behauptet).

suppressPackageStartupMessages(library(data.table))

#' Regelmaessige Lag-/Rolling-Features je Entity, leckagefrei (nur
#' rueckblickend).
#'
#' @param dt `data.table` mit Entity-, Zeit- und Zielspalte (i.d.R. der
#'   KOMBINIERTE Train+Test-Datensatz - siehe `combined_task_helper.R` -
#'   damit die ersten Test-Zeilen korrekt Train-Vergangenheit nutzen).
#' @param entity Spaltenname der Entity (z.B. `"station"`, `"client"`).
#' @param time Spaltenname der Zeitachse (sortierbar, z.B. `POSIXct`/
#'   `Date`/Integer-Zeittakt). `dt` wird intern nach `entity, time`
#'   sortiert - die Eingabereihenfolge bleibt unveraendert (Kopie).
#' @param value Spaltenname der Zielgroesse, aus der Lags/Rollings
#'   gebaut werden (kann, muss aber nicht die Modell-Zielspalte sein).
#' @param lags Integer-Vektor von Lag-Schritten (in Zeilen = Zeittakt-
#'   Einheiten, z.B. `c(1L, 24L)` fuer 1h/24h bei stuendlichen Daten).
#'   Erzeugt `<value>_lag_<n>`. Leer (Default) = keine Lag-Spalten.
#' @param roll_windows Benannte Liste, jedes Element ein Integer-Paar
#'   `c(from, width)`: Rolling-Mittel/-SD ueber die `width` Werte, die
#'   `from` bis `from + width - 1` Schritte VOR der aktuellen Zeile
#'   liegen (leckagefrei per Konstruktion, `from >= 1`). Erzeugt
#'   `<value>_roll_mean_<name>`/`<value>_roll_sd_<name>`. Beispiel:
#'   `list(\"24h\" = c(1L, 24L))` = Mittel/SD der letzten 24 Werte;
#'   `list(\"24to168h\" = c(24L, 144L))` = Mittel/SD der Werte 24 bis 168
#'   Schritte zurueck (24h-vorlauf-sicher, siehe Horizont-Framing in
#'   `WORKFLOW_GUARDS.md` Abschnitt 6).
#' @return Kopie von `dt`, sortiert nach `entity, time`, mit den neuen
#'   Spalten. SD nutzt die vektorisierte Formel
#'   `sqrt(pmax(0, E[x^2] - E[x]^2))` (zwei `frollmean()`-Aufrufe) statt
#'   des langsamen `frollapply(..., sd)`.
add_regular_lags <- function(dt, entity, time, value, lags = integer(0),
                              roll_windows = list()) {
  stopifnot("entity/time/value muessen alle Spalten von dt sein" = all(c(entity, time, value) %in% names(dt)))
  out <- copy(as.data.table(dt))
  setorderv(out, c(entity, time))

  for (lag_n in lags) {
    col <- paste0(value, "_lag_", lag_n)
    out[, (col) := shift(.SD[[1]], lag_n), by = c(entity), .SDcols = value]
  }

  for (nm in names(roll_windows)) {
    from <- roll_windows[[nm]][1]
    width <- roll_windows[[nm]][2]
    stopifnot(
      "roll_windows[[nm]][1] (from) muss >= 1 sein" = from >= 1L,
      "roll_windows[[nm]][2] (width) muss >= 1 sein" = width >= 1L
    )
    mean_col <- paste0(value, "_roll_mean_", nm)
    sd_col <- paste0(value, "_roll_sd_", nm)

    out[, (c(mean_col, sd_col)) := {
      x <- .SD[[1]]
      shifted <- shift(x, from)
      shifted_sq <- shift(x^2, from)
      m1 <- frollmean(shifted, width)
      m2 <- frollmean(shifted_sq, width)
      list(m1, sqrt(pmax(0, m2 - m1^2)))
    }, by = c(entity), .SDcols = value]
  }

  out
}
