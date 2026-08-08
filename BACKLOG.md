# Template-Backlog: unbestaetigte Kandidaten

Stand: 2026-07-23

Hier stehen Workflow-/Methoden-Bausteine, die in **einem** Projekt nuetzlich
waren, aber die Rueckfuehrungs-Regel noch **nicht** erfuellen. Sie bleiben
projekt-lokal, bis eine der Bedingungen erfuellt ist:

- **bestaetigt durch >= 2 Projekte**, ODER
- **nachweislich rueckwirkungsfrei** (No-op gegen das Template-Eigenprojekt
  regressionsgetestet).

Erst dann wandert ein Punkt aus diesem Backlog in den versionierten Workflow.
Was bereits im Template ist (Feature-Availability-Audit, Adversarial Validation,
Segmentmetriken, Submission-Diff-Check), steht in `WORKFLOW_GUARDS.md` und ist
default-inert (kein Eingriff in die bestehende Pipeline).

---

## Herkunft: Forecasting-/Shift-Projekt (GeoAI Drought, `AStepAheadOfdrought`)

Diese Kandidaten sind forecasting-/panelspezifisch und bisher nur an **einem**
Projekt belegt. Nicht pauschal fuer i.i.d.-Regression aktivieren.

1. **Zeitgeblocktes / rollierendes Resampling als zentrale API.**
   Statt `rsmp("cv")` fest verdrahtet: `make_resampling(task, purpose)` mit
   Strategien `cv` / `holdout` / `time_blocked`. OOF-Ensemble und Tuning muessen
   denselben instanziierten Split nutzen. → Groesster Baustein; braucht ein 2.
   zeitliches Projekt, bevor die API-Form feststeht.

2. **Zeitgeblockte Persistence-Baseline.** Bei Forecasting ist die No-Signal-
   Unterkante oft `y(t+1) = y(t)`, nicht der Mittelwert. Optionaler Baseline-Typ
   `persistence`, wenn eine Lag-/Current-Target-Spalte konfiguriert ist.

3. **Oracle- vs. feasible-Baseline trennen.** Eine Baseline, die im Test nicht
   immer verfuegbare Information nutzt (`oracle`), von einer exakt auf `Test.csv`
   berechenbaren (`feasible`) unterscheiden; Metriken nach Availability-Segmenten
   (`all` / `available` / `masked`) gruppieren.

4. **Validierungs-Maskierung aus Test-Verfuegbarkeit spiegeln.** Helper
   `apply_availability_profile()`: lernt Missingness aus den Test-Features und
   spiegelt sie in zeitgeblockte Validierungs-Folds, damit die lokale CV nicht
   zu optimistisch wird.

5. **Legal-history-Feature-Helper.** Generisch "letzter beobachteter Wert vor der
   aktuellen Zeile je Entity" (`last_known_*`, `months_since_known`,
   `current_or_last_known`), Maskierung respektierend, aktuelle Zeile nie im
   Feature. Nur fuer Forecasting/Paneldaten, nicht fuer i.i.d.-Regression.

## Herkunft: Workflow-Konventionen (allgemeiner, aber noch 1x belegt)

6. **Domain-Feature-Bloecke als benannte Experimente.** Jeder thematische Block
   immer gegen einen Refit der bisherigen Referenz auf **denselben** Folds; ohne
   diesen Refit-Vergleich ist der Effekt nicht interpretierbar.

7. **Segment-Blends vor Modellvielfalt.** Bei klar diagnostiziertem Segmentfehler
   zuerst einen Baseline-Blend nur auf dem Segment testen; Subsegmente pruefen
   (ein globaler Gewinn kann ein Subsegment verschlechtern). Seed-Ensembles
   separat diagnostizieren (Seed-Korrelation, RMSE gegen Einzelseed) statt
   pauschal Gewinn anzunehmen.

