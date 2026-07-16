suppressPackageStartupMessages({
  library(mlr3)
  library(mlr3pipelines)
})

make_imputed_learner <- function(base_learner) {
  as_learner(
    po("imputemedian") %>>%
      po("imputemode") %>>%
      base_learner
  )
}

# Boosting-Learner erhalten eine numerische Feature-Matrix. Das ist fuer
# LightGBM robust und macht den ersten Vergleich mit CatBoost vergleichbar.
make_encoded_imputed_learner <- function(base_learner) {
  as_learner(
    po("imputemedian") %>>%
      po("imputemode") %>>%
      po("encode") %>>%
      po("colapply", applicator = as.numeric) %>>%
      base_learner
  )
}
