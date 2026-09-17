# =====================================================================
# test_combined_task_helper.R -- Verifikation von combined_task_helper.R
# (build_combined_task_regr()). Prueft insbesondere, dass der Combined-
# Task genau die "different column info"-Falle vermeidet, die er beheben
# soll: unterschiedliche Typinferenz je Datei UND unterschiedliche
# Faktor-Levels zwischen Train und Test.
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
})
project_dir <- normalizePath(".")
source(file.path(project_dir, "modules", "combined_task_helper.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}

# Train: x1 hat Nachkommastellen (numeric), Test: x1 zufaellig nur ganze
# Zahlen (fread wuerde das als integer lesen) - klassischer Typ-Drift.
train <- data.table(x1 = c(1.5, 2.5, 3.5, 4.5), cat = c("a", "b", "a", "c"), y = c(10, 20, 30, 40))
test <- data.table(x1 = c(5L, 6L, 7L), cat = c("a", "b", "b"), y = c(50, 60, 70))
# cat hat im Test nicht alle Train-Levels ("c" fehlt), simuliert Faktor-Level-Delta.

res <- build_combined_task_regr(train, test, feature_cols = c("x1", "cat"), target_col = "y")

check("Task hat train+test Zeilen", res$task$nrow == nrow(train) + nrow(test))
check("train_rows/test_rows disjunkt und vollstaendig",
      length(intersect(res$train_rows, res$test_rows)) == 0 &&
        length(union(res$train_rows, res$test_rows)) == res$task$nrow)
check("x1 ist numeric im kombinierten Task (kein Typ-Drift)",
      res$task$feature_types[id == "x1"]$type == "numeric")
check("cat hat ALLE Levels aus Train UND Test (gemeinsamer Faktor)",
      setequal(res$task$levels("cat")$cat, c("a", "b", "c")))

# Train/Predict auf dem kombinierten Task duerfen NICHT mit "different
# column info" scheitern - das ist der eigentliche Regressionstest.
learner <- lrn("regr.rpart")
fit_ok <- tryCatch({
  learner$train(res$task, row_ids = res$train_rows)
  pred <- learner$predict(res$task, row_ids = res$test_rows)
  length(pred$response) == length(res$test_rows)
}, error = function(e) FALSE)
check("train()/predict() auf demselben Task laufen ohne Fehler durch", fit_ok)

check("train_task enthaelt nur Train-Zeilen", res$train_task$nrow == nrow(train))

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
