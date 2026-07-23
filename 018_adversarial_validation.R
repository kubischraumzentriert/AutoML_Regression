rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3learners)
  library(mlr3pipelines)
})

source("000_config.R")
source(file.path(project_dir, "040_preprocessing.R"))

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

train <- fread(train_path)
test <- fread(test_path)

feature_cols <- intersect(
  setdiff(names(train), adversarial_exclude_cols),
  setdiff(names(test), adversarial_exclude_cols)
)
if (!length(feature_cols)) {
  stop("Keine gemeinsamen Features fuer Adversarial Validation gefunden.")
}

n_each <- min(nrow(train), nrow(test), floor(adversarial_validation_sample_n / 2))
train_sample <- train[sample.int(.N, n_each), ..feature_cols]
test_sample <- test[sample.int(.N, n_each), ..feature_cols]
train_sample[, dataset_origin := "train"]
test_sample[, dataset_origin := "test"]
combined <- rbindlist(list(train_sample, test_sample), use.names = TRUE, fill = TRUE)

char_cols <- names(combined)[vapply(combined, is.character, logical(1))]
combined[, (char_cols) := lapply(.SD, as.factor), .SDcols = char_cols]
combined[, dataset_origin := factor(dataset_origin, levels = c("train", "test"))]

task <- as_task_classif(combined, target = "dataset_origin", id = paste0(project_name, "_adversarial"))
learner <- make_imputed_learner(lrn(
  "classif.ranger",
  predict_type = "prob",
  num.trees = ranger_baseline_trees,
  respect.unordered.factors = "order",
  seed = seed
))
resampling <- rsmp("cv", folds = adversarial_validation_folds)
rr <- resample(task, learner, resampling, store_models = FALSE)

prediction <- rr$prediction()
prob_test <- prediction$prob[, "test"]
truth <- prediction$truth == "test"
rank_prob <- rank(prob_test, ties.method = "average")
n_pos <- as.numeric(sum(truth))
n_neg <- as.numeric(length(truth) - n_pos)
auc <- (sum(rank_prob[truth]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
propensity <- pmin(0.999, pmax(0.001, prob_test))
weights <- ifelse(truth, 0.5 / propensity, 0.5 / (1 - propensity))
ess_ratio <- (sum(weights) ^ 2 / sum(weights ^ 2)) / length(weights)

results <- data.table(
  feature_set = "common_features",
  n_train_sample = n_each,
  n_test_sample = n_each,
  n_features = length(feature_cols),
  folds = adversarial_validation_folds,
  auc = auc,
  ess_ratio = ess_ratio
)
predictions <- data.table(
  row_id = prediction$row_ids,
  truth = as.character(prediction$truth),
  prob_test = prob_test,
  weight = weights
)

fwrite(results, adversarial_validation_results_path)
fwrite(predictions, adversarial_validation_prediction_path)

cat("=== Adversarial Validation ===\n")
print(results)
cat("\nInterpretation:\n")
cat("- AUC nahe 0.5: Train/Test schwer unterscheidbar.\n")
cat("- AUC deutlich > 0.7: moeglicher Shift; Validation und Feature-Availability pruefen.\n")
cat("- ESS/n klein: Propensity-Gewichte waeren instabil.\n")
cat("\nGespeichert:\n")
cat("Ergebnisse :", adversarial_validation_results_path, "\n")
cat("Predictions:", adversarial_validation_prediction_path, "\n")
