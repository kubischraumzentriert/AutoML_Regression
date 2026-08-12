if (!exists("project_dir")) {
  config_path <- normalizePath(sys.frame(1)$ofile)
  project_dir <- dirname(config_path)
}

train_path <- file.path(project_dir, "train.csv")
test_path <- file.path(project_dir, "test.csv")
sample_submission_path <- file.path(project_dir, "sample_submission.csv")

id_col <- "id"
target_col <- "accident_risk"
project_name <- "playground-series-s5e10-road-accident-risk"

# Kaggle bewertet die Vorhersagen mit RMSE; kleinere Werte sind besser.
primary_measure_id <- "regr.rmse"
baseline_measure_ids <- c("regr.rmse", "regr.mae", "regr.rsq")

seed <- 42
subset_fraction <- 0.10
validation_ratio <- 0.80
cv_folds <- 5
full_holdout_train_ratio <- 0.80
full_holdout_seed <- 2026
ranger_baseline_trees <- 100

task_id_prefix <- paste0(target_col, "_", subset_fraction * 100, "pct")

artifact_dir <- file.path(project_dir, "_artifacts")
experiments_db_path <- file.path(artifact_dir, "experiments.db")
task_train_small_path <- file.path(artifact_dir, "task_train_small.rds")
signal_diagnostics_path <- file.path(artifact_dir, "signal_diagnostics.csv")
signal_correlations_path <- file.path(artifact_dir, "signal_correlations.csv")
feature_availability_summary_path <- file.path(artifact_dir, "feature_availability_summary.csv")
feature_availability_missingness_path <- file.path(artifact_dir, "feature_availability_missingness.csv")
feature_availability_report_path <- file.path(artifact_dir, "feature_availability_report.txt")
feature_availability_sentinel_values <- c(-999, -9999, 999, 9999)

adversarial_validation_sample_n <- 150000L
adversarial_validation_folds <- 3L
adversarial_validation_results_path <- file.path(artifact_dir, "adversarial_validation_results.csv")
adversarial_validation_prediction_path <- file.path(artifact_dir, "adversarial_validation_predictions.csv")
adversarial_exclude_cols <- c(id_col, target_col)

# Univariate Drift-Tests (KS je stetigem Feature, Chi-Quadrat je kategorialem
# Feature, BH-korrigiert) - Ergaenzung zur Adversarial-Validation-AUC, siehe
# univariate_drift.R. Sagt WELCHE Features driften, nicht nur ob insgesamt
# trennbar. Zurueckgefuehrt aus dem Klassifikations-Template, dort an 2
# OpenML-Datensaetzen/3 Szenarien verifiziert, siehe dortiges TARGETS.md.
univariate_drift_results_path <- file.path(artifact_dir, "univariate_drift_results.csv")
univariate_drift_alpha <- 0.05

