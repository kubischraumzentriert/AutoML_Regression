library(targets)

# Deckt den etablierten *finalen* Produktionspfad ab (Volldaten-Task, finales
# Modell auf allen Daten, Submission) - entspricht 150_train_full_model.R und
# 155_predict_submission.R. Die explorativen Einzel-Experimente (030-125) bleiben
# manuelle Analyse-Werkzeuge fuer die Modellauswahl und gehoeren nicht in die
# reproduzierbare Pipeline. tar_make() ersetzt das manuelle Nacheinander von
# 150/155 durch einen cachenden Abhaengigkeitsgraphen: bei einer Aenderung an
# train.csv, an der Config oder an der LightGBM-Auswahl rechnet tar_make() nur
# die betroffenen nachgelagerten Ziele neu.
#
# Entwurfsmuster gespiegelt vom Klassifikations-Template (_targets.R deckt nur
# den finalen Pfad ab, kein DB-Seiteneffekt im Graphen - DB-Logging bleibt in den
# manuellen Skripten 150/160). Unterschied bewusst: die Regression liest die in
# 100_lightgbm_tuning.R getroffene Wahl als *Datei-Eingang* (lightgbm_selection.rds)
# statt ueber eine Selektions-CSV, damit eine neue Tuning-Wahl den Graphen korrekt
# invalidiert.

project_dir <- normalizePath(getwd())
source("000_config.R")
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "045_lightgbm_selection.R"))

tar_option_set(
  packages = c(
    "data.table", "mlr3", "mlr3learners",
    "mlr3extralearners", "mlr3pipelines"
  )
)

# Volldaten wie in 150 aufbereiten: id entfernen, character -> factor, Ziel
# numerisch. Liefert Daten UND die Faktor-Level, damit die Submission dieselbe
# Kodierung auf test.csv anwenden kann.
prepare_full_training_data <- function(train_file) {
  train <- fread(train_file)
  train[, (id_col) := NULL]
  feature_char_cols <- setdiff(
    names(train)[vapply(train, is.character, logical(1))],
    target_col
  )
  train[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
  train[, (target_col) := as.numeric(get(target_col))]
  list(
    data = train,
    feature_levels = lapply(train[, ..feature_char_cols], levels)
  )
}

# --- Ziele, die unabhaengig vom finalen Algorithmus sind --------------------
core_targets <- list(
  tar_target(train_full_file, train_path, format = "file"),
  tar_target(test_file, test_path, format = "file"),

  tar_target(full_training, prepare_full_training_data(train_full_file)),

  tar_target(task_full, {
    as_task_regr(
      full_training$data,
      target = target_col,
      id = paste0(target_col, "_full_", submission_model_name)
    )
  }),

  tar_target(
    submission,
    {
      test <- fread(test_file)
      test_ids <- test[[id_col]]
      test[, (id_col) := NULL]
      for (col in names(full_training$feature_levels)) {
        test[[col]] <- factor(test[[col]], levels = full_training$feature_levels[[col]])
      }
      predictions <- final_model_full$predict_newdata(test)$response
      predictions <- pmin(prediction_bounds[2], pmax(prediction_bounds[1], predictions))
      if (anyNA(predictions)) {
        stop("Die Submission enthaelt fehlende Vorhersagen.")
      }
      result <- data.table(id = test_ids, response = predictions)
      setnames(result, "id", id_col)
      setnames(result, "response", target_col)
      fwrite(result, submission_path)
      submission_path
    },
    format = "file"
  )
)

# --- Finales Modell: Selektions-Handoff je nach Algorithmus -----------------
# Der lightgbm-Zweig bindet lightgbm_selection.rds als Datei-Ziel ein, damit eine
# neue Tuning-Wahl den Graphen invalidiert. Der ranger-Zweig braucht die Auswahl
# nicht und laesst die Abhaengigkeit weg, statt eine ggf. fehlende Datei zu fordern.
if (identical(submission_model_algorithm, "lightgbm")) {
  model_targets <- list(
    tar_target(lightgbm_selection_file, lightgbm_selection_path, format = "file"),
    tar_target(final_model_full, {
      selection <- readRDS(lightgbm_selection_file)
      if (!selection$variant %in% c("default", "tuned")) {
        stop("Unbekannte LightGBM-Variante im Auswahl-Artefakt: ", selection$variant)
      }
      learner <- make_selected_lightgbm(selection)
      set.seed(seed)
      learner$train(task_full)
      learner
    })
  )
} else if (identical(submission_model_algorithm, "ranger")) {
  model_targets <- list(
    tar_target(final_model_full, {
      learner <- make_imputed_learner(lrn(
        "regr.ranger", num.trees = ranger_baseline_trees,
        respect.unordered.factors = "order", seed = seed
      ))
      set.seed(seed)
      learner$train(task_full)
      learner
    })
  )
} else {
  stop("Unterstuetzte finale Algorithmen fuer die targets-Pipeline: ranger, lightgbm.")
}

c(core_targets, model_targets)
