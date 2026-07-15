rm(list = ls())

suppressPackageStartupMessages(library(data.table))
source("000_config.R")

train <- fread(train_path)

cat("=== EDA: Trainingdaten ===\n")
cat("Zeilen:", nrow(train), " Spalten:", ncol(train), "\n")
cat("\nSpaltentypen:\n")
print(data.table(column = names(train), class = vapply(train, class, character(1))))
cat("\nFehlende Werte je Spalte:\n")
print(colSums(is.na(train)))
cat("\nZielvariable:", target_col, "\n")
print(summary(train[[target_col]]))
cat("Eindeutige Zielwerte:", uniqueN(train[[target_col]]), "\n")
