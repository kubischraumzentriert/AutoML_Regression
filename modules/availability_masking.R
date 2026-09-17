# =====================================================================
# availability_masking.R -- Validierungs-Maskierung aus Test-Verfuegbarkeit
# spiegeln.
# =====================================================================
# BACKLOG.md-Kandidat Nr. 4 (Herkunft: GeoAI-Drought), an 2 unabhaengigen
# Panel-/Forecasting-Projekten bestaetigt. Siehe REFERENZ_AVAILABILITY_
# MASKING.md Abschnitt 1-2 fuer die Herleitung/Theorie. Baut auf dem bereits
# vorhandenen `012_feature_availability_audit.R` auf (dessen `missing_rate_
# delta`-Spalte), fuegt aber die fehlende AKTIONS-Ebene hinzu: die Luecke
# NICHT nur berichten, sondern in die lokale Validierung spiegeln.
#
# WICHTIGE LEHRE (Rossmann-Bestaetigung): die Pruefung muss auf den
# tatsaechlich im Modell verwendeten (ggf. ABGELEITETEN) Spalten laufen, nicht
# nur auf den Rohspalten aus `012` - ein Delta in einer Rohspalte schlaegt
# sich auf jedes daraus abgeleitete Feature durch. Der Aufrufer muss daher
# explizit angeben, welche abgeleiteten Features von welcher Rohspalte
# abhaengen (`derived_from`), damit deren Delta korrekt uebertragen wird -
# das kann diese Funktion nicht automatisch erkennen.

#' Bestimmt je Spalte, um wie viel haeufiger sie im Test fehlt als im
#' Training (gekappt bei 0 - nur der fuer CV-Optimismus relevante Fall).
#'
#' @param train_raw,test_raw `data.frame`/`data.table` der ROHEN (nicht
#'   feature-engineerten) Trainings-/Testdaten.
#' @param cols Zeichenvektor der zu pruefenden Rohspalten.
#' @return Benannter numerischer Vektor (Delta je Spalte, `1` wenn die
#'   Spalte im Test komplett fehlt).
apply_availability_profile <- function(train_raw, test_raw, cols) {
  vapply(cols, function(c) {
    if (!c %in% names(test_raw)) return(1)
    tr_rate <- mean(is.na(train_raw[[c]]))
    te_rate <- mean(is.na(test_raw[[c]]))
    max(0, te_rate - tr_rate)
  }, numeric(1))
}

#' Uebertraegt Rohspalten-Deltas auf abgeleitete Features und injiziert die
#' resultierende zusaetzliche Fehlwert-Rate zufaellig in eine Validierungs-
#' menge (nur bei aktuell NICHT bereits fehlenden Zeilen, um Fehlwerte nicht
#' doppelt zu zaehlen).
#'
#' @param valid_dt `data.table` der Validierungszeilen (wird kopiert, nicht
#'   in-place veraendert).
#' @param raw_deltas Ergebnis von `apply_availability_profile()`.
#' @param derived_from Benannte Liste: Name = abgeleitetes Feature in
#'   `valid_dt`, Wert = Vektor der Rohspalten, von denen es abhaengt (das
#'   MAXIMUM ihrer Deltas wird verwendet - fehlt irgendeine Rohspalte, ist
#'   die Ableitung typischerweise ebenfalls unbekannt).
#' @param seed Zufalls-Seed fuer die Maskierungs-Stichprobe.
#' @return `valid_dt`-Kopie mit zusaetzlichen `NA`s in den betroffenen
#'   Spalten.
mask_validation_by_availability_profile <- function(valid_dt, raw_deltas, derived_from = list(), seed = 42) {
  d <- data.table::copy(valid_dt)
  target_deltas <- raw_deltas[intersect(names(raw_deltas), names(d))]
  for (derived_col in names(derived_from)) {
    source_cols <- derived_from[[derived_col]]
    delta <- max(raw_deltas[intersect(source_cols, names(raw_deltas))], 0)
    target_deltas[derived_col] <- delta
  }
  for (col in names(target_deltas)) {
    rate <- target_deltas[[col]]
    if (rate <= 0 || !col %in% names(d)) next
    non_na_idx <- which(!is.na(d[[col]]))
    if (length(non_na_idx) == 0) next
    set.seed(seed)
    mask_idx <- sample(non_na_idx, round(rate * nrow(d)))
    d[mask_idx, (col) := NA]
  }
  d
}
