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
- `_artifacts/univariate_drift_results.csv`

### Univariate Drift-Tests (Ergaenzung, `univariate_drift.R`)

Laeuft direkt im Anschluss an die Adversarial Validation, auf derselben
Stichprobe (`train_sample`/`test_sample`). Je Feature ein Kolmogorov-Smirnov-
Test (stetig) oder Chi-Quadrat-Test (kategorial), Benjamini-Hochberg-korrigiert
ueber alle Features. Ergaenzt die Adversarial-AUC um eine Pro-Feature-Diagnose:
die AUC sagt nur "insgesamt trennbar ja/nein/wie stark", die univariaten Tests
sagen WELCHE Features driften (mit Effektgroesse, KS-D bzw. Cramers V, je 0-1).

**Wichtig**: p-Wert und Effektgroesse zusammen lesen, nicht nur den p-Wert -
bei grossen Datensaetzen wird sonst auch eine praktisch irrelevante Abweichung
"signifikant" (im Klassifikations-Template z.B. ein Feature mit
p_adj_BH ~1e-297, aber Cramers V nur 0.037 - siehe dortiges `TARGETS.md`).

Zurueckgefuehrt aus dem Klassifikations-Template (Herkunft: "Introducing
MLOps", Treveil/Dataiku 2020, Kap. 7 - Domain-Classifier == unsere Adversarial
Validation, univariate Tests sind komplementaer). Verifiziert an 2 unabhaengigen
OpenML-Datensaetzen/3 Szenarien (echter Zeit-Drift, Zufalls-Kontrolle,
konstruierter Drift) im Klassifikations-Template, dort end-to-end getestet;
hier end-to-end gegen das Template-eigene Projekt (road-accident-risk)
regressionsgetestet (0/12 Features signifikant, konsistent mit Adversarial-
AUC ~0.499).

Config:

```r
univariate_drift_results_path <- file.path(artifact_dir, "univariate_drift_results.csv")
univariate_drift_alpha <- 0.05
```

Outputs:

- `_artifacts/univariate_drift_results.csv`

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

## 6. Panel-/Forecasting-Helfer (optional, opt-in, an 2 Projekten bestaetigt)

An GeoAI-Drought (`AStepAheadOfdrought`) UND Rossmann Store Sales bestaetigt
(siehe `REFERENZ_AVAILABILITY_MASKING.md` fuer Theorie/Zahlen). NUR fuer
zeitlich/panelartig strukturierte Projekte relevant - keine dieser Dateien
wird von einem bestehenden numerierten Skript automatisch geladen, ein neues
Projekt sourct sie bei Bedarf selbst:

- `time_blocked_resampling.R` - `make_resampling(task, purpose, date_col)`:
  `"time_blocked"` liefert Rolling-Origin-Folds (Trainingsblock strikt vor
  Validierungsblock) statt zufaelliger CV. Rossmann-Befund: zufaellige CV war
  optimistischer (RMSE 0.2545 vs. 0.2696, ~6% relativ) UND instabiler
  zwischen Folds.
- `oracle_feasible_baseline.R` - `oracle_feasible_comparison(...)`: vergleicht
  ein Modell MIT und OHNE train-only-Spalten (aus `012`s `train_only_cols`)
  auf demselben Split, optional nach Segmenten aufgeschluesselt. Rossmann-
  Befund: +55% relative RMSE-Verbesserung durch eine einzige Oracle-Spalte
  (`Customers`) - modellunabhaengig reproduziert (LightGBM UND Ranger).
- `availability_masking.R` - `apply_availability_profile()`/
  `mask_validation_by_availability_profile()`: spiegelt die aus `012`s
  Missingness-Delta gemessene Test-Verfuegbarkeitsluecke in die lokale
  Validierung, INKLUSIVE davon abgeleiteter Features (`derived_from`-
  Parameter - eine erste Version, die nur Rohspalten prueft, uebersah bei
  Rossmann eine echte 5.2%-Luecke in einem abgeleiteten Feature).
- `entity_history.R` - `months_since_known()`/`weeks_since_known()`/
  `current_or_last_known()`: generische "Zeit seit einem bekannten Ereignis"/
  "letzter bekannter Wert vor der aktuellen Zeile je Entity"-Helfer.
  Respektiert IMMER die Zeilen-Zukunft der Entity (kein Blick nach vorn).
- Optionale Persistence-Baseline in `030_baseline.R`
  (`baseline_persistence_entity_col`/`_date_col`/`_lag` in `000_config.R`,
  Default `NULL` -> uebersprungen). **Kein Default-Ersatz fuer den
  Mittelwert-Vergleich** - Rossmann zeigte einen echten GEGENbefund
  (Persistence 0.4263 RMSE schlechter als naive_mean 0.4165), immer BEIDE
  parallel berichten.
