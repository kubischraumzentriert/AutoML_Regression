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

## 7. Target-Leak-Audit

Skript: `013_target_leak_audit.R`

Zweck:

Eine zu gute Baseline auf einer schweren Aufgabe ist ein Warnsignal, kein Erfolg.
CV<->Leaderboard-Uebereinstimmung faengt einen Leak NICHT (das Artefakt steckt
meist auch in den Testdaten). Zurueckgefuehrt aus dem Klassifikations-Template
(dort an African-Credit-Scoring bestaetigt: eine naive F1-0.88-Baseline war ein
Ex-post-Leak, ehrlich F1 ~0.41, extern am Leaderboard fast exakt bestaetigt).
Laeuft bewusst auf **vollen** Daten (kein Subset), vier automatisierte Schritte:

1. Feature-Importance-Konzentration (LightGBM-Gain-Share eines einzelnen Features).
2. Determinismus - fuer stetige Ziele adaptiert: Zielstreuung (SD) INNERHALB einer
   Wertgruppe relativ zur Gesamtstreuung; nahe Null = das Feature pinnt den
   Zielwert nahezu fest.
3. Optional: Within-Stratum-Korrelation (`leak_audit_stratify_cols`) - bleibt ein
   verdaechtiges numerisches Feature auch innerhalb einer neutralen Kategorie
   stark mit dem Ziel korreliert?
4. Ehrlich-vs-aufgeblasen-Zerlegung: gepaarter Holdout, Zielmetrik mit vs. ohne
   die Verdaechtigen.

Schritt 5 (Verfuegbarkeit zur Entscheidungszeit) ist bewusst NICHT automatisiert -
das Skript listet nur die Verdaechtigen und die Leitfragen, das Urteil bleibt fachlich.

Config:

```r
leak_audit_importance_share_threshold <- 0.50
leak_audit_determinism_min_n <- 30
leak_audit_determinism_sd_ratio <- 0.10
leak_audit_stratify_cols <- character(0)  # optional
```

Outputs:

- `_artifacts/leak_audit_importance.csv`
- `_artifacts/leak_audit_determinism.csv`
- `_artifacts/leak_audit_within_stratum.csv` (nur falls `leak_audit_stratify_cols` gesetzt)
- `_artifacts/leak_audit_decomposition.csv` (nur falls Verdaechtige gefunden wurden)

Getestet gegen das Template-eigene Projekt (`playground-series-s5e10-road-
accident-risk`, volle 517755 Zeilen): kein Feature ueberschreitet 50%
Gain-Share (Top: curvature 36.4%, lighting 27.0%, speed_limit 25.3%), keine
Wert-Gruppe mit stark reduzierter Zielstreuung - Audit korrekt unauffaellig.

**Praeventiv portierte Haertung (2026-08-05)**: Das Klassifikations-Template
hat sein Pendant (`015_target_leak_audit.R`) auf zwei reale externe Projekte
angewandt (PumpItUp, geoai-aquaculture) und dabei zwei generische mlr3-Task-
Bugs gefunden, die die eigene (synthetische) Zielaufgabe nie ausloeste - beide
betreffen `as_task_regr()`/`as_task_classif()` gleichermassen, deshalb hier
vorsorglich mitgezogen (noch KEINE eigenstaendige Regressions-Cross-Projekt-
Bestaetigung, nur no-op-getestet gegen das Template-eigene Projekt):

- Datumsspalten (`Date`/`IDate`/`POSIXct`, z.B. aus `fread()`) liessen
  `as_task_regr()` abstuerzen - jetzt numerisch konvertiert (Tage/Sekunden
  seit Epoch) statt fallengelassen, ein Datum kann selbst leak-relevant sein.
- Rein kontinuierliche Feature-Saetze ohne jede Spalte
  `<= leak_audit_cardinality_max` liessen Schritt 2 abstuerzen
  (`rbindlist(list())` erzeugt eine spaltenlose Tabelle) - jetzt expliziter
  Kurzschluss mit Hinweistext statt Absturz.

**Sensitivitaetstest an einem ECHTEN, bekannten Leak (2026-08-05, OpenML 42712
"Bike_Sharing_Demand")**: Alle bisherigen Bestaetigungen zeigten nur, dass der
Guard bei sauberen Daten still bleibt (Spezifitaet) - nie, ob er einen echten
Leak FINDET (Sensitivitaet). Die UCI/Kaggle-Bike-Sharing-Rohdaten (OpenML
markiert `casual`/`registered` explizit als `ignore_attribute`) haben einen
verifizierten, deterministischen Leak: `casual + registered == count` exakt
bei 100% von 17379 Zeilen. Testprojekt: `C:\Users\HP\ML_Learning\
openml-bike-sharing-leak-test\` (nur `000_config.R` + `013_...R` + `train.csv`
noetig, kein DB-Logging).

**Ergebnis - der Guard fand ihn:**

| Variante | RMSE | R2 |
|---|---:|---:|
| Voll (mit `casual`+`registered`) | 3.12 | 0.9997 |
| Guard-Ergebnis (nur `registered` entfernt) | 32.50 | 0.9668 |
| Vollstaendig ehrlich (beide entfernt) | 40.67 | 0.9480 |

Schritt 1 flaggte `registered` (94.7% Gain-Share, weit ueber der 50%-Schwelle);
Schritt 4 zeigte den fast 10-fachen RMSE-Anstieg (3.12 -> 32.50) - ein klares,
korrektes Leak-Signal.

**Bekannte Grenze dabei entdeckt**: `casual` (5.3% Gain-Share) blieb UNTER der
Einzel-Schwelle und wurde nicht in die Zerlegung einbezogen - die vom Guard
berichteten "ehrlichen" 32.50 sind selbst noch ~20% zu optimistisch (wahre
Zahl 40.67). **Der Guard prueft nur Einzelfeature-Konzentration, keine
gemeinsam wirkenden Leak-Paare/-Gruppen.** Bewusst NICHT automatisch behoben
(z.B. per kumulativer Top-k-Schwelle) - das Risiko, legitime, gemeinsam starke
Features faelschlich auszuschliessen, waere real, und Schritt 5 (manuelles
Urteil) faengt den Rest ab: eine Warnung + ein 10-facher RMSE-Sprung provoziert
ohnehin weitere Pruefung, bei der ein Mensch `casual` findet.

## 5. Empfohlene Reihenfolge

Fuer neue Projekte:

1. `010_eda.R`
2. `013_target_leak_audit.R`
3. `012_feature_availability_audit.R`
4. `015_signal_diagnostics.R`
5. `018_adversarial_validation.R`
6. Baselines und Boosting-Schritte.
7. `120_full_holdout_confirmation.R`
8. optional `125_segment_metrics.R`
9. `155_predict_submission.R`
10. optional `158_check_submission_diff.R`
11. `160_log_kaggle_submission.R`

## Nicht automatisieren

Diese Checks liefern Warnsignale, keine automatischen Entscheidungen. Wenn ein
Projekt zeitlich, raeumlich oder panelartig strukturiert ist, muss das Resampling
fachlich angepasst werden. Zufalls-CV ist dann oft nur ein erster technischer Test.
