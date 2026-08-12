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

14. **Zwei implizite Architekturentscheidungen zu ADRs ausgebaut, ERLEDIGT
    (2026-08-12)**: (a) `targets`-Pipeline deckt bewusst nur den finalen
    Produktionspfad ab, die explorativen Skripte bleiben ausserhalb des
    Graphen (`adr/005-targets-covers-production-path-only.md`); (b) beide
    Templates (Klassifikation/Regression) halten ihr `experiments.db`-
    Schema bewusst identisch, um Cross-Template-Analysen/-Merges zu
    ermoeglichen - konkret bereits belegt: `tweet`s Poisson-/Tweedie-
    Projekte liegen dank identischem Schema klaglos in der zentralen
    Klassifikations-DB (`adr/006-identical-db-schema-across-templates.md`).
    Beide ADRs in BEIDEN Repos dupliziert (siehe `adr/README.md`).
15. **`merge_project_experiments.R` in diesem Repo war bis 2026-08-08 eine
    unangepasste Kopie der Klassifikations-Version** (falsches `target_db_path`,
    zeigte auf die Klassifikations-DB statt auf dieses Repo) - im selben Zug
    wie die Auto-Discovery-Uebernahme (siehe `adr/001-local-project-db-central-
    merge.md`) korrigiert und getestet. Als Lektion vorgemerkt: Datei-Kopien
    zwischen den Templates immer auf hartcodierte, nicht mitkopierte Pfade
    pruefen, nicht nur auf inhaltliche Anpassung.

---

## Herkunft: "Automated Machine Learning"-Buch (Hutter/Kotthoff/Vanschoren 2019)

16. **Caruana-Greedy-Ensemble-Selection - ERLEDIGT, 2 eigene
    Regressions-Bestaetigungen (2026-08-12).** Statt ein Einzelmodell zu
    waehlen oder wenige Modelle gleichzugewichten, einen Pool bereits
    trainierter Modelle per gieriger Vorwaertsauswahl (mit Wiederholung,
    Caruana et al. 2004, wie in Auto-sklearn) zu einem Ensemble
    kombinieren. Erst im Klassifikations-Template an zwei OpenML-
    Datensaetzen (bank-marketing, electricity) verifiziert, dann hierher
    portiert (`127_ensemble_candidate_pool.R`/`129_ensemble_selection.R`)
    und an ZWEI eigenen Projekten bestaetigt: **road-accident-risk** (RMSE,
    Greedy 0.0564 < Einzelmodell 0.0565 < Blend 0.0572) und **tweet**
    (Poisson-/Tweedie-Devianz + Exposure-Offset, Vollmodell-Deploy auf
    externem Holdout: Greedy D²=0.115/0.114 vs. Referenz-LightGBM
    D²=0.081/0.060 - siehe `ML_Learning/tweet/REFERENZ_ENSEMBLE_SELECTION_
    TWEEDIE.md` und `MLR3_Klassifikation/REFERENZ_ENSEMBLE_SELECTION.md`
    Abschnitt 4 fuer Details). Bestaetigt: Mechanismus ist metrik-/
    aufgabentyp-unabhaengig (RMSE UND Devianz, mit Exposure-Offset).
17. **Meta-Learning-Warmstart fuer Tuning aus der zentralen `experiments.db`
    - VERALTETER EINTRAG, bereits geprueft mit NEGATIVEM Ergebnis
    (2026-08-08/10), NICHT weiterverfolgt.** Auto-sklearn-Rezept sauber
    umgesetzt (Meta-Features, k-naechste Referenz-Datensaetze per
    L1-Distanz, deren beste LightGBM-Konfiguration als `tnr("mbo")`-
    Initialdesign injiziert) und fair getestet (Standalone-Skripte in
    `ML_Learning/openml-drift-detection-test/020_/021_meta_learning_
    warmstart_test.R`, Referenzpool aus 8 OpenML-Datensaetzen, Baseline vs.
    Warmstart mit EXAKT demselben Budget, 2 Zieldatensaetze, je 3 Seeds):
    kein messbarer Effekt (bank-marketing +0.0001 AUC, electricity +0.0002
    AUC, beides klar innerhalb der Seed-Streuung). Volle Details, Zahlen
    und Diagnose (Pool zu klein, LightGBM robust gegen Hyperparameterwahl,
    Budget/Dimensionalitaets-Regime ungeeignet) in
    `MLR3_Klassifikation/TARGETS.md` Zeile ~594-646. Referenzpool bleibt in
    der zentralen `experiments.db` als Projekt `meta-learning-reference-
    pool` erhalten fuer einen moeglichen groesseren Folgeversuch - aber
    nicht als naechster Schritt priorisiert.
