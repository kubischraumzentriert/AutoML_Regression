rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
})

source("000_config.R")

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

train <- fread(train_path)
train_small <- train[sample.int(.N, size = floor(.N * subset_fraction))]
train_small[, (id_col) := NULL]

feature_char_cols <- names(train_small)[vapply(train_small, is.character, logical(1))]
train_small[, (feature_char_cols) := lapply(.SD, as.factor), .SDcols = feature_char_cols]
train_small[, (target_col) := as.numeric(get(target_col))]

task_train_small <- as_task_regr(
  train_small,
  target = target_col,
  id = task_id_prefix
)

saveRDS(task_train_small, task_train_small_path)

cat("=== mlr3 Regressionstask gespeichert ===\n")
cat("Pfad:", task_train_small_path, "\n")
print(task_train_small)
cat("\nFeature Types:\n")
print(task_train_small$feature_types)
