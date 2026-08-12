rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3extralearners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "040_preprocessing.R"))
source(file.path(project_dir, "db_logging.R"))

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

# Schliesst dieselbe Luecke wie im Klassifikations-Template (156_train_full_
# ensemble.R): 129_ensemble_selection.R liefert nur eine Entscheidung,
# 150_train_full_model.R kann aber nur EIN benanntes Modell auf vollen Daten
# trainieren. Dieses Skript trainiert stattdessen jeden EINDEUTIGEN
# ausgewaehlten Kandidaten aus `ensemble_composition_path` auf dem VOLLEN
# Trainingsdatensatz (Wiederholung wird als Gewicht beim Vorhersage-Mitteln
# in 131 verwendet, nicht als mehrfaches Training).
if (!file.exists(ensemble_composition_path)) {
  stop("Ensemble-Zusammensetzung fehlt. Erst 129_ensemble_selection.R ausfuehren.")
}
composition <- readRDS(ensemble_composition_path)
target_col_name <- composition$target_col_name

train <- fread(train_path)
train[, (id_col) := NULL]
feature_char_cols <- setdiff(names(train)[vapply(train, is.character, logical(1))], target_col_name)
train[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
train[, (target_col_name) := as.numeric(get(target_col_name))]
feature_levels <- lapply(train[, ..feature_char_cols], levels)

task_full <- as_task_regr(train, target = target_col_name, id = paste0(target_col_name, "_full_ensemble"))

# Identischer Kandidaten-Aufbau wie 127_ensemble_candidate_pool.R.
make_candidate_learner <- function(family, params) {
  if (family == "ranger") {
    make_imputed_learner(lrn("regr.ranger", num.trees = 200, respect.unordered.factors = "order", seed = seed,
                              mtry.ratio = params$mtry.ratio, min.node.size = params$min.node.size))
  } else if (family == "lightgbm") {
    make_encoded_imputed_learner(lrn("regr.lightgbm", num_iterations = 200, seed = seed, verbose = -1,
                                      num_leaves = params$num_leaves, learning_rate = params$learning_rate,
                                      feature_fraction = params$feature_fraction))
  } else {
    make_encoded_imputed_learner(lrn("regr.catboost", random_seed = seed, logging_level = "Silent", allow_writing_files = FALSE,
                                      depth = params$depth, learning_rate = params$learning_rate, iterations = params$iterations))
  }
}

n_members <- length(composition$selected_composition)
total_weight <- sum(vapply(composition$selected_composition, function(m) m$weight, integer(1)))
cat(sprintf("=== Ensemble-Volltraining: %d eindeutige Kandidaten (Zeilen: %d) ===\n", n_members, nrow(train)))
t0 <- Sys.time()
trained_members <- lapply(composition$selected_composition, function(member) {
  t_m <- Sys.time()
  learner <- make_candidate_learner(member$spec$family, member$spec$params)
  learner$train(task_full)
  cat(sprintf("  %s (Gewicht %d/%d) fertig (%.1f Min.)\n", member$label, member$weight, total_weight,
              as.numeric(Sys.time() - t_m, units = "mins")))
  list(learner = learner, weight = member$weight, label = member$label)
})
cat(sprintf("Ensemble-Training fertig: %.1f Minuten\n", as.numeric(Sys.time() - t0, units = "mins")))

# --- Experiment-Tracking (SQLite) -------------------------------------------
db_con <- db_connect()
db_proj_id <- db_get_or_create_project(db_con, project_name)
db_wf_id <- db_get_or_create_workflow(db_con, db_proj_id, "script", "130_train_full_ensemble.R")
composition_str <- paste(sprintf("%s:%d", vapply(trained_members, `[[`, character(1), "label"),
                                  vapply(trained_members, `[[`, integer(1), "weight")), collapse = ", ")
db_run_id <- db_create_run(db_con, db_wf_id, seed = seed, notes = sprintf(
  "Ensemble-Volltraining: %d Mitglieder (%s)", n_members, composition_str
))

model_path <- final_ensemble_full_path(db_run_id)
saveRDS(
  list(members = trained_members, feature_levels = feature_levels, target_col_name = target_col_name),
  model_path
)

db_create_model_config(
  db_con, db_run_id,
  task_type = "regr", algorithm = "ensemble", feature_set = "raw",
  preprocessing = "impute_median_mode", class_weight_power = NA_real_, task_id = task_full$id,
  hyperparams = list(model_artifact_path = model_path, n_members = n_members, composition = composition_str)
)
db_finish_run(db_con, db_run_id)
DBI::dbDisconnect(db_con)

cat("\nZusammensetzung:", composition_str, "\n")
cat("Gespeichert:", model_path, "\n")
cat("Experiment-DB:", experiments_db_path, "(run_id", db_run_id, ")\n")