18. **Successive Halving/Hyperband fuer `100_lightgbm_tuning.R` - VERALTETER
    EINTRAG, bereits geprueft mit NEGATIVEM/uneindeutigem Ergebnis
    (2026-08-10), NICHT weiterverfolgt.** Standalone-Skript
    (`ML_Learning/openml-drift-detection-test/030_successive_halving_
    test.R`, 16 Kandidaten, Budget-Stufen 25->400, exakt gleiches
    Gesamtbudget wie Baseline, 2 Datensaetze, 3 Seeds): gegensaetzliche
    Richtung an beiden Zieldatensaetzen (bank-marketing -0.0015,
    electricity +0.0025 TEST-AUC), beide Effekte winzig gegenueber der
    Seed-Streuung. Details in `MLR3_Klassifikation/TARGETS.md` Zeile
    ~647-666.

---

## Herkunft: "Introducing MLOps"-Buch (Treveil/Dataiku 2020) - ERLEDIGT

19. **Univariate Drift-Tests: geprueft, verifiziert UND ins Template
    zurueckgefuehrt (2026-08-08).** Kap. 7 des Buchs: Domain-Classifier
    (== unsere Adversarial Validation) und univariate statistische Tests
    (Kolmogorov-Smirnov je stetigem Feature, Chi-Quadrat je kategorialem
    Feature, Benjamini-Hochberg-korrigiert) sind komplementaer - die
    Adversarial-AUC sagt nur "insgesamt trennbar", die univariaten Tests
    sagen WELCHE Features driften, mit Effektgroesse. Im Klassifikations-
    Template an 2 unabhaengigen OpenML-Datensaetzen/3 Szenarien (echter
    Zeit-Drift, Zufalls-Kontrolle, konstruierter Drift) verifiziert -
    Zahlen und Details siehe dortiges `TARGETS.md`. Neues, generisches
    Modul `univariate_drift.R` (identisch in beide Templates uebernommen,
    aufgabentyp-unabhaengig - reine Statistik auf zwei Datensaetzen mit
    gleichen Spalten), eingebunden in `018_adversarial_validation.R`
    direkt nach dem bestehenden Ergebnis-Speichern-Block. Neue Config-
    Variablen `univariate_drift_results_path`/`univariate_drift_alpha` in
    `000_config.R`. End-to-end gegen das Template-eigene Projekt
    (road-accident-risk) regressionsgetestet: 0/12 Features signifikant,
    konsistent mit der unauffaelligen Adversarial-AUC (~0.499) - genau das
    erwartete Spezifitaets-Verhalten. Details siehe `WORKFLOW_GUARDS.md`.

---

## Herkunft: Literaturbewertung Traceability/Produktion-KI (`C:\Git\literatur`) - ERLEDIGT

