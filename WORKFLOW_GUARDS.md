# Workflow Guards

Stand: 2026-07-23

Diese Checks schuetzen das Regression-Template vor drei typischen Fehlern:

- lokale CV sieht besser aus als der echte Test.
- starke Features sind im Test nicht genauso verfuegbar wie im Train.
- eine neue Submission veraendert gar keine Predictions oder nur irrelevante Zeilen.

## 1. Feature Availability Audit

Skript: `012_feature_availability_audit.R`

Zweck:

- Train/Test-Spalten vergleichen.
- Missingness-Shift je Feature messen.
- Sentinel-Werte wie `-999` oder `9999` erkennen.
- externe Quellenklassifikation aus `external_source_policy` mitloggen.

Config:

```r
feature_availability_sentinel_values <- c(-999, -9999, 999, 9999)
external_source_policy <- data.frame(
  source = c("example external page"),
  policy = c("inspiration_only"),
  notes = c("May inspire features, not used as direct input")
)
```

Outputs:

- `_artifacts/feature_availability_summary.csv`
- `_artifacts/feature_availability_missingness.csv`
- `_artifacts/feature_availability_report.txt`

## 2. Adversarial Validation

Skript: `018_adversarial_validation.R`

Zweck:

Train und Test werden zu einer Klassifikationsaufgabe gemischt. Ein Modell versucht,
`train` vs. `test` anhand der gemeinsamen Features zu erkennen.

Interpretation:

| AUC | Bedeutung |
|---:|---|
| ca. 0.50 | Train/Test kaum unterscheidbar |
| ca. 0.60-0.70 | leichter Shift, genauer pruefen |
| > 0.70 | starker Shift, Validierung und Features kritisch ansehen |

`ess_ratio` zeigt, ob Propensity-Gewichte stabil waeren. Je kleiner der Wert, desto
weniger repraesentativ ist die lokale Validierung fuer den Test.

Config:

```r
adversarial_validation_sample_n <- 150000L
adversarial_validation_folds <- 3L
adversarial_exclude_cols <- c(id_col, target_col)
```

Outputs:

- `_artifacts/adversarial_validation_results.csv`
- `_artifacts/adversarial_validation_predictions.csv`

## 3. Segment Metrics

Skript: `125_segment_metrics.R`

Zweck:

Global gute Modelle koennen in wichtigen Untergruppen schlecht sein. Segmentmetriken
werten Holdout-Predictions je konfigurierter Spalte aus.

Config:

```r
segment_metric_cols <- c("weather", "road_type")
```

Voraussetzung:

`120_full_holdout_confirmation.R` muss vorher gelaufen sein, weil
`_artifacts/full_holdout_confirmation_predictions.csv` benoetigt wird.

Output:

- `_artifacts/segment_metrics.csv`

Hinweis:

Segmentspalten sind Diagnostik, keine neuen Features. Gute Segmente koennen zu
fairen Folgeexperimenten fuehren, z. B. Segment-Blend oder Segment-Postprocessing.

## 4. Submission Diff Check

Skript: `158_check_submission_diff.R`

Zweck:

Vor einer externen Einreichung pruefen, ob die neue Submission wirklich von einer
Referenzsubmission abweicht.

Config:

```r
reference_submission_path <- file.path(project_dir, "submission_previous.csv")
submission_path <- file.path(project_dir, "submission.csv")
```

Output:

- `_artifacts/submission_diff_check.csv`

Wichtige Kennzahlen:

- `n_different_predictions`
- `share_different_predictions`
- `max_abs_diff`
- `rmse_diff`

Wenn `n_different_predictions = 0`, ist die Submission ein No-op und sollte nicht
eingereicht werden.

## 6. Devianz-Measures (Count/Tweedie)

Modul: `deviance_measures.R` (Test: `test_deviance.R`)

Zweck:

mlr3 liefert ab Werk KEINE Devianz-Metrik (nur `regr.rmse/mae/mse/msle/rsq`).
Fuer Count-/Tweedie-Ziele (Schadenhaeufigkeit, Schadenlast, alles mit Nullmasse +
Rechtsschiefe) ist die mittlere Poisson-/Tweedie-Devianz die richtige Metrik, weil
sie die Verlustfunktion des Modells spiegelt und ~0-Vorhersagen korrekt bestraft,
statt sie wie RMSE/MAE zu belohnen.

Nutzung (opt-in, default-inert — nichts sourct das Modul automatisch):

```r
source(file.path(project_dir, "deviance_measures.R"))
register_deviance_measures(tweedie_power = 1.5)
msr("regr.poisson_deviance")
msr("regr.tweedie_deviance")   # power ueber register_deviance_measures() gesetzt
```

Verifiziert (`test_deviance.R`): Poisson == Poisson-GLM-Residualdevianz,
Tweedie(p=2) == Gamma-GLM, p=1 == Poisson, p=0 == MSE, Nullmasse endlich,
mlr3-Measure == Kernfunktion. `db_schema.sql`/`v_regr_model_results` fuehrt die
Spalten `poisson_deviance`/`tweedie_deviance` (additiv, NULL ohne diese Measures).

Wichtig: **`p_eval` fixieren.** Der Tweedie-Devianz-WERT haengt stark von der Potenz
`p` ab (in einem Fall ~11x Unterschied ueber p=1.1..1.9) — Modelle nur bei gleichem
`p_eval` vergleichen. Die Exposure-Offset-Verdrahtung (nativer col-role bzw.
LightGBM-`init_score`) ist noch projekt-lokal, siehe `BACKLOG.md`.

Theorie/Hintergrund/Literatur (Exponential-Dispersions-Modelle, Tweedie-Familie,
warum Devianz statt RMSE, Namensherkunft, Quellen): siehe `DEVIANCE_MEASURES.md`.

## 5. Empfohlene Reihenfolge

Fuer neue Projekte:

1. `010_eda.R`
2. `012_feature_availability_audit.R`
3. `015_signal_diagnostics.R`
4. `018_adversarial_validation.R`
5. Baselines und Boosting-Schritte.
6. `120_full_holdout_confirmation.R`
7. optional `125_segment_metrics.R`
8. `155_predict_submission.R`
9. optional `158_check_submission_diff.R`
10. `160_log_kaggle_submission.R`

## Nicht automatisieren

Diese Checks liefern Warnsignale, keine automatischen Entscheidungen. Wenn ein
Projekt zeitlich, raeumlich oder panelartig strukturiert ist, muss das Resampling
fachlich angepasst werden. Zufalls-CV ist dann oft nur ein erster technischer Test.
