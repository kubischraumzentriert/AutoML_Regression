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

# Kandidaten-Pool fuer die Caruana-Greedy-Ensemble-Selection (siehe
# REFERENZ_ENSEMBLE_SELECTION.md im Klassifikations-Template, identisch
# uebernommen). Reproduziert den Train/Test-Split aus
# `120_full_holdout_confirmation.R` DETERMINISTISCH (gleicher Seed, gleiche
# Reihenfolge) statt einen neuen Split zu ziehen oder ein weiteres Artefakt
# einzufuehren - loses Kopplungsmuster.
train <- fread(train_path)
train[, (id_col) := NULL]
feature_char_cols <- setdiff(names(train)[vapply(train, is.character, logical(1))], target_col)
train[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
train[, (target_col) := as.numeric(get(target_col))]
task_full <- as_task_regr(train, target = target_col, id = paste0(target_col, "_ensemble_pool"))

set.seed(full_holdout_seed)
resampling <- rsmp("holdout", ratio = full_holdout_train_ratio)
resampling$instantiate(task_full)
train_ids <- resampling$train_set(1)
test_ids <- resampling$test_set(1)
truth <- as.numeric(task_full$truth(test_ids))
cat(sprintf("Split (identisch zu 120): train=%d test=%d\n", length(train_ids), length(test_ids)))

# Pool-Training NUR auf einer Stichprobe von train_ids (siehe 000_config.R) -
# Bewertung bleibt auf dem vollen test_ids.
set.seed(seed)
if (length(train_ids) > ensemble_pool_train_sample_n) {
  train_ids <- sample(train_ids, ensemble_pool_train_sample_n)
  cat(sprintf("Pool-Training auf Stichprobe von %d Zeilen (aus %d) - siehe ensemble_pool_train_sample_n.\n",
              length(train_ids), length(resampling$train_set(1))))
}

set.seed(seed)
n_per_family <- ensemble_pool_n_per_family
sample_grid <- function(grid, n) grid[sample.int(nrow(grid), min(n, nrow(grid))), , drop = FALSE]

ranger_grid <- sample_grid(expand.grid(
  mtry.ratio = c(0.3, 0.5, 0.7, 1.0), min.node.size = c(1L, 5L, 10L, 20L)
), n_per_family)
lightgbm_grid <- sample_grid(expand.grid(
  num_leaves = c(15L, 31L, 63L, 127L), learning_rate = c(0.01, 0.05, 0.1), feature_fraction = c(0.6, 0.8, 1.0)
), n_per_family)
catboost_grid <- sample_grid(expand.grid(
  depth = c(4L, 6L, 8L), learning_rate = c(0.01, 0.05, 0.1), iterations = c(100L, 200L)
), n_per_family)

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

candidate_specs <- c(
  lapply(seq_len(nrow(ranger_grid)), function(i) list(family = "ranger", params = as.list(ranger_grid[i, ]))),
  lapply(seq_len(nrow(lightgbm_grid)), function(i) list(family = "lightgbm", params = as.list(lightgbm_grid[i, ]))),
  lapply(seq_len(nrow(catboost_grid)), function(i) list(family = "catboost", params = as.list(catboost_grid[i, ])))
)
cat(sprintf("Kandidaten-Pool: %d Modelle (%d ranger / %d lightgbm / %d catboost)\n",
            length(candidate_specs), nrow(ranger_grid), nrow(lightgbm_grid), nrow(catboost_grid)))

t0 <- Sys.time()
pred_list <- vector("list", length(candidate_specs))
labels <- character(length(candidate_specs))
families <- character(length(candidate_specs))
for (i in seq_along(candidate_specs)) {
  spec <- candidate_specs[[i]]
  learner <- make_candidate_learner(spec$family, spec$params)
  learner$train(task_full, row_ids = train_ids)
  pred_list[[i]] <- learner$predict(task_full, row_ids = test_ids)$response
  labels[i] <- sprintf("%s_%d", spec$family, i)
  families[i] <- spec$family
  if (i %% 5 == 0) cat(sprintf("  %d/%d Kandidaten fertig (%.0fs)\n", i, length(candidate_specs), as.numeric(Sys.time() - t0, units = "secs")))
}
cat(sprintf("Pool-Training fertig: %.1f Minuten\n", as.numeric(Sys.time() - t0, units = "mins")))

saveRDS(
  list(labels = labels, families = families, candidate_specs = candidate_specs,
       pred_list = pred_list, truth = truth, test_ids = test_ids, target_col_name = target_col),
  ensemble_candidate_pool_path
)
cat("Gespeichert:", ensemble_candidate_pool_path, "\n")