8. **Residualisierung nur als Hypothese, nicht als Default.** Residual-Modell
   gegen eine legale Baseline immer gegen das direkte Modell mit identischen
   Features messen; in einem Fall war Residualisierung nicht stabil besser
   (Negativergebnis).

9. **Test-Segmentbelegung vor segmentbezogener Submission pruefen.** Ergaenzung
   zum vorhandenen `158_check_submission_diff.R`: wenn ein Segment-Hebel im echten
   Test keine Zeile veraendert, automatisch als No-op kennzeichnen.

## Herkunft: Count/Tweedie-Projekt (tweet, French Motor freMTPL2)

Erstes Count-/Tweedie-Regressionsprojekt. Das Devianz-Modul ist bereits ins
Template gewandert (default-inert, No-op-Zweig — `deviance_measures.R`,
`WORKFLOW_GUARDS.md` Abschnitt 6). Die folgenden Bausteine greifen in bestehende
Skripte ein bzw. sind datensatzgeformt → bleiben 1-Projekt-Kandidaten, bis ein 2.
Count-/Tweedie-Projekt sie bestaetigt.

10. **Exposure als echter log-Offset — Verdrahtungs-Helfer.** Drei Wege, alle in
    tweet verifiziert: (a) nativer mlr3-`offset`-col-role
    (`task$set_col_roles(col, "offset")`) — von `regr.glm`/`regr.glmnet`/`regr.xgboost`
    bei Training UND Vorhersage genutzt, ueberlebt `po("encode")`; (b) LightGBM
    hat KEINE offset-Property → native API `dtr$set_field("init_score", log(exp))`,
    Predict `mu = exp * response`; (c) Tweedie-GLM braucht base-R
    `glm(family = statmod::tweedie(var.power=p, link.power=0))`, weil mlr3 `regr.glm`
    kein Family-Objekt akzeptiert. Greift in `020_task.R`/`030_baseline.R`/
    `080_boosting_benchmark.R` ein → erst als generischer `set_offset()`/init_score-
    Helfer backporten, wenn ein 2. Projekt die API-Form bestaetigt.

11. **Metrik-Angemessenheits-A/B.** Vier Praediktoren (near_zero / naive_mean /
    null_offset / full) auf RMSE/MAE **vs.** Devianz. Macht messbar, dass bei hoher
    Nullmasse RMSE/MAE ~0-Vorhersagen belohnen und Modelle kaum rangieren, die
    Devianz aber klar trennt (tweet: RMSE-Spanne +0,4 % vs. Devianz +15497 %; das
    bessere Modell hatte sogar schlechteren RMSE). Generalisiert zu „ist mein Loss
    die richtige Metrik?" fuer jedes schiefe/nullmassige Ziel.

12. **Durable Befunde (als Doku-Notiz, kein Code):** (a) Offset-Wirkung ist
    modellklassenabhaengig — linearer GLM profitiert klar, flexibler Boost bei
    Poisson gar nicht und bei Tweedie sogar negativ (Ursache: niedriges Exposure-
    Terzil, multiplikative Rate-Korrektur verstaerkt Rauschen). (b) Referenz IMMER
    auf identischen Folds rechnen (ein Single-Split-GLM vs. 5-fold-Boost drehte das
    Ergebnis). (c) externer Sanity-Check via D² (skaleninvariant), nicht absolute
    Devianz (Rate+Gewichte vs. Offset liegen auf verschiedenen Skalen).

---

## Herkunft: Sensitivitaetstest Target-Leak-Audit (OpenML 42712 Bike-Sharing)