- **Regelmaessige hochfrequente Lags deckt `entity_history.R` NICHT ab**
  (nur "Zeit seit Ereignis" + Lag-1 via `current_or_last_known()`). Dafuer
  [`regular_lags_helper.R`](modules/regular_lags_helper.R) -
  `add_regular_lags(dt, entity, time, value, lags, roll_windows)`: baut
  `<value>_lag_<n>` (zeilenbasiert je Entity) und `<value>_roll_mean_
  <name>`/`<value>_roll_sd_<name>` (Rolling-Fenster `c(from, width)`
  Schritte zurueck, leckagefrei per Konstruktion). Rolling-SD vektorisiert
  ueber `sqrt(pmax(0, E[x^2] - E[x]^2))` statt `frollapply(..., sd)` (bei
  >100k Zeilen sonst zu langsam). An 2 unabhaengigen Panel-Projekten
  bestaetigt (`beijing-air-quality-panel`, `electricity-load-panel`,
  ADR-003 erfuellt, BACKLOG.md-Kandidat 25) - setzt eine REGELMAESSIGE
  Zeitachse je Entity voraus (kein Reindizieren bei Zeitluecken).
- **Residualisierung (Ziel = Rohwert minus einer groben Gruppen-
  Klimatologie, z.B. `entity x Monat x Stunde`-Mittel) ist KEIN
  Default-Hebel** - an 3 unabhaengigen Panel-Projekten geprueft, KEIN
  Fall zeigt einen verlaesslichen Vorteil (GeoAI-Drought: "nicht stabil
  besser"; `beijing-air-quality-panel`: Ratio 1,04, Held-out-Test sogar
  minimal BESSER mit Residualisierung, -0,36 RMSE; `electricity-load-
  panel`: im Mittel schlechter, aber Ratio 0,86 - ein einzelner Fold-
  Ausreisser dominiert die Streuung). **Korrektur 2026-09-11**: die
  urspruenglich hier dokumentierte "klar schlechter, Ratio 2,59"-Zahl
  fuer Beijing beruhte auf einem Bug (`merge()` ohne `sort = FALSE` beim
  Zusammenfuehren der Klimatologie-Werte mit den Fold-Zeilen - Default
  `sort = TRUE` sortiert nach den Merge-Spalten um, der danach extrahierte
  `clim`-Vektor war dadurch GEGEN `truth`/`pred` verschoben; betraf sogar
  das Residual-TRAININGSZIEL selbst, nicht nur die Auswertung). Nach dem
  Fix: kein Fall zeigt einen |Ratio|>2-Effekt in beide Richtungen -
  **Residualisierung hilft nachweislich nicht verlaesslich, ist aber
  auch nicht zuverlaessig schaedlich** (anders als vorher dokumentiert).
  Plausibler Grund fuer den ausbleibenden Nutzen bleibt: ein Boosting-
  Modell lernt eine gruppenabhaengige Baseline ohnehin selbst
  (Baumsplits auf den Gruppierungs-Features). Praktische Konsequenz
  unveraendert: ein Residual-Modell IMMER gegen das direkte Modell mit
  identischen Features/Folds messen, nie ungeprueft einbauen - UND bei
  jedem `merge()`, der einen Vektor fuer eine spaetere positionelle
  Verrechnung extrahiert, `sort = FALSE` nicht vergessen (sonst gilt
  dieselbe Falle wie hier).

## 8. Fallstricke beim Uebertragen des Templates auf ein neues Projekt

Nicht projekt-, sondern template-spezifisch - jedes neue Projekt kann
darauf stossen:

- **`030_baseline.R` bricht beim ERSTEN Lauf ab**, wenn
  `_artifacts/task_train_small.rds` noch nicht existiert:
  `030_baseline.R` sourct `040_preprocessing.R` (definiert
  `make_imputed_learner()`), laedt dann bei fehlendem Task-Artefakt
  `source("020_task.R")` nach - und `020_task.R` beginnt mit `rm(list =
  ls())`, was `make_imputed_learner()` wieder loescht. **Workaround**:
  `020_task.R` immer zuerst separat laufen lassen (so auch in Abschnitt 5
  / `WorkflowDescription.md` als Reihenfolge vorgesehen). Haertungs-
  kandidat: `020_task.R` ohne `rm(list = ls())`, oder `030` sourct `040`
  NACH dem Task-Build.