20. **Conformal Prediction Intervals: prototypisiert, verifiziert UND ins
    Template eingebaut (2026-08-10).** Aus dem MLOps/Uncertainty-
    Quantification-Semiconductor-Paper (arXiv 2605.07752, siehe
    `C:\Git\literatur\bewertung.md`): Split-Conformal liefert verteilungsfreie
    Prediction-Intervals mit endlich-Stichproben-Coverage-Garantie, retrofit-
    faehig auf ein bereits trainiertes Punktvorhersage-Modell (kein
    erneutes Training). Neue Datei `conformal_prediction.R` (3 generische
    Funktionen: `split_conformal_calibrate()`, `split_conformal_predict_
    interval()`, `check_conformal_coverage()`), `128_conformal_prediction_
    intervals.R` (optional, `conformal_target_coverage` default `NA` ->
    uebersprungen, baut auf `120_full_holdout_confirmation.R` auf).
    **Ground-Truth-Verifikation** (synthetisch, analog zur Leak-Audit-
    Methodik): homoskedastisches Rauschen haelt Coverage (empirisch 0.884
    vs. Ziel 0.900), heteroskedastisches Rauschen haelt Coverage TROTZDEM
    (0.911 vs. 0.900 - Validitaet ist unabhaengig von Heteroskedastizitaet,
    nur die Intervallbreite waechst), ein simulierter Distribution-Shift
    zwischen Kalibrierungs- und Pruefmenge bricht die Garantie sichtbar
    (0.260 vs. 0.900 Ziel) - bestaetigt die theoretische Exchangeability-
    Voraussetzung. End-to-end gegen das Template-eigene Projekt
    (road-accident-risk) regressionsgetestet: empirische Coverage 0.901 bei
    Ziel 0.900 (n=51775), unauffaellig. Kein zweites Projekt noetig (anders
    als bei heuristischen Guards) - die Methode ist mathematisch
    verteilungsfrei-gueltig, nicht datensatzspezifisch zu bestaetigen.

21. **Huyen-Sanity-Checks (Perturbation/Invarianz/Directional Expectation):
    aus dem Klassifikations-Template uebertragen (2026-08-10).** Waren dort
    bereits an synthetischer Ground Truth + 2 realen Projekten (health_
    condition, drivendata-pump-it-up) bestaetigt (siehe dortiges TARGETS.md).
    `sanity_checks.R` wurde dabei aufgabentyp-unabhaengig generalisiert
    (`higher_is_better`-Flag fuer `run_perturbation_test()` statt impliziter
    BAcc-Annahme; `run_invariance_test()` erkennt jetzt numerische vs.
    kategoriale Response automatisch; neues `build_numeric_shift_fn()` mit
    Integer-Typ-Erhalt) und identisch in beide Templates uebernommen -
    Generalisierung an synthetischen Regressions-Beispielen nachverifiziert
    (RMSE-Drop korrekt vorzeichenrichtig, numerische Invarianz sauber
    getrennt: sauberes vs. leaky-lm-Modell 0.0 vs. 0.9996 flip_rate).
    **Voraussetzung geschaffen**: `120_full_holdout_confirmation.R` speicherte
    bisher nur Vorhersagen, keine Learner-Objekte - fuer frische Vorhersagen
    auf perturbierten Daten ergaenzt um `full_holdout_models_path`
    (Learner+Holdout-Featuredaten), additiv, bestehende Outputs unveraendert.
    Neues `126_sanity_checks.R` (optional, baut auf diesem Artefakt auf,
    kein erneutes Training). **Echter Befund beim Regressionstest gegen
    road-accident-risk**: Perturbation (`curvature`) unauffaellig (Drop
    0.0008). Invarianz (`public_road`) zeigte zunaechst eine irrefuehrend
    hohe flip_rate (0.499) bei winziger `mean_abs_change` (0.0009) - bei
    einem grossen Boosting-Ensemble reicht ein einziger Baum, der die Spalte
    irgendwo nutzt, fuer eine (belanglose) Aenderung. Neue Config
    `invariance_warn_magnitude_threshold` gated die Warnung zusaetzlich auf
    die Aenderungsgroesse (nur bei numerischer Response relevant, bei
    Klassifikation ignoriert). Directional (`num_reported_accidents` +1,
    `speed_limit` +10, beide "increasing"): reproduziert dasselbe Muster wie
    in der Klassifikation - Richtung im Mittel korrekt, aber
    `num_reported_accidents` zeigt 10.2% aller Zeilen mit substanzieller
    (>0.05) Verletzung (WARNUNG), `speed_limit` praktisch keine (0.01%,
    unauffaellig trotz 22.2% technischer violation_rate) - **dritte
    unabhaengige Bestaetigung** desselben Tree-Ensemble-Nichtmonotonie-
    Musters (nach health_condition und PumpItUp).