# Target-Leak-Audit (013): eine zu gute Baseline auf einer schweren Aufgabe ist
# ein Warnsignal, kein Erfolg - CV<->Leaderboard-Uebereinstimmung faengt einen
# Leak NICHT (das Artefakt steckt meist auch in den Testdaten). Rueckgefuehrt aus
# dem Klassifikations-Template (dort an African-Credit-Scoring bestaetigt: eine
# naive F1-0.88-Baseline war ein Ex-post-Leak, ehrlich F1 ~0.41). Schritt 2
# (Determinismus) ist hier fuer STETIGE Ziele adaptiert: statt P(Klasse|Wert)=0/1
# wird geprueft, ob die Zielstreuung INNERHALB einer Wertgruppe nahe Null ist
# relativ zur Gesamtstreuung (das Feature pinnt den Zielwert nahezu fest).
leak_audit_importance_share_threshold <- 0.50  # 1 Feature traegt >50% der Gain-Importance
# Kumulative Top-k-Schwelle (Punkt 13, BACKLOG.md) - faengt ein Leak-PAAR/eine
# Leak-GRUPPE, bei der kein einzelnes Feature ueber leak_audit_importance_
# share_threshold liegt, die fuehrenden Features zusammen aber fast die
# gesamte Importance tragen. leak_audit_cumulative_max_k begrenzt, wie viele
# fuehrende Features ueberhaupt betrachtet werden - verhindert, dass bei
# gleichmaessig verteilter Importance am Ende viele Features "verdaechtig"
# werden (das waere kein Leak-Befund mehr, nur triviale Schwellenerschoepfung).
# BEWUSST hoch (nicht 80%): der Check soll nur bei FAST VOLLSTAENDIGER
# Erklaerung greifen (typisch fuer einen exakten Leak wie casual+registered
# ==count, 100.0%), nicht schon wenn die fuehrenden Features "nur" den
# groessten Teil der Varianz erklaeren (das kann bei starken legitimen
# Praediktoren leicht 80-90% erreichen, ohne Leak zu sein - empirisch bei
# road-accident-risk beobachtet: 3 legitime Top-Features = 88%).
leak_audit_cumulative_share_threshold <- 0.98
leak_audit_cumulative_max_k <- 5L
leak_audit_suspect_top_n <- 8                  # max. Anzahl Verdaechtiger fuer die Zerlegung
leak_audit_determinism_min_n <- 30             # Mindestgruppengroesse fuer einen Determinismus-Fund
leak_audit_determinism_sd_ratio <- 0.10        # Gruppen-SD/Gesamt-SD unter dieser Schwelle = verdaechtig
leak_audit_cardinality_max <- 30               # nur Spalten mit <= so vielen eindeutigen Werten pruefen
# Optional: kategoriale Spalten, gegen die verdaechtige NUMERISCHE Features per
# Within-Stratum-Korrelation geprueft werden. Default leer = Schritt wird
# uebersprungen (projektspezifisches Wissen noetig).
leak_audit_stratify_cols <- character(0)
leak_audit_importance_path <- file.path(artifact_dir, "leak_audit_importance.csv")
leak_audit_determinism_path <- file.path(artifact_dir, "leak_audit_determinism.csv")
leak_audit_stratum_path <- file.path(artifact_dir, "leak_audit_within_stratum.csv")
leak_audit_decomposition_path <- file.path(artifact_dir, "leak_audit_decomposition.csv")

baseline_results_path <- file.path(artifact_dir, "baseline_results.csv")
baseline_benchmark_path <- file.path(artifact_dir, "baseline_benchmark.rds")
boosting_results_path <- file.path(artifact_dir, "boosting_results.csv")
boosting_benchmark_path <- file.path(artifact_dir, "boosting_benchmark.rds")
lightgbm_baseline_iterations <- 200
catboost_baseline_iterations <- 200
lightgbm_tuning_evals <- 20
lightgbm_tuning_search_results_path <- file.path(artifact_dir, "lightgbm_tuning_search_results.csv")
lightgbm_tuning_final_results_path <- file.path(artifact_dir, "lightgbm_tuning_final_results.csv")
lightgbm_tuning_instance_path <- file.path(artifact_dir, "lightgbm_tuning_instance.rds")
lightgbm_selection_path <- file.path(artifact_dir, "lightgbm_selection.rds")
ensemble_results_path <- file.path(artifact_dir, "ensemble_results.csv")
ensemble_oof_predictions_path <- file.path(artifact_dir, "ensemble_oof_predictions.csv")
ensemble_lightgbm_weight <- 0.60
full_holdout_results_path <- file.path(artifact_dir, "full_holdout_confirmation_results.csv")
full_holdout_predictions_path <- file.path(artifact_dir, "full_holdout_confirmation_predictions.csv")
# Speichert die trainierten LightGBM/CatBoost-Learner-Objekte (nicht nur
# Vorhersagen) - noetig fuer 126_sanity_checks.R, das FRISCHE Vorhersagen auf
# perturbierten/verschobenen Daten braucht, kein erneutes Training.
full_holdout_models_path <- file.path(artifact_dir, "full_holdout_confirmation_models.rds")
segment_metric_cols <- character()
segment_metrics_path <- file.path(artifact_dir, "segment_metrics.csv")

