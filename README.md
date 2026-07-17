# AutoML Regression

Wiederverwendbarer `mlr3`-Workflow fuer tabellarische Regressionsaufgaben.
Das erste Referenzprojekt ist Kaggle Playground Series S5E10: Vorhersage von
`accident_risk` mit RMSE als Zielmetrik.

## Bootstrap-Workflow

1. `010_eda.R` prueft Datenstruktur, fehlende Werte und Zielvariable.
2. `015_signal_diagnostics.R` vergleicht die CV-Mittelwertreferenz mit dem Feature-Signal.
3. `020_task.R` erstellt einen 10%-`TaskRegr` aus den Rohfeatures.
4. `030_baseline.R` vergleicht rpart und Ranger (100 Baeume) per 5-facher CV.
5. `080_boosting_benchmark.R` vergleicht LightGBM und CatBoost (je 200 Iterationen).
6. `100_lightgbm_tuning.R` optimiert LightGBM per Bayesian Optimization, vergleicht es mit dem Standard-LightGBM per CV und speichert die bessere Variante.
7. `110_oof_ensemble.R` prueft eine OOF-Mischung aus der zuvor gewaehlten LightGBM-Variante und CatBoost.
8. `120_full_holdout_confirmation.R` bestaetigt die zuvor gewaehlte LightGBM-Variante, CatBoost und den festen OOF-Blend auf allen Daten per separatem 80/20-Holdout.
9. `150_train_full_model.R` trainiert die zuvor gewaehlte LightGBM-Variante auf allen Daten.
10. `155_predict_submission.R` schreibt die Kaggle-Submission.
11. `165_mean_submission.R` erzeugt im No-Signal-Fall eine Mittelwert-Submission.
12. `160_log_kaggle_submission.R` protokolliert gemeldete Public-/Private-Scores fuer finale Modelle oder den Mittelwert in der SQLite-DB.

Aktueller Finalkandidat fuer S5E10 ist getuntes LightGBM: Es gewann die
unabhaengige Voll-Daten-Holdout-Bestaetigung gegen CatBoost und den OOF-Blend.

Alle Messungen werden in `_artifacts/experiments.db` im gleichen SQLite-Schema
wie das Klassifikations-Template gespeichert. `merge_project_experiments.R`
kann projektlokale Datenbanken spaeter in eine zentrale Vergleichsdatenbank
uebernehmen.

Die Tabellen, Beziehungen, Laufzeit-Semantik und Abfrage-Views sind in
[`DATABASE.md`](DATABASE.md) beschrieben.

## Signal-Gate und Stop-Regel

`015_signal_diagnostics.R` ist ein frueher Entscheidungscheck, kein Modell-
Ersatz. Wenn die CV-Mittelwertreferenz bereits auf dem Niveau von rpart,
Ranger und mindestens einem nichtlinearen Boosting-Modell liegt, ist kein
robustes nutzbares Feature-Signal nachgewiesen. In diesem Fall:

1. Mit `165_mean_submission.R` eine Mittelwert-Submission als externe
   Kalibrierung erzeugen; in `160_log_kaggle_submission.R`
   `submission_candidate <- "target_mean"` setzen und ihren Kaggle-Score in
   `submission_result` speichern.
2. Bei Uebereinstimmung von CV und Leaderboard weder Hyperparameter-Tuning
   noch Ensembles oder zusaetzliche Modellfamilien starten.
3. Erst mit zusaetzlichen, wettbewerbskonformen Informationen oder einer
   veraenderten Feature-Repraesentation erneut experimentieren.

Die Regel verhindert blindes Tuning, ist aber bewusst keine harte
Automatik: Ein auffaelliger Unterschied zwischen lokaler CV und Leaderboard
erfordert zuerst eine Pruefung von Split, Daten und Leakage.

Tuning-Suchen speichern die Laufzeit jeder Konfiguration mit ihren
Hyperparametern. Vor einem Folge-Lauf gibt `estimate_tuning_runtime()` eine
Median-/P90-Schaetzung aus den bereits gemessenen Konfigurationen aus.

## Abgrenzung

Klassenspezifische Bausteine wie Stratifizierung, Klassengewichte, ROC/PR,
Threshold-Tuning und Konfusionsmatrizen gehoeren nicht in diesen Workflow.
Fuer Regression werden stattdessen RMSE, MAE, R-Quadrat und spaeter
Residualdiagnostik verwendet.

Der Ensemble-Schritt speichert die OOF-Metriken aller getesteten Gewichte
sowie die vollstaendigen OOF-Prognosen der beiden Basismodelle und der besten
Mischung in der SQLite-DB. Ein OOF-Gewinn ist nur ein Kandidat; bevor das
Ensemble fuer die Submission ausgewaehlt wird, wird er separat bestaetigt.
`120_full_holdout_confirmation.R` ist diese Bestaetigung: Das zuvor bestimmte
Gewicht wird nicht erneut auf dem Holdout optimiert.
