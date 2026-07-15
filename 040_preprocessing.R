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
