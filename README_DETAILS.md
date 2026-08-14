# AutoML Regression

Wiederverwendbarer `mlr3`-Workflow fuer tabellarische Regressionsaufgaben.
Das erste Referenzprojekt ist Kaggle Playground Series S5E10: Vorhersage von
`accident_risk` mit RMSE als Zielmetrik.

> **Einstieg / Kontext erfassen**: vor dem Deep-Dive in einzelne Skripte
> zuerst [`WorkflowDescription.md`](WorkflowDescription.md) ansehen - dort
> steht ein Mermaid-Diagramm mit dem kompletten Ablauf inkl. aller
> Entscheidungspunkte (Metrik-Typ, Signal-Gate, Adversarial-Shift, Tuning-/
> Ensemble-Entscheidungen, Neural-Gate) sowie die Bootstrap-Workflow-Liste,
> das Signal-Gate/Stop-Regel-Detail und die Abgrenzung zum Klassifikations-
> Template. Gilt auch fuer eine KI-Session, die hier den Kontext erfassen
> soll: das Diagramm ist der guenstigste Einstiegspunkt. Fuer automatisierte
> Agenten (Codex, Claude Code, etc.) siehe zusaetzlich
> [`AGENTS.md`](AGENTS.md) - u.a. die Pflicht, das Diagramm bei Aenderungen
> an der Ablauflogik mitzuziehen.

## Reproduzierbare Pipeline (`_targets.R`)

`tar_make()` fasst den **finalen Produktionspfad** (Volldaten-Task -> finales
Modell -> Submission, entspricht `150`/`155`) zu einem cachenden
Abhaengigkeitsgraphen zusammen und ersetzt das manuelle Nacheinander dieser
Schritte. Aendert sich `train.csv`, die Config oder die in `100_lightgbm_tuning.R`
getroffene LightGBM-Wahl (`_artifacts/lightgbm_selection.rds`), rechnet
`tar_make()` nur die betroffenen nachgelagerten Ziele neu. Die explorativen
Einzel-Experimente (`030`-`125`) bleiben bewusst ausserhalb des Graphen.

Entwurfsmuster gespiegelt vom Klassifikations-Template: der Graph deckt nur den
finalen Pfad ab und hat keinen DB-Seiteneffekt (DB-Logging bleibt in den
manuellen Skripten). Bewusster Unterschied: die Auswahl wird als **Datei-Eingang**
(`lightgbm_selection.rds`) gelesen, damit eine neue Tuning-Wahl den Graphen
korrekt invalidiert - nicht ueber einen DB-Lookup, der fuer einen reproduzier-
baren Graphen nicht sauber hashbar waere.

Alle Messungen werden in `_artifacts/experiments.db` im gleichen SQLite-Schema
wie das Klassifikations-Template gespeichert. `merge_project_experiments.R`
kann projektlokale Datenbanken spaeter in eine zentrale Vergleichsdatenbank
uebernehmen.

Die Tabellen, Beziehungen, Laufzeit-Semantik und Abfrage-Views sind in
[`DATABASE.md`](DATABASE.md) beschrieben.
Die neuen Schutzchecks sind in [`WORKFLOW_GUARDS.md`](WORKFLOW_GUARDS.md)
ausfuehrlicher dokumentiert.
Fuer neuronale Tabellenmodelle (FT-Transformer) als Ensemble-Diversitaet siehe
[`NEURAL_DEPLOY.md`](NEURAL_DEPLOY.md): R-only-Policy, wann sich ein neuronales
Modell lohnt, und der Python-GPU-Export-Workflow fuer Kaggle.
Fuer den theoretischen Hintergrund von `group_resampling.R` (i.i.d.-Annahme,
mlr3-Gruppen-Rolle, Permutationstest fuer Gruppen-Kandidaten) siehe
[`REFERENZ_GROUP_AWARE_CV.md`](REFERENZ_GROUP_AWARE_CV.md).

Die Bootstrap-Workflow-Liste, das Signal-Gate/Stop-Regel-Detail, die
optionalen Workflow-Sicherungen, das group-aware-Resampling-Modul und die
Abgrenzung zum Klassifikations-Template stehen jetzt in
[`WorkflowDescription.md`](WorkflowDescription.md).