# Split-Conformal Prediction Intervals (128_conformal_prediction_intervals.R,
# siehe conformal_prediction.R): retrofit-faehige, verteilungsfreie
# Prediction-Intervals auf einem bereits trainierten Punktvorhersage-Modell
# (kein erneutes Training), verifiziert an synthetischer Ground Truth
# (homo-/heteroskedastisch haelt Coverage, Distribution-Shift bricht sie
# sichtbar - siehe BACKLOG.md). Default NA -> uebersprungen, kein Eingriff
# in die bestehende Holdout-Bestaetigung.
# conformal_target_coverage: Ziel-Coverage (z.B. 0.90 fuer 90%), NA = aus.
# conformal_calib_ratio: Anteil des 120-Holdouts fuer die Kalibrierung
# (Rest = Coverage-Pruefmenge), muss disjunkt von der Eval-Menge sein.
# conformal_prediction_col: welche Spalte aus full_holdout_predictions_path
# kalibriert wird; NA = automatisch die beste (niedrigster RMSE) laut
# full_holdout_results_path.
conformal_target_coverage <- NA_real_
conformal_calib_ratio <- 0.5
conformal_prediction_col <- NA_character_
conformal_intervals_path <- file.path(artifact_dir, "conformal_prediction_intervals.csv")

# Modell-Sanity-Checks (126_sanity_checks.R, siehe sanity_checks.R und
# REFERENZ_MODEL_SANITY_CHECKS.md im Klassifikations-Template fuer den
# theoretischen Hintergrund - identisch uebernommen, aufgabentyp-
# unabhaengig). Bauen auf `full_holdout_models_path` auf (kein erneutes
# Training). Alle drei Listen default leer -> Skript uebersprungen.
#
# sanity_check_model: "lightgbm"/"catboost"/"blend"/NA (NA = automatisch das
# beste laut RMSE auf dem 120-Holdout).
sanity_check_model <- NA_character_

# Perturbation: numerische Spalten (MUESSEN dbl-typisiert sein, siehe
# TARGETS.md/PumpItUp-Erfahrung im Klassifikations-Template). warn_drop ist
# in Ziel-Einheiten (RMSE-Verschlechterung), projektabhaengig zu justieren.
perturbation_test_cols <- character(0)
perturbation_noise_sd_frac <- 0.05
perturbation_warn_drop <- 0.05

# Invarianz: Spalten ohne vermutete kausale Bedeutung fuer die Zielgroesse
# (Kandidaten-Check, keine endgueltige Aussage). Bei einer numerischen
# Response (Regression) ist die reine flip_rate bei einem grossen Boosting-
# Ensemble oft irrefuehrend hoch (schon EIN Baum, der die Spalte irgendwo
# nutzt, aendert die Vorhersage minimal) - warn_magnitude_threshold gated
# zusaetzlich auf die tatsaechliche Aenderungsgroesse (mean_abs_change, in
# Ziel-Einheiten). Bei kategorialer Response (Klassifikation) wird dieser
# Schwellwert ignoriert (mean_abs_change ist dort NA).
invariance_test_cols <- character(0)
invariance_warn_flip_rate <- 0.05
invariance_warn_magnitude_threshold <- 0.01

# Directional Expectation: wie im Klassifikations-Template, aber OHNE
# favorable_class (Regression hat keine Klassen - die rohe Vorhersage wird
# direkt beobachtet). Jede Spec: feature, type ("numeric"+delta oder
# "ordinal"+level_order), direction ("increasing"/"decreasing" - Vorhersage
# soll bei der Verschiebung nicht sinken/steigen).
directional_expectation_specs <- list()
directional_warn_violation_rate <- 0.30
directional_effect_threshold <- 0.05  # in Ziel-Einheiten, projektabhaengig
directional_warn_effect_share <- 0.05
sanity_check_results_path <- file.path(artifact_dir, "sanity_check_results.csv")

