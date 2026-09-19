# =====================================================================
# rolling_drift_diagnosis.R -- Concept-Drift ueber MEHRERE Zeitperioden,
# nicht nur einen einzelnen Train-vs-Test-Vergleich.
# =====================================================================
# BACKLOG.md-Vorschlag (Bestandsaufnahme 2026-09-14, Kandidat 3).
# `univariate_drift.R`/`composition_reweighting.R` wurden bisher immer
# auf GENAU ZWEI Perioden angewendet (Train vs. Test). Das beantwortet
# "unterscheiden sich diese beiden Perioden?", aber NICHT "driftet die
# Verteilung SYSTEMATISCH ueber die Zeit (Trend), oder schwankt sie nur
# zufaellig zwischen zwei willkuerlich gewaehlten Perioden?" - ein
# echter Trend hat andere Konsequenzen als eine einmalige Verschiebung
# (z.B. fuer die Frage, ob ein Modell in der Produktion regelmaessig
# neu trainiert werden muss).
#
# Baut auf `univariate_drift.R` auf (`run_univariate_drift_tests()`) -
# jedes Zeitfenster wird gegen ein REFERENZ-Fenster (per Default das
# ERSTE, chronologisch frueheste) verglichen, genau wie Train-vs-Test,
# nur K-mal statt einmal. Ein einfacher Trend-Test (Spearman-Korrelation
# zwischen Fenster-Index und Drift-Staerke) unterscheidet dann
# systematischen Trend von Fenster-zu-Fenster-Rauschen.

#' Teilt Zeilen in K aufeinanderfolgende, ungefaehr gleich grosse
#' Zeitfenster (nach einer Zeitspalte).
#'
#' @param time Sortierbarer Vektor (Datum/POSIXct/Zahl), eine Zeile je
#'   Beobachtung.
#' @param k Anzahl Fenster.
#' @return Integer-Vektor `window_id` (1 = chronologisch fruehestes
#'   Fenster, `k` = spaetestes), gleiche Laenge/Reihenfolge wie `time`.
assign_time_windows <- function(time, k) {
  stopifnot(
    "k (Anzahl Fenster) muss mindestens 2 sein" = k >= 2,
    "k darf nicht groesser als die Anzahl Zeilen sein" = k <= length(time)
  )
  ord <- order(time)
  window_id <- integer(length(time))
  window_id[ord] <- ceiling(seq_along(ord) / (length(ord) / k))
  pmin(window_id, k)
}

#' Parst den `effect_size`-String aus `run_univariate_drift_tests()`
#' ("D=0.140"/"CramersV=0.045"/"n/a (...)") zu einer Zahl. Identische
#' Logik wie in `missingness_mechanism_audit.R` (bewusst dupliziert -
#' ein einzeiliger Regex-Parser, kein gemeinsames Modul noetig).
.parse_drift_effect_size <- function(effect_str) {
  suppressWarnings(as.numeric(sub("^[A-Za-z]+=", "", effect_str)))
}

#' Vergleicht JEDES Fenster (2..k) gegen das Referenz-Fenster (Default
#' Fenster 1) mit `run_univariate_drift_tests()`, fasst je Fenster
#' zusammen.
#'
#' @param dt data.table/data.frame mit den zu pruefenden Feature-Spalten.
#' @param window_id Rueckgabe von `assign_time_windows()`.
#' @param feature_cols Zu pruefende Spalten.
#' @param reference_window Welches Fenster als Referenz dient (Default 1
#'   = chronologisch fruehestes - "hat sich seither etwas veraendert?").
#' @param alpha Signifikanzschwelle NACH BH-Korrektur (Default 0.05).
#' @return `data.table`: `window_id`, `n`, `share_significant` (Anteil
#'   Features mit `p_adj_BH < alpha`), `mean_effect_size` (Mittel ueber
#'   alle Features, NA-Faelle ausgeschlossen).
rolling_univariate_drift <- function(dt, window_id, feature_cols, reference_window = 1L, alpha = 0.05) {
  dt <- data.table::as.data.table(dt)
  stopifnot("reference_window muss ein tatsaechlich vorkommender window_id-Wert sein" = reference_window %in% window_id)
  ref <- dt[window_id == reference_window, feature_cols, with = FALSE]
  other_windows <- sort(unique(window_id[window_id != reference_window]))

  rows <- lapply(other_windows, function(w) {
    new <- dt[window_id == w, feature_cols, with = FALSE]
    res <- run_univariate_drift_tests(ref, new)
    effect_vals <- vapply(res$effect_size, .parse_drift_effect_size, numeric(1))
    data.table::data.table(
      window_id = w, n = nrow(new),
      share_significant = mean(res$p_adj_BH < alpha, na.rm = TRUE),
      mean_effect_size = mean(effect_vals, na.rm = TRUE)
    )
  })
  data.table::rbindlist(rows)[order(window_id)]
}

#' Trend-Test: ist die Drift-Staerke ueber die Fenster hinweg
#' SYSTEMATISCH (monoton mit dem Fenster-Index korreliert), oder nur
#' zufaellige Fenster-zu-Fenster-Schwankung?
#'
#' @param window_drift_dt Rueckgabe von `rolling_univariate_drift()`.
#' @param metric_col Welche Spalte als Drift-Staerke gilt (Default
#'   `"mean_effect_size"`).
#' @return Liste mit `rho` (Spearman), `p_value`, `trend_detected`
#'   (`|rho| > 0.5` UND `p_value < 0.05` - bewusst beide Bedingungen,
#'   analog zur restlichen Template-Konvention "Signifikanz UND
#'   Effektgroesse", siehe `missingness_mechanism_audit.R`s
#'   `min_effect_size`-Lehre).
drift_trend_test <- function(window_drift_dt, metric_col = "mean_effect_size") {
  n <- nrow(window_drift_dt)
  if (n < 3) {
    return(list(rho = NA_real_, p_value = NA_real_, trend_detected = FALSE))
  }
  test <- suppressWarnings(stats::cor.test(
    window_drift_dt$window_id, window_drift_dt[[metric_col]], method = "spearman"))
  rho <- unname(test$estimate)
  p_value <- test$p.value
  trend_detected <- !is.na(p_value) && !is.na(rho) && p_value < 0.05 && abs(rho) > 0.5
  list(rho = rho, p_value = p_value, trend_detected = trend_detected)
}
