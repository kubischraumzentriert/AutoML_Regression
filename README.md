# AutoML Regression

Wiederverwendbarer `mlr3`-Workflow fuer tabellarische Regressionsaufgaben.
Das erste Referenzprojekt ist Kaggle Playground Series S5E10: Vorhersage von
`accident_risk` mit RMSE als Zielmetrik.

## Bootstrap-Workflow

1. `010_eda.R` prueft Datenstruktur, fehlende Werte und Zielvariable.
2. `020_task.R` erstellt einen 10%-`TaskRegr` aus den Rohfeatures.
3. `030_baseline.R` vergleicht rpart und Ranger (100 Baeume) per 5-facher CV.
4. `080_boosting_benchmark.R` vergleicht LightGBM und CatBoost (je 200 Iterationen).
5. `100_lightgbm_tuning.R` optimiert LightGBM per Bayesian Optimization und bestaetigt es per CV.
6. `110_oof_ensemble.R` prueft eine OOF-Mischung aus getuntem LightGBM und CatBoost.
7. `150_train_full_model.R` trainiert das gewaehlte Modell auf allen Daten.
8. `155_predict_submission.R` schreibt die Kaggle-Submission.

Alle Messungen werden in `_artifacts/experiments.db` im gleichen SQLite-Schema
wie das Klassifikations-Template gespeichert. `merge_project_experiments.R`
kann projektlokale Datenbanken spaeter in eine zentrale Vergleichsdatenbank
uebernehmen.

## Abgrenzung

Klassenspezifische Bausteine wie Stratifizierung, Klassengewichte, ROC/PR,
Threshold-Tuning und Konfusionsmatrizen gehoeren nicht in diesen Workflow.
Fuer Regression werden stattdessen RMSE, MAE, R-Quadrat und spaeter
Residualdiagnostik verwendet.

Der Ensemble-Schritt speichert die OOF-Metriken aller getesteten Gewichte
sowie die vollstaendigen OOF-Prognosen der beiden Basismodelle und der besten
Mischung in der SQLite-DB. Ein OOF-Gewinn ist nur ein Kandidat; bevor das
Ensemble fuer die Submission ausgewaehlt wird, wird er separat bestaetigt.
