# =====================================================================
# entity_history.R -- generische "letzter bekannter Wert/Zeit seit einem
# bekannten Ereignis vor der aktuellen Zeile je Entity"-Helfer.
# =====================================================================
# BACKLOG.md-Kandidat Nr. 5 (Herkunft: GeoAI-Drought "legal-history"), an 2
# unabhaengigen Panel-/Forecasting-Projekten bestaetigt (GeoAI-Drought,
# Rossmann Store Sales - siehe REFERENZ_AVAILABILITY_MASKING.md). NUR fuer
# Panel-/Forecasting-Daten sinnvoll (Entity + Zeit), nicht fuer i.i.d.-
# Regression. Optional, projektspezifisch - kein numeriertes Treiber-Skript,
# ein neues Projekt sourct diese Datei bei Bedarf selbst (analog zu
# `group_resampling.R`).
#
# WICHTIGES PRINZIP (in beiden Bestaetigungsprojekten verifiziert): ein
# Ereignis, das ERST NACH der aktuellen Zeile eintritt, darf KEINE Information
# in die aktuelle Zeile liefern - sonst waere das ein Blick in die eigene
# Zukunft der Entity (Leck). Alle Funktionen unten geben `NA` zurueck, wenn
# das Ereignis (noch) unbekannt/in der Zukunft liegt, NIE einen negativen
# "Countdown" o.ae.

#' Monate seit einem bekannten Monats-/Jahres-Ereignis, aus Sicht der
#' aktuellen Zeile.
#'
#' @param current_date `Date`-Vektor (eine Zeile je Beobachtung).
#' @param onset_year,onset_month Jahr/Monat des Ereignisses je Entity
#'   (gleiche Laenge wie `current_date`, i.d.R. durch einen vorherigen Merge
#'   mit Entity-Stammdaten entstanden - z.B. "seit wann gibt es einen
#'   Wettbewerber" je Filiale).
#' @return Numerischer Vektor (Monate, `0` = Ereignis-Monat selbst), `NA`
#'   wenn das Ereignis unbekannt ist ODER noch in der Zukunft von
#'   `current_date` liegt.
months_since_known <- function(current_date, onset_year, onset_month) {
  onset_date <- as.Date(sprintf("%d-%02d-01", onset_year, onset_month))
  months_elapsed <- (as.integer(format(current_date, "%Y")) - as.integer(format(onset_date, "%Y"))) * 12L +
    (as.integer(format(current_date, "%m")) - as.integer(format(onset_date, "%m")))
  ifelse(is.na(onset_date) | current_date < onset_date, NA_real_, as.numeric(months_elapsed))
}

#' Wochen seit einem bekannten ISO-Kalenderwochen-/Jahres-Ereignis.
#'
#' @param current_date `Date`-Vektor.
#' @param onset_year,onset_week Jahr/ISO-Kalenderwoche des Ereignisses je
#'   Entity.
#' @return Numerischer Vektor (volle Wochen), `NA` wie bei
#'   `months_since_known()`.
weeks_since_known <- function(current_date, onset_year, onset_week) {
  onset_date <- as.Date(paste(onset_year, onset_week, 1), format = "%Y %U %u")
  weeks_elapsed <- as.numeric(difftime(current_date, onset_date, units = "weeks"))
  ifelse(is.na(onset_date) | current_date < onset_date, NA_real_, floor(weeks_elapsed))
}

#' Letzter bekannter Wert einer Statusspalte VOR der aktuellen Zeile, je
#' Entity - die urspruengliche GeoAI-Drought-Formulierung ("legal-history"),
#' fuer den allgemeinen Fall EINER Beobachtungsreihe je Entity (nicht nur
#' "seit wann"-Ereignisse wie oben, sondern ein sich ueber die Zeit
#' aendernder Wert, z.B. ein Status-Code).
#'
#' @param entity_id Vektor der Entity-IDs.
#' @param date `Date`-Vektor.
#' @param value Der zu verfolgende Wert (numerisch oder Faktor/Zeichen).
#' @return Vektor derselben Laenge: fuer jede Zeile der zuletzt bekannte
#'   `value` BEVOR das aktuelle Datum, je Entity - `NA` fuer die erste
#'   Beobachtung jeder Entity bzw. wenn noch kein vorheriger Wert existiert.
#'   Erwartet, dass die Eingabe NICHT bereits nach `date` sortiert sein muss -
#'   die Funktion sortiert intern und stellt die Original-Reihenfolge wieder
#'   her.
current_or_last_known <- function(entity_id, date, value) {
  # Ueber Positions-INDIZES statt Werten arbeiten - vermeidet Typ-/Level-
  # Verlust bei `c()` auf Faktoren (ein direktes `c(NA, factor[...])` wuerde
  # den Faktor stillschweigend zu Integer-Codes degradieren). Indizierung
  # (`value[idx]`) erhaelt Typ/Level dagegen automatisch korrekt, auch bei
  # `NA`-Indizes.
  ord <- order(entity_id, date)
  entity_sorted <- entity_id[ord]
  n <- length(value)
  prev_pos_in_sorted <- c(NA_integer_, seq_len(n - 1L))
  prev_pos_in_sorted[!duplicated(entity_sorted)] <- NA_integer_  # erste Zeile je Entity: kein Vorwissen
  prev_orig_idx <- ord[prev_pos_in_sorted]
  value[prev_orig_idx]
}