22. **Caruana Greedy Ensemble Selection: aus dem Klassifikations-Template
    uebertragen (2026-08-11).** Siehe dortiges `REFERENZ_ENSEMBLE_SELECTION.md`
    fuer den theoretischen Hintergrund (identisch, aufgabentyp-unabhaengig).
    Neues `127_ensemble_candidate_pool.R` reproduziert den `120`-Train/Test-
    Split DETERMINISTISCH (gleicher Seed) statt ein weiteres Artefakt
    einzufuehren - `120`s voller Trainingssplit ist hier ~414k Zeilen (viel
    groesser als das Klassifikations-Aequivalent, ~55k), daher trainiert der
    Pool nur auf einer Stichprobe (`ensemble_pool_train_sample_n`, Default
    50k) - Bewertung bleibt auf dem vollen Test-Split. Neues
    `129_ensemble_selection.R`: RMSE MINIMIEREN statt BAcc maximieren, sonst
    identischer Mechanismus (Selektions-/Bestaetigungs-Split). **Ergebnis
    gegen road-accident-risk (4. unabhaengige Bestaetigung nach bank-
    marketing/electricity/health_condition)**: bestes Einzelmodell
    (`catboost_23`) RMSE 0.0565, gleichgewichteter Blend (24) 0.0572
    (schlechter), **Greedy-Ensemble 0.0564** (50 Modelle, diesmal echte
    Familien-Diversitaet: CatBoost/LightGBM/Ranger alle vertreten, nicht wie
    bei health_condition von einer Familie dominiert). Config-Ergaenzung in
    `000_config.R` analog zum Klassifikations-Template.
    **Luecke geschlossen (2026-08-12)**: `129_ensemble_selection.R`
    speichert jetzt die eindeutigen Kandidaten+Gewichte
    (`ensemble_composition_path`, analog zum Klassifikations-Template).
    Neues `130_train_full_ensemble.R` retrainiert nur diese eindeutigen
    Kandidaten auf dem vollen Trainingsdatensatz (9 Mitglieder bei road-
    accident-risk: 3 CatBoost/4 LightGBM/2 Ranger, 77.6 Min. - die 2 Ranger-
    Modelle allein 17.9+56.5 Min., Boosting-Modelle unter 1 Min. je Stueck -
    deutliche Bestaetigung, dass Boosting-Modelle bei diesem Projekt viel
    guenstiger auf Volldaten skalieren als Ranger). Neues `131_predict_
    ensemble_submission.R` mittelt gewichtet, clippt mit `prediction_bounds`
    (wie `155`), schreibt `submission_ensemble.csv`. End-to-end verifiziert:
    172585 Zeilen (= test.csv), plausible Vorhersageverteilung. Anders als
    beim Klassifikations-Template gibt es hier kein Klassengewichtungs-
    Konzept - der dortige Gewichtungs-Bug (siehe dessen TARGETS.md) betrifft
    dieses Template nicht.

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
| 14 ADR-Kandidaten (targets-Scope, gemeinsames Schema) | beide Repos (ADR 005/006) | erledigt |
| 15 Datei-Kopien auf hartcodierte Pfade pruefen (Lektion) | – | erledigt (Fix) |
| 16 Caruana-Greedy-Ensemble-Selection | bestaetigt in Klassifikation (2) + hier (road-accident-risk) | erledigt (Punkt 22) |
| 17 Meta-Learning-Warmstart aus zentraler DB | Standalone (2, siehe Punkt 17) | geprueft, negativ, nicht weiterverfolgt |
| 18 Successive Halving/Hyperband fuers Tuning | Standalone (2, siehe Punkt 18) | geprueft, negativ, nicht weiterverfolgt |
| 19 Univariate Drift-Tests (`univariate_drift.R`) | Klassifikation (2) + hier (eigener Regressionstest) | erledigt |
