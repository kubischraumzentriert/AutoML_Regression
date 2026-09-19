# =====================================================================
# test_config_helpers.R -- Verifikation der Helper-Funktionen aus
# 000_config.R (add_log_offset(), algorithm_from_learner_id()). Bisher
# ungetestet (Clean-Code-Review 2026-09-19, Regression-Pendant zum
# Classifikation-Review) - add_log_offset() ist an 2 unabhaengigen
# Projekten (tweet/dataCar) real bestaetigt (siehe BACKLOG.md Punkt 10),
# hatte aber selbst nie eine eigenstaendige Testdatei; die 3 stopifnot()-
# Bedingungen bekamen im selben Review benannte Fehlermeldungen (P0.2-
# Muster aus dem Klassifikations-Template).
# =====================================================================
rm(list = ls())
suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners) # regr.lm ist dort registriert, nicht im mlr3-Kernpaket
})
project_dir <- normalizePath(".")
source(file.path(project_dir, "000_config.R"))

ok <- TRUE
check <- function(name, cond) {
  cat(sprintf("  [%s] %s\n", if (isTRUE(cond)) "OK" else "FAIL", name))
  if (!isTRUE(cond)) ok <<- FALSE
}

# --- add_log_offset() -------------------------------------------------------

train <- data.table(
  exposure = c(1, 2, 0.5, 3),
  x1 = c(10, 20, 30, 40),
  y = c(2, 5, 1, 8)
)
task <- as_task_regr(train, target = "y", id = "offset_test")

task_offset <- add_log_offset(task, "exposure")

check("log-Offset-Spalte 'log_exposure' existiert im Task", "log_exposure" %in% task_offset$col_roles$offset)
check("log_exposure ist NICHT als normales Feature vorhanden", !"log_exposure" %in% task_offset$feature_names)
check("rohe Exposure-Spalte ist NICHT mehr als Feature vorhanden (keine Doppelnutzung)", !"exposure" %in% task_offset$feature_names)
check("x1 bleibt unveraendert als Feature erhalten", "x1" %in% task_offset$feature_names)
check("log_exposure-Werte entsprechen log(exposure)", {
  actual <- task_offset$data(cols = "log_exposure")[["log_exposure"]]
  isTRUE(all.equal(actual, log(train$exposure)))
})

# offset-Property-Learner (regr.lm - mlr3-Basispaket, "offset" laut
# mlr_learners-Registry; der Kopfkommentar oben nennt "regr.glm" als
# Beispiel, das ist aber kein tatsaechlich registrierter mlr3-Learner-Key -
# regr.lm hier bewusst als real existierender Ersatz) muss mit dem Offset
# trainieren/vorhersagen koennen, ohne "different column info"/Fehler -
# das ist der eigentliche Regressionstest fuers Zusammenspiel mit mlr3.
fit_ok <- tryCatch({
  learner <- lrn("regr.lm")
  learner$train(task_offset)
  pred <- learner$predict(task_offset)
  length(pred$response) == task_offset$nrow
}, error = function(e) FALSE)
check("train()/predict() mit regr.lm (offset-Property) laufen ohne Fehler durch", fit_ok)

# --- algorithm_from_learner_id() --------------------------------------------

check("erkennt 'ranger' in einer zusammengesetzten Learner-Id", algorithm_from_learner_id("imputemedian.regr.ranger") == "ranger")
check("erkennt 'lightgbm'", algorithm_from_learner_id("regr.lightgbm") == "lightgbm")
check("erkennt 'catboost'", algorithm_from_learner_id("preprocess.regr.catboost") == "catboost")
check("erkennt 'rpart'", algorithm_from_learner_id("regr.rpart") == "rpart")
check("wirft einen Fehler bei einer nicht abbildbaren Learner-Id (kein stiller Fallback)", {
  tryCatch({
    algorithm_from_learner_id("regr.glmnet")
    FALSE
  }, error = function(e) TRUE)
})

cat(sprintf("\n%s\n", if (ok) "Alle Checks OK." else "MINDESTENS EIN CHECK FEHLGESCHLAGEN."))
if (!ok) quit(status = 1)