# Caruana-Greedy-Ensemble-Selection (127_ensemble_candidate_pool.R +
# 129_ensemble_selection.R, siehe REFERENZ_ENSEMBLE_SELECTION.md im
# Klassifikations-Template fuer den theoretischen Hintergrund - identisch
# uebernommen). An 2 unabhaengigen OpenML-Datensaetzen verifiziert
# (bank-marketing/electricity, Klassifikation) und gegen health_condition
# bestaetigt (Klassifikation) - Backport-Kriterium erfuellt.
# ensemble_pool_n_per_family: Kandidaten je Modellfamilie (Ranger/LightGBM/
# CatBoost). Reproduziert den `120`-Holdout-Split deterministisch (gleicher
# Seed) statt einen neuen Split zu ziehen.
ensemble_pool_n_per_family <- 8L
# `120`s vollstaendiger Trainingssplit ist hier ~414k Zeilen (viel groesser
# als das Klassifikations-Aequivalent, ~55k) - 24 Kandidaten darauf zu
# trainieren waere nicht mehr im Minutenbereich. ensemble_pool_train_sample_n
# begrenzt die Trainingsmenge NUR fuer den Kandidaten-Pool (Diversitaet
# zaehlt hier mehr als Volldaten-Praezision je Kandidat); Bewertung bleibt
# auf dem vollen Test-Split.
ensemble_pool_train_sample_n <- 50000L
ensemble_candidate_pool_path <- file.path(artifact_dir, "ensemble_candidate_pool.rds")
ensemble_selection_rounds <- 50L
ensemble_selection_valid_ratio <- 0.5
ensemble_selection_results_path <- file.path(artifact_dir, "ensemble_selection_results.csv")
# Eindeutige Kandidaten+Gewichte aus 129 (fuer 130_train_full_ensemble.R -
# retrainiert nur diese, nicht den gesamten Pool, auf vollen Daten).
ensemble_composition_path <- file.path(artifact_dir, "ensemble_composition.rds")
final_ensemble_full_path <- function(run_id) {
  file.path(artifact_dir, paste0("final_model_ensemble_full_", run_id, ".rds"))
}
submission_ensemble_path <- file.path(project_dir, "submission_ensemble.csv")

# `100_lightgbm_tuning.R` bestimmt die Variante per CV und speichert sie in
# `lightgbm_selection_path`; nachfolgende Schritte lesen dieses Artefakt.
submission_model_name <- "lightgbm_selected"
submission_model_algorithm <- "lightgbm"
submission_path <- file.path(project_dir, "submission.csv")
mean_submission_path <- file.path(project_dir, "submission_mean.csv")
prediction_bounds <- c(0, 1)
reference_submission_path <- NA_character_
submission_diff_check_path <- file.path(artifact_dir, "submission_diff_check.csv")

# Externe Quellen fuer Feature-Engineering bewusst klassifizieren. Werte:
# "allowed_input", "inspiration_only", "blocked_or_unclear".
external_source_policy <- data.frame(
  source = character(),
  policy = character(),
  notes = character(),
  stringsAsFactors = FALSE
)

final_model_full_path <- function(model_name, run_id) {
  file.path(artifact_dir, paste0("final_model_", model_name, "_full_", run_id, ".rds"))
}