- **mlr3 "Learner ... received task with different column info (feature
  type or factor level ordering) during train and predict"** bei ZWEI
  separat gebauten Tasks (einer aus `train.csv`, einer aus `test.csv`):
  `fread` inferiert Spaltentypen je Datei unabhaengig (dieselbe Spalte
  wird `numeric` im Train, `integer` im Test, wenn die Testscheibe nur
  ganze Zahlen enthaelt - `012_feature_availability_audit.R` zeigt diese
  Typ-Deltas), und Faktor-Level-Mengen/-Reihenfolgen koennen abweichen.
  **Fix**: EINEN gemeinsamen Task aus `rbind(train, test)` bauen (mit
  `.is_test`-Flag), numerische Spalten explizit `as.numeric`, Charakter
  explizit `as.factor`, dann per `row_ids` trennen:
  `learner$train(task_all, row_ids = train_rows)` /
  `learner$predict(task_all, row_ids = test_rows)`. Nie zwei Tasks. (Das
  umgeht auch mlr3s Task-Hash-Check, wenn man eine EINMAL instanziierte
  Resampling-Struktur ueber feature-gefilterte Task-Klone
  wiederverwenden will - dann pro Fold `train_set(i)`/`test_set(i)`
  ziehen und manuell schleifen.)

  **Diese Falle ist trotz Dokumentation mehrfach wieder aufgetreten**
  (Beijing-Air-Quality-Panel: `026`, `029`, je einmal trotz bekannter
  Falle) - Lehre: dokumentiertes Wissen verhindert das Hineinlaufen nicht
  zuverlaessig, nur ein wiederverwendbarer Code-Baustein tut das. Deshalb
  gibt es jetzt [`combined_task_helper.R`](modules/combined_task_helper.R)
  (`build_combined_task_regr(train, test, feature_cols, target_col)`) -
  kapselt genau dieses Muster und gibt `task`/`train_rows`/`test_rows`/
  `train_task` zurueck. Neue Panel-/Forecasting-Projekte sollten diesen
  Helfer verwenden statt das Muster erneut von Hand zu schreiben.

- **`mlr3measures::rsq()` ist deprecated** - R^2 manuell:
  `1 - sum((truth - response)^2) / sum((truth - mean(truth))^2)`.

- **`data.table::merge()` sortiert standardmaessig (`sort = TRUE`) nach
  den Merge-Spalten um** - wird nur EIN Ergebnisvektor extrahiert
  (`merge(x, y, by = ...)$spalte`) und dieser dann POSITIONELL gegen
  einen anders geordneten Vektor verrechnet (z.B. `truth - clim_vektor`),
  entsteht eine stille Verschiebung - kein Fehler, nur falsche Werte.
  Gefunden in `beijing-air-quality-panel/031_residualization.R`: die
  Klimatologie-Werte wurden gegen Fold-Zeilen verrechnet, OHNE
  `sort = FALSE` - verfaelschte sogar das Residual-Trainingsziel selbst
  und liess ein eigentlich neutrales Ergebnis (Ratio 1,04) wie einen
  klaren Negativbefund (Ratio 2,59) aussehen (siehe Panel-Helfer-
  Abschnitt oben, Residualisierung). **Fix**: `sort = FALSE` setzen, oder
  gleich die GESAMTE Tabelle (inkl. der Vergleichsspalten wie `truth`)
  mergen statt nur einen Wert zu extrahieren - dann bleibt die
  Zuordnung immer konsistent, unabhaengig von der Merge-Reihenfolge.

- **LightGBM `objective="huber"`/`"quantile"` mit Default-`alpha`
  (0.9) UND einem auf L2 kalibrierten Iterationsbudget kann einen
  robusten Loss faelschlich "katastrophal schlecht" aussehen lassen.**
  Gefunden in `electricity-load-panel/034_robust_loss_functions.R`
  (BACKLOG.md Kandidat 30): bei einem Ziel mit Werten bis in die
  Tausende ist `alpha=0.9` praktisch IMMER unterschritten - Huber wird
  zu fast reinem linearem Loss mit KONSTANTEM (nicht fehlerproportionalem)
  Gradienten, das Modell braucht dadurch vielfach mehr Baeume, um
  grosse Fehler zu korrigieren, als L2s fehlerproportionaler Gradient
  (RMSE bei 250 Iterationen: 1738 statt 96 [!]; bei 3000 Iterationen:
  96, praktisch identisch - reine Konvergenzgeschwindigkeit, kein
  echter Qualitaetsunterschied). **Fix**: `alpha` auf die tatsaechliche
  Fehlergroessenordnung skalieren (z.B. aus einer schnellen L2-Referenz-
  RMSE ableiten, nicht den Default uebernehmen) UND alle Objectives mit
  demselben, ausreichend GROSSEN Iterationsbudget vergleichen - sonst
  ist der Vergleich nicht aussagekraeftig, egal in welche Richtung er
  ausfaellt.

## Nicht automatisieren

Diese Checks liefern Warnsignale, keine automatischen Entscheidungen. Wenn ein
Projekt zeitlich, raeumlich oder panelartig strukturiert ist, muss das Resampling
fachlich angepasst werden. Zufalls-CV ist dann oft nur ein erster technischer Test.
