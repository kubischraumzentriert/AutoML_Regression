rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")

dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

train <- fread(train_path)
test <- fread(test_path)

train_cols <- names(train)
test_cols <- names(test)
train_feature_cols <- setdiff(train_cols, c(id_col, target_col))
test_feature_cols <- setdiff(test_cols, id_col)
common_feature_cols <- intersect(train_feature_cols, test_feature_cols)
train_only_cols <- setdiff(train_feature_cols, test_feature_cols)
test_only_cols <- setdiff(test_feature_cols, train_feature_cols)

class_name <- function(x) paste(class(x), collapse = "|")
sentinel_count <- function(x) {
  if (!is.numeric(x)) {
    return(NA_integer_)
  }
  sum(x %in% feature_availability_sentinel_values, na.rm = TRUE)
}

summary_dt <- rbindlist(list(
  data.table(scope = "train_only_feature", column = train_only_cols),
  data.table(scope = "test_only_feature", column = test_only_cols),
  data.table(scope = "common_feature", column = common_feature_cols)
), fill = TRUE)

missingness <- rbindlist(lapply(common_feature_cols, function(col) {
  train_missing <- mean(is.na(train[[col]]))
  test_missing <- mean(is.na(test[[col]]))
  data.table(
    column = col,
    train_class = class_name(train[[col]]),
    test_class = class_name(test[[col]]),
    train_missing_rate = train_missing,
    test_missing_rate = test_missing,
    missing_rate_delta = test_missing - train_missing,
    train_unique_n = uniqueN(train[[col]], na.rm = TRUE),
    test_unique_n = uniqueN(test[[col]], na.rm = TRUE),
    train_sentinel_n = sentinel_count(train[[col]]),
    test_sentinel_n = sentinel_count(test[[col]])
  )
}))

missingness[, abs_missing_rate_delta := abs(missing_rate_delta)]
setorder(missingness, -abs_missing_rate_delta)
fwrite(summary_dt, feature_availability_summary_path)
fwrite(missingness, feature_availability_missingness_path)

report <- c(
  "=== Feature Availability Audit ===",
  paste("Train rows:", nrow(train), "columns:", ncol(train)),
  paste("Test rows :", nrow(test), "columns:", ncol(test)),
  paste("Common features:", length(common_feature_cols)),
  paste("Train-only features:", length(train_only_cols)),
  paste("Test-only features :", length(test_only_cols)),
  "",
  "Train-only feature columns:",
  if (length(train_only_cols)) paste(" -", train_only_cols) else " - none",
  "",
  "Test-only feature columns:",
  if (length(test_only_cols)) paste(" -", test_only_cols) else " - none",
  "",
  "Largest missingness shifts:",
  capture.output(print(head(missingness, 20))),
  "",
  "External source policy:",
  if (nrow(external_source_policy)) capture.output(print(external_source_policy)) else " - none configured"
)
writeLines(report, feature_availability_report_path)

cat(paste(report, collapse = "\n"), "\n")
cat("\nGespeichert:\n")
cat("Summary    :", feature_availability_summary_path, "\n")
cat("Missingness:", feature_availability_missingness_path, "\n")
cat("Report     :", feature_availability_report_path, "\n")
