# modules/ - Übersicht

Nicht-nummerierte R-Dateien, die von den nummerierten Kernskripten im
Repo-Root per `source(file.path(project_dir, "modules", "X.R"))`
eingebunden werden, statt selbst Teil der laufenden Pipeline zu sein
(ADR-007-Äquivalent, siehe `MLR3_Classifikation/adr/007-flat-scripts-not-r-package.md`
- dieselbe Architekturentscheidung, im Regressions-Template nie als eigene
ADR dupliziert). Mehrere Dateien sind wortgleiche oder eng verwandte
Backports aus `MLR3_Classifikation/modules/` (siehe dortige
`modules/README.md` für die Klassifikationsseite).

Jede Datei trägt ihren eigenen ausführlichen Kopfkommentar (Herkunft,
Mechanismus, ADR-003-Bestätigungshistorie) - diese Übersicht ersetzt den
nicht, sondern hilft nur beim schnellen Einordnen.

## Trust-Layer / Diagnose

| Datei | Zweck | Genutzt von |
|---|---|---|
| `composition_reweighting.R` | Label-freie Diagnose, ob eine CV↔Test-/LB-Lücke ein reiner Kompositionseffekt ist | `test_composition_reweighting.R` |
| `univariate_drift.R` | Statistische Train-vs-Test-Drift-Tests je Spalte (Ergänzung zur Adversarial Validation) | `018_adversarial_validation.R`, `missingness_mechanism_audit.R`, `rolling_drift_diagnosis.R` |
| `missingness_mechanism_audit.R` | Ist Fehlen in einem Feature informativ (MCAR/MAR/MNAR-artig), statt naiv zu imputieren? | `test_missingness_mechanism_audit.R`; real angewendet in `ML_Learning/beijing-air-quality-panel`, `ML_Learning/openml-house-prices-regression` |
| `rolling_drift_diagnosis.R` | Concept-Drift über MEHRERE Zeitperioden statt nur Train-vs-Test | `test_rolling_drift_diagnosis.R` |
| `feature_importance_stability.R` | Ist die Gain-Importance-Rangfolge über Folds/Seeds stabil, oder Rauschen eines Einzellaufs? | `test_feature_importance_stability.R` |
| `sanity_checks.R` | Perturbations-/Invarianz-/Directional-Expectation-Checks (Huyen 2022) | `126_sanity_checks.R` |
| `paired_fold_comparison.R` | Generischer Helfer für "paired same-folds"-Vergleiche (jede Variante auf denselben Folds messen) | `test_paired_fold_comparison.R` |
| `group_resampling.R` | Group-aware Resampling für Aufgaben mit wiederholten Entitäten (Generalisierung auf NEUE Gruppen) | projektspezifisch (kein Default-Skript, opt-in) |

## Panel-/Forecasting-spezifisch (opt-in, nur bei Entity+Zeit-Daten)

Nur relevant für Projekte mit Panel-/Zeitreihenstruktur - kein Default-Skript
im Template selbst, direkt aus einem projekteigenen Skript aufgerufen.

| Datei | Zweck |
|---|---|
| `availability_masking.R` | Validierungs-Maskierung aus Test-Verfügbarkeit spiegeln (welche Spalten sind zum Vorhersagezeitpunkt wirklich bekannt) |
| `entity_history.R` | "Letzter bekannter Wert/Zeit seit einem bekannten Ereignis" je Entity (unregelmäßig, ein Ereignis pro Entity) |
| `regular_lags_helper.R` | Regelmäßige, hochfrequente Lag-/Rolling-Features je Entity (Ergänzung zu `entity_history.R` für regelmäßige statt unregelmäßige Historie) |
| `oracle_feasible_baseline.R` | Oracle- vs. Feasible-Baseline trennen, Metriken nach Availability-Segmenten gruppieren |
| `time_blocked_resampling.R` | Zeitgeblocktes/rollierendes Resampling als eigene Strategie neben `rsmp("cv")`/`rsmp("holdout")` |

## Prediction Intervals

| Datei | Zweck | Genutzt von |
|---|---|---|
| `conformal_prediction.R` | Split-Conformal Prediction Intervals (verteilungsfrei, endlich-Stichproben-gültige Coverage) auf einem bereits trainierten Punktmodell | `128_conformal_prediction_intervals.R` |
| `quantile_regression.R` | Pinball-Loss-Quantilregression als lokal-adaptive Alternative/Ergänzung zu Split-Conformal | `132_quantile_prediction_intervals.R` |

## Metriken & Infra

| Datei | Zweck | Genutzt von |
|---|---|---|
| `deviance_measures.R` | Poisson-/Tweedie-Devianz als mlr3-Measures (fehlt in mlr3 ab Werk, für Count-/Tweedie-Ziele die passende Verlustfunktion) | `test_deviance.R` |
| `combined_task_helper.R` | Baut EINEN gemeinsamen mlr3-Task aus separat eingelesenen Train-/Test-Daten (vermeidet "different column info"-Fehler durch getrennte Typinferenz je Datei) | `test_combined_task_helper.R` |
| `merge_project_experiments.R` | Konsolidiert projekteigene `experiments.db`-Dateien mehrerer lokaler Projekte in eine zentrale DB | manuell aufgerufen |

## Sonderfall: `multilayer_stack_test.R`

Kein wiederverwendbarer Baustein wie die übrigen Dateien hier, sondern ein
eigenständiges Evaluations-Skript (sourced direkt `000_config.R`, `rm(list=ls())`
am Anfang) - die 4. Bestätigung des Multi-Layer-Stacking-Tests, erste auf der
Regressionsseite. Liegt in `modules/` statt im Root, weil es kein Teil der
nummerierten Produktionspipeline ist (analog zu `MLR3_Classifikation/analysis/`).

## Siehe auch

- `MLR3_Classifikation/modules/README.md` - Klassifikationsseite, mit
  mehreren wortgleichen Backports zu dieser Liste.
- `adr/` - die einzige ADR-Verzeichnis-Entsprechung in diesem Template.
