# =====================================================================
# combined_task_helper.R -- baut EINEN gemeinsamen mlr3-Task aus separat
# eingelesenen Train-/Test-Datensaetzen (z.B. `train.csv`/`test.csv`).
# =====================================================================
# Grund: mlr3 wirft "Learner ... received task with different column info
# (feature type or factor level ordering) during train and predict", wenn
# Train und Test als ZWEI getrennte Tasks gebaut werden - `fread`/ CSV-
# Import inferiert Spaltentypen je Datei unabhaengig (z.B. `numeric` im
# Train, `integer` im Test, wenn die Testscheibe zufaellig nur ganze Zahlen
# enthaelt), und Faktor-Level-Mengen/-Reihenfolgen koennen abweichen.
#
# Diese Falle ist seit WORKFLOW_GUARDS.md Abschnitt 8 als Prosa dokumentiert,
# ist aber trotzdem in mehreren Panel-/Forecasting-Projekten wiederholt
# hineingelaufen worden (Beijing-Air-Quality-Panel: `026`, `029`, jeweils
# trotz bekannter Falle). Lehre daraus: dokumentiertes Wissen ueber eine
# Falle verhindert das Hineinlaufen nicht zuverlaessig - nur ein
# wiederverwendbarer Code-Baustein tut das. Diese Datei ist genau das.

suppressPackageStartupMessages(library(data.table))

#' Baut einen gemeinsamen Regressions-Task aus Train + Test.
#'
#' @param train,test `data.table`/`data.frame` mit identischen Feature-
#'   Spalten (Test darf das Ziel enthalten oder NA/fehlen - wird nur fuer
#'   den Combined-Task-Bau benoetigt und danach nicht ausgewertet).
#' @param feature_cols Character-Vektor der Feature-Spaltennamen (OHNE
#'   Zielspalte).
#' @param target_col Name der Zielspalte (numerisch).
#' @param id Task-Id (Default `"combined"`).
#' @return Liste mit `task` (der gemeinsame `TaskRegr`), `train_rows` und
#'   `test_rows` (Row-Id-Vektoren fuer `learner$train(task, row_ids=...)`/
#'   `learner$predict(task, row_ids=...)`), sowie `train_task` (bereits
#'   gefilterter Klon nur der Train-Zeilen, praktisch fuer Resampling-
#'   Instantiierung wie `make_resampling(train_task, ...)`).
#' @details Erzwingt explizite Typisierung (numerisch -> `as.numeric`,
#'   Zeichenketten -> `as.factor`) auf dem KOMBINIERTEN Datensatz, bevor der
#'   Task gebaut wird - das ist der eigentliche Fix, nicht nur das `rbind`.
build_combined_task_regr <- function(train, test, feature_cols, target_col,
                                      id = "combined") {
  stopifnot(all(feature_cols %in% names(train)), all(feature_cols %in% names(test)))
  stopifnot(target_col %in% names(train))

  cols <- c(feature_cols, target_col)
  tr <- copy(as.data.table(train))[, ..cols]
  tr[, .is_test := FALSE]

  te <- copy(as.data.table(test))[, intersect(cols, names(test)), with = FALSE]
  if (!target_col %in% names(te)) te[, (target_col) := NA_real_]
  te <- te[, ..cols]
  te[, .is_test := TRUE]

  comb <- rbind(tr, te)

  num_cols <- setdiff(feature_cols, names(comb)[vapply(comb, is.character, logical(1))])
  comb[, (num_cols) := lapply(.SD, as.numeric), .SDcols = num_cols]
  char_cols <- names(comb)[vapply(comb, is.character, logical(1))]
  char_cols <- intersect(char_cols, feature_cols)
  comb[, (char_cols) := lapply(.SD, as.factor), .SDcols = char_cols]

  task_all <- mlr3::as_task_regr(comb[, !".is_test"], target = target_col, id = id)
  train_rows <- which(!comb$.is_test)
  test_rows <- which(comb$.is_test)
  train_task <- task_all$clone(deep = TRUE)$filter(train_rows)

  list(task = task_all, train_rows = train_rows, test_rows = test_rows,
       train_task = train_task)
}
