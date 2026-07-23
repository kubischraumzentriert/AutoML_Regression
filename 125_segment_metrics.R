rm(list = ls())

suppressPackageStartupMessages(library(data.table))

source("000_config.R")

if (!file.exists(full_holdout_predictions_path)) {
  stop("Holdout-Predictions fehlen. Erst 120_full_holdout_confirmation.R ausfuehren.")
}
if (!length(segment_metric_cols)) {
  cat("Keine segment_metric_cols in 000_config.R gesetzt. Segmentmetriken uebersprungen.\n")
  quit(save = "no", status = 0)
}

train <- fread(train_path)
pred <- fread(full_holdout_predictions_path)
missing_cols <- setdiff(segment_metric_cols, names(train))
if (length(missing_cols)) {
  stop("Segmentspalten fehlen in train.csv: ", paste(missing_cols, collapse = ", "))
}

prediction_cols <- setdiff(names(pred), c("row_id", "truth"))
metric_values <- function(truth, response) {
  c(
    rmse = sqrt(mean((truth - response) ^ 2, na.rm = TRUE)),
    mae = mean(abs(truth - response), na.rm = TRUE),
    bias = mean(response - truth, na.rm = TRUE)
  )
}

segments <- train[pred$row_id, ..segment_metric_cols]
eval_dt <- cbind(pred, segments)

results <- rbindlist(lapply(segment_metric_cols, function(segment_col) {
  rbindlist(lapply(prediction_cols, function(pred_col) {
    eval_dt[, {
      metrics <- metric_values(truth, get(pred_col))
      c(list(n = .N), as.list(metrics))
    }, by = .(segment_value = as.character(get(segment_col)))][
      , `:=`(segment_col = segment_col, model = pred_col)][]
  }))
}), fill = TRUE)

setcolorder(results, c("segment_col", "segment_value", "model", "n", "rmse", "mae", "bias"))
setorder(results, segment_col, segment_value, rmse)
fwrite(results, segment_metrics_path)

cat("=== Segmentmetriken ===\n")
print(results)
cat("\nGespeichert:", segment_metrics_path, "\n")