# --- Exposure/Offset (Punkt 10 im BACKLOG.md, Kriterium erfuellt 2026-08-12) -
# Fuer Count-/Tweedie-Ziele mit einer Exposure-Spalte (Beobachtungsdauer,
# Zeit-am-Risiko o.ae.): NICHT als Feature, sondern als log-Offset -
# modelliert den Erwartungswert BEI GEGEBENER Exposure statt eine rohe Rate
# zu lernen. Verifiziert an 2 unabhaengigen Projekten (tweet/freMTPL2,
# dataCar/insuranceData - beide standalone in ML_Learning/, siehe
# BACKLOG.md Punkt 10 fuer Details/Zahlen).
#
# offset_col <- NULL (Default): kein Offset, `add_log_offset()` wird nicht
# aufgerufen - rueckwirkungsfrei fuer Projekte ohne Exposure-Spalte (wie
# road-accident-risk hier). Bei Bedarf in einem neuen Projekt auf den
# Spaltennamen setzen (z.B. "Exposure") UND `020_task.R` ruft dann
# `add_log_offset()` automatisch auf.
offset_col <- NULL

# Setzt eine log-Offset-Spalte als nativen mlr3-`offset`-col-role. Wirkt
# automatisch fuer jeden Learner mit "offset"-Property (regr.glm/
# regr.glmnet/regr.xgboost) bei Training UND Vorhersage - kein weiterer
# Eingriff in Benchmark-/Tuning-Skripte noetig, mlr3 nutzt den Offset
# automatisch, wo unterstuetzt.
#
# WICHTIGE GRENZE (verifiziert per Test, siehe BACKLOG.md Punkt 10):
# regr.lightgbm/regr.catboost haben KEINE offset-Property - mlr3 wirft in
# `benchmark()` nur eine WARNUNG ("Task hat offset, aber Learner
# unterstuetzt das nicht, wird ignoriert") und trainiert normal weiter,
# aber OHNE den Offset zu nutzen (kein Fehler, kein Leck, aber auch kein
# Nutzen). Ein LightGBM-Modell, das den Offset TATSAECHLICH nutzt, braucht
# die native `lightgbm`-API (`dtr$set_field("init_score", log(exposure))`,
# Predict `mu = exposure * response`) AUSSERHALB des normalen
# `mlr3::benchmark()`-Wegs dieses Templates - siehe `tweet/080_boosting_
# benchmark.R` fuer ein vollstaendiges Beispiel. Das dort demonstrierte
# Muster laesst sich nicht 1:1 generisch in dieses Template einbauen, ohne
# die einheitliche benchmark()-Abstraktion fuer alle anderen Learner
# aufzugeben - bewusst nicht erzwungen, hier nur dokumentiert.
add_log_offset <- function(task, offset_col_name) {
  offset_values <- task$data(cols = offset_col_name)[[offset_col_name]]
  log_offset_col <- paste0("log_", offset_col_name)

  offset_dt <- data.table(x = log(offset_values))
  setnames(offset_dt, "x", log_offset_col)

  task_with_offset <- task$clone(deep = TRUE)
  task_with_offset$cbind(offset_dt)
  task_with_offset$set_col_roles(log_offset_col, roles = "offset")
  # Rohe Exposure-Spalte aus den Features entfernen (nicht loeschen) - sonst
  # bliebe dieselbe Information doppelt im Modell: einmal als Offset, einmal
  # als normales Feature.
  task_with_offset$set_col_roles(offset_col_name, roles = character(0))

  stopifnot(!log_offset_col %in% task_with_offset$feature_names,
            !offset_col_name %in% task_with_offset$feature_names,
            identical(task_with_offset$col_roles$offset, log_offset_col))
  task_with_offset
}

algorithm_from_learner_id <- function(learner_id) {
  algorithms <- c("rpart", "ranger", "lightgbm", "catboost")
  matched <- algorithms[vapply(algorithms, function(algorithm) {
    grepl(paste0("regr\\.", algorithm), learner_id)
  }, logical(1))]

  if (length(matched) != 1) {
    stop("Algorithmus konnte nicht aus learner_id abgeleitet werden: ", learner_id)
  }

  matched
}
