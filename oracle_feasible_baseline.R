# =====================================================================
# oracle_feasible_baseline.R -- Oracle- vs. Feasible-Baseline trennen,
# Metriken nach Availability-Segmenten gruppieren.
# =====================================================================
# BACKLOG.md-Kandidat Nr. 3 (Herkunft: GeoAI-Drought), an 2 unabhaengigen
# Panel-/Forecasting-Projekten bestaetigt (siehe REFERENZ_AVAILABILITY_
# MASKING.md Abschnitt 3). Baut auf `012_feature_availability_audit.R`s
# `train_only_cols`-Erkennung auf: eine Spalte, die im Training aber NICHT
# im Test existiert, darf im deploybaren ("feasible") Modell nicht verwendet
# werden. Ein Modell, das sie trotzdem nutzt ("oracle"), zeigt das Ausmass
# des Risikos, BEVOR es in Produktion zum Problem wird.
suppressPackageStartupMessages(library(mlr3))

#' Vergleicht ein Feasible- gegen ein Oracle-Modell auf demselben Split.
#'
#' @param dt `data.table` mit allen Zeilen/Spalten (Training + der zu
#'   bewertende Holdout, ueber `train_idx`/`valid_idx` abgegrenzt).
#' @param target_col Zielspalte.
#' @param feasible_cols Feature-Spalten, die auch in `test.csv` existieren.
#' @param oracle_extra_cols Zusaetzliche Spalten, die NUR im Training
#'   existieren (aus `012`s `train_only_cols`) - werden dem Oracle-Modell
#'   hinzugefuegt, dem Feasible-Modell NICHT.
#' @param train_idx,valid_idx Zeilenindizes fuer Training/Bewertung (fester
#'   Split, damit beide Modelle exakt vergleichbar sind).
#' @param learner_fn Funktion ohne Argumente, die einen frischen `mlr3`-
#'   Learner erzeugt (Default: `regr.ranger`, 200 Baeume).
#' @param segment_cols Optional: benannte Liste `Segmentname = logischer
#'   Vektor (Laenge = length(valid_idx))` fuer eine Aufschluesselung nach
#'   Availability-/Kalender-Segmenten (z.B. Feiertag ja/nein). Wird IMMER um
#'   ein "Alle"-Segment (alle Zeilen) ergaenzt.
#' @return `data.table` mit `segment`, `rmse_feasible`, `rmse_oracle`, `n`.
oracle_feasible_comparison <- function(dt, target_col, feasible_cols, oracle_extra_cols,
                                        train_idx, valid_idx,
                                        learner_fn = function() lrn("regr.ranger", num.trees = 200),
                                        segment_cols = list()) {
  fit_predict <- function(cols) {
    task_train <- as_task_regr(dt[train_idx, c(target_col, cols), with = FALSE], target = target_col)
    learner <- learner_fn()
    learner$train(task_train)
    learner$predict_newdata(dt[valid_idx, cols, with = FALSE])$response
  }
  rmse <- function(pred, truth) sqrt(mean((pred - truth)^2))

  pred_feasible <- fit_predict(feasible_cols)
  pred_oracle <- fit_predict(c(feasible_cols, oracle_extra_cols))
  truth <- dt[[target_col]][valid_idx]

  segments <- c(list(Alle = rep(TRUE, length(valid_idx))), segment_cols)
  data.table::rbindlist(lapply(names(segments), function(nm) {
    mask <- segments[[nm]]
    data.table::data.table(
      segment = nm,
      rmse_feasible = rmse(pred_feasible[mask], truth[mask]),
      rmse_oracle = rmse(pred_oracle[mask], truth[mask]),
      n = sum(mask)
    )
  }))
}
