# =====================================================================
# time_blocked_resampling.R -- zeitgeblocktes/rollierendes Resampling als
# eigene Strategie neben `rsmp("cv")`/`rsmp("holdout")`.
# =====================================================================
# BACKLOG.md-Kandidat Nr. 1 (Herkunft: GeoAI-Drought), an 2 unabhaengigen
# Panel-/Forecasting-Projekten bestaetigt (GeoAI-Drought, Rossmann Store
# Sales - siehe REFERENZ_AVAILABILITY_MASKING.md Abschnitt 4 fuer die
# Herleitung/Zahlen). Optional, projektspezifisch (Datumsspalte muss explizit
# angegeben werden) - kein Eingriff in bestehende `rsmp("cv")`-Aufrufe,
# solange kein Projekt diese Funktion aufruft.
#
# Wichtig: OOF-Ensemble-Aufbau (`110_oof_ensemble.R`) und Tuning muessen bei
# Zeitreihen-/Panel-Daten DENSELBEN instanziierten Split verwenden wie die
# finale Bewertung - sonst optimiert das Tuning auf eine andere
# (z.B. zufaellige) Datenaufteilung als die, gegen die am Ende verglichen wird.

#' Instanziiert ein Resampling fuer einen `mlr3`-Task.
#'
#' @param task `TaskRegr`/`TaskClassif`.
#' @param purpose "cv" (klassische K-fache Kreuzvalidierung, ignoriert Zeit),
#'   "holdout" (`rsmp("holdout")`), oder "time_blocked" (Rolling-Origin:
#'   K aufeinanderfolgende Zeitbloecke, jeder Trainingsblock endet strikt VOR
#'   seinem Validierungsblock - kein Blick in die Zukunft der Entity).
#' @param date_col Spaltenname mit dem Datum (nur fuer `purpose="time_blocked"`
#'   noetig) - muss im Task als Feature ODER separat uebergebenes `data.table`
#'   vorliegen (siehe `dt`-Parameter).
#' @param dt Optionales `data.table` mit derselben Zeilenreihenfolge wie
#'   `task$row_ids`, falls `date_col` nicht im Task selbst als Feature-Spalte
#'   enthalten ist (z.B. weil das Datum bewusst NICHT als Modell-Feature
#'   verwendet wird). Default: liest `date_col` direkt aus `task$data()`.
#' @param k Anzahl Bloecke/Folds.
#' @param block_range Anteilsbereich (0,1) der Zeitspanne, an dem die K
#'   Cutoffs liegen - Default `c(0.5, 0.9)` verwendet die zweite Haelfte der
#'   Zeitspanne fuer die Validierungsbloecke, analog zum Rossmann-Test.
#' @return `Resampling` (`rsmp("custom")`, bereits instanziiert) fuer
#'   "time_blocked", sonst das Standard-`mlr3`-Resampling-Objekt (NICHT
#'   instanziiert - der Aufrufer instanziiert wie gewohnt selbst).
make_resampling <- function(task, purpose = c("cv", "holdout", "time_blocked"),
                             date_col = NULL, dt = NULL, k = 5L, block_range = c(0.5, 0.9)) {
  purpose <- match.arg(purpose)
  if (purpose != "time_blocked") {
    return(mlr3::rsmp(purpose))
  }
  stopifnot("date_col muss gesetzt sein fuer purpose='time_blocked'" = !is.null(date_col))
  dates <- if (!is.null(dt)) dt[[date_col]] else task$data(cols = date_col)[[1]]
  stopifnot("dates muss dieselbe Laenge wie task$nrow haben" = length(dates) == task$nrow)

  unique_dates <- sort(unique(dates))
  cuts <- unique_dates[round(seq(block_range[1], block_range[2], length.out = k + 1) * length(unique_dates))]

  train_sets <- vector("list", k)
  test_sets <- vector("list", k)
  row_ids <- task$row_ids
  for (i in seq_len(k)) {
    train_sets[[i]] <- row_ids[dates < cuts[i]]
    test_sets[[i]] <- row_ids[dates >= cuts[i] & dates < cuts[i + 1]]
  }
  resampling <- mlr3::rsmp("custom")
  resampling$instantiate(task, train_sets = train_sets, test_sets = test_sets)
  resampling
}