13. **Kumulative Top-k-Importance-Schwelle fuer `013_target_leak_audit.R`
    (Schritt 1)** - Anlass: Sensitivitaetstest am bekannten Bike-Sharing-Leak
    (`casual + registered == count` exakt bei 100% der Zeilen). Der Guard fand
    den Leak korrekt (`registered` 94.7% Gain-Share > Schwelle, Zerlegung
    RMSE 3.12 -> 32.50), liess aber `casual` (5.3%, unter der 50%-Einzel-
    schwelle) in der "ehrlichen" Zerlegung stehen - die berichteten 32.50 RMSE
    waren selbst noch ~20% zu optimistisch (voll ehrlich: 40.67). **Der Guard
    prueft nur Einzelfeature-Konzentration, keine gemeinsam wirkenden Leak-
    Paare/-Gruppen.** Idee: zusaetzlich pruefen, ob die kumulierte Gain-Share
    der Top-k-Features (k=2,3,...) eine Schwelle ueberschreitet, nicht nur ein
    einzelnes Feature. Bewusst NICHT sofort umgesetzt - Risiko, legitime,
    gemeinsam starke (aber nicht leakende) Feature-Gruppen faelschlich
    auszuschliessen; Schritt 5 (manuelles Urteil) faengt den Rest bereits ab,
    ein 10-facher RMSE-Sprung provoziert ohnehin weitere Pruefung. 1-Projekt-
    Kandidat, niedrige Prioritaet.

---

## Herkunft: ADR-Aufraeumung (2026-08-08)

14. **Zwei implizite Architekturentscheidungen als ADR-Kandidaten
    vorgemerkt, noch nicht umgesetzt**: (a) `targets`-Pipeline deckt bewusst
    nur den finalen Produktionspfad ab, die explorativen Skripte bleiben
    ausserhalb des Graphen - bisher nur in `README.md`-Prosa begruendet;
    (b) beide Templates (Klassifikation/Regression) halten ihr
    `experiments.db`-Schema bewusst identisch, um kuenftige Cross-Template-
    Analysen/-Merges zu ermoeglichen - ebenfalls nur Prosa. Beide erfuellen
    das Befoerderungs-Kriterium aus `adr/README.md` (echte Alternative +
    versehentlich umkehrbar), aber noch nicht zu eigenen ADR-Dateien
    ausgebaut - niedrige Prioritaet, keine akute Verwechslungsgefahr
    beobachtet.
15. **`merge_project_experiments.R` in diesem Repo war bis 2026-08-08 eine
    unangepasste Kopie der Klassifikations-Version** (falsches `target_db_path`,
    zeigte auf die Klassifikations-DB statt auf dieses Repo) - im selben Zug
    wie die Auto-Discovery-Uebernahme (siehe `adr/001-local-project-db-central-
    merge.md`) korrigiert und getestet. Als Lektion vorgemerkt: Datei-Kopien
    zwischen den Templates immer auf hartcodierte, nicht mitkopierte Pfade
    pruefen, nicht nur auf inhaltliche Anpassung.

---

## Aufnahme-Kriterium erfuellt? → hier abhaken und ins Template verschieben

| Kandidat | 2. Projekt / No-op-Beleg | Status |
|---|---|---|
| 1 zeitgeblocktes Resampling | – | offen |
| 2 Persistence-Baseline | – | offen |
| 3 oracle/feasible-Baseline | – | offen |
| 4 Availability-Spiegelung | – | offen |
| 5 legal-history-Features | – | offen |
| 6 benannte Feature-Bloecke | – | offen |
| 7 Segment-Blends | – | offen |
| 8 Residualisierung als Option | – | offen |
| 9 Segmentbelegung-Check | – | offen |
| 10 Exposure-Offset-Verdrahtung | tweet (1) | offen |
| 11 Metrik-Angemessenheits-A/B | tweet (1) | offen |
| 12 Durable Befunde (Doku) | tweet (1) | offen |
| 13 kumulative Top-k-Importance-Schwelle | openml-bike-sharing (1) | offen |
| 14 ADR-Kandidaten (targets-Scope, gemeinsames Schema) | – | offen |
| 15 Datei-Kopien auf hartcodierte Pfade pruefen (Lektion) | – | erledigt (Fix) |
