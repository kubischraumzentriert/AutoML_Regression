# Experiment Database

`_artifacts/experiments.db` ist die projektlokale SQLite-Datenbank fuer
reproduzierbare Modellversuche. `db_connect()` legt sie bei Bedarf an und
fuehrt `db_schema.sql` idempotent aus. Alle fachlichen Schluessel sind UUIDs;
die `*_seq`-Spalten sind nur SQLite-interne, fortlaufende Primaerschluessel.

## Datenmodell

Die zentrale Kette lautet:

```text
project -> workflow -> run -> model_config -> hyperparam
                         |          |      -> prediction
                         |          +-----> submission_result
                         +-> resampling

model_config + resampling -> metric_result
```

| Tabelle | Zweck |
| --- | --- |
| `project` | Fachliches Projekt, z.B. eine Competition oder OpenML-Uebung. |
| `workflow` | Ausfuehrendes Skript innerhalb eines Projekts. |
| `run` | Konkrete Ausfuehrung mit Start-/Endzeit, Seed, Git-Commit und Notiz. |
| `run_config` | Zur Laufzeit verwendete, projektuebergreifende Einstellungen. |
| `model_config` | Ein Modellkandidat mit Algorithmus, Feature-Set, Preprocessing und Task. |
| `hyperparam` | Name-Wert-Paare einer `model_config`; auch Artefaktpfade und Trainingszeit werden hier abgelegt. |
| `resampling` | CV, Holdout oder Custom-Split, verknuepft mit dem ausfuehrenden Run. |
| `metric_result` | Aggregierte und optionale Fold-Metriken je Modell und Resampling. |
| `prediction` | Optionale zeilenweise Regressionsergebnisse; nur gezielt loggen, um die DB klein zu halten. |
| `submission_result` | Gemeldete externe Scores, z.B. Kaggle Public/Private, am konkreten Modell. |

`prediction_prob` ist eine klassifikationsspezifische Erweiterung und fuer
Regression nicht befuellt.

## Metriken und Laufzeiten

`metric_result` ist die einzige Quelle fuer lokale Leistungsmetriken:

- `mres_fold IS NULL`: aggregierte Metrik eines Resamplings.
- `mres_fold = 1, 2, ...`: Metrik des einzelnen CV-Folds.
- `mres_elapsed_seconds`: gemessene Laufzeit in Sekunden. Bei Benchmark-CV
  ist sie die Zeit des jeweiligen Modell-Benchmarks; bei MBO ist sie die
  Laufzeit genau einer Holdout-Konfiguration (`runtime_learners`).

MBO speichert jede getestete LightGBM-Konfiguration als eigene
`model_config`, ihre Parameter in `hyperparam` und die zugehoerige RMSE samt
Laufzeit in `metric_result`. Damit lassen sich Qualitaet und Laufzeit direkt
pro Parameterkombination vergleichen. `estimate_tuning_runtime()` verwendet
diese historischen Einzelzeiten und gibt vor einem Folge-Lauf eine Median-
und P90-Schaetzung aus. Die P90 ist eine konservative Obergrenze, keine
Garantie; bei noch fehlenden Messungen wird bewusst keine Scheinschaetzung
ausgegeben.

## Externe Ergebnisse

`submission_result` trennt externe Leaderboard-Ergebnisse von lokaler CV:

- `subm_public_score` und `subm_private_score` sind die vom Nutzer gemeldeten
  Plattformwerte.
- `subm_status` ist `submitted` oder `late_submission`.
- Der eindeutige Schluessel verhindert doppelte Eintraege fuer dieselbe
  Modell-/Plattform-/Status-/Metrik-Kombination; ein erneuter Lauf aktualisiert
  den vorhandenen Eintrag.

Eine Mittelwert-Kalibrierung wird als Algorithmus `target_mean` mit
`constant_prediction` in `hyperparam` gespeichert. Sie bleibt dadurch von
gelernten Modellen unterscheidbar.

## Views und Auswertung

`db_schema.sql` stellt lesbare Views bereit, insbesondere:

- `v_model_results`: aggregierte Modellmetriken mit Hyperparametern.
- `v_regression_predictions`: geloggte Regressionsergebnisse und Residuen.
- `v_submission_results`: externe Scores mit Projekt-, Run- und Modellkontext.

Die kanonische Abfrage fuer Vergleichstabellen ist `v_model_results`; die
normalisierten Basistabellen sollten fuer neue Skripte nur ueber die Helfer
in `db_logging.R` beschrieben werden.

## Betrieb

Die DB verwendet Foreign Keys, WAL und einen `busy_timeout` von 30 Sekunden.
Mehrere Leser sind damit unproblematisch; parallele Schreiber sollten dennoch
auf einzelne Skriptlaeufe beschraenkt bleiben. Projektlokale Datenbanken
koennen mit `merge_project_experiments.R` in eine zentrale Vergleichs-DB
uebernommen werden. Dabei werden Vorhersagen und Submission-Ergebnisse
bewusst nicht automatisch kopiert, um zentrale Datenbanken schlank zu halten.
