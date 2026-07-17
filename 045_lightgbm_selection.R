# Gemeinsame Auswahl zwischen Standard- und getuntem LightGBM. Die Auswahl
# entsteht in 100 aus einer separaten 5-fachen CV und wird danach nicht erneut
# auf OOF- oder Holdout-Daten optimiert.
read_lightgbm_selection <- function() {
  if (!file.exists(lightgbm_selection_path)) {
    stop("LightGBM-Auswahl fehlt. Bitte zuerst 100_lightgbm_tuning.R ausfuehren.")
  }
  selection <- readRDS(lightgbm_selection_path)
  if (!selection$variant %in% c("default", "tuned")) {
    stop("Unbekannte LightGBM-Variante im Auswahl-Artefakt: ", selection$variant)
  }
  selection
}

make_selected_lightgbm <- function(selection = read_lightgbm_selection()) {
  learner <- make_encoded_imputed_learner(lrn(
    "regr.lightgbm", num_iterations = lightgbm_baseline_iterations,
    learning_rate = 0.05, seed = seed, verbose = -1
  ))
  if (identical(selection$variant, "tuned")) {
    learner$param_set$values <- utils::modifyList(learner$param_set$values, selection$tuned_params)
  }
  learner
}

selected_lightgbm_hyperparams <- function(selection = read_lightgbm_selection()) {
  if (identical(selection$variant, "tuned")) {
    params <- selection$tuned_params
    names(params) <- sub("^regr\\.lightgbm\\.", "", names(params))
    return(c(params, list(selection_variant = "tuned")))
  }
  list(
    num_iterations = lightgbm_baseline_iterations,
    learning_rate = 0.05,
    selection_variant = "default"
  )
}
