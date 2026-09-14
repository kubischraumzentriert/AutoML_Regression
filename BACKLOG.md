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

## Herkunft: Forecasting-/Shift-Projekt (GeoAI Drought, `AStepAheadOfdrought`) - ALLE 5 ERLEDIGT (2026-08-26)

1. **Zeitgeblocktes / rollierendes Resampling als zentrale API - ERLEDIGT,
   2. Bestaetigung (Rossmann Store Sales, 2026-08-26).** `make_resampling()`
   jetzt in `time_blocked_resampling.R` (Template-Root, opt-in, kein
   numeriertes Treiber-Skript aendert sich). Rossmann-Befund: zufaellige CV
   optimistischer als zeitgeblockt (RMSE 0.2545 vs. 0.2696, ~6% relativ) UND
   instabiler zwischen Folds - siehe `REFERENZ_AVAILABILITY_MASKING.md`
   Abschnitt 4.

2. **Zeitgeblockte Persistence-Baseline - ERLEDIGT, 2. Bestaetigung, ABER mit
   wichtigem GEGENbefund.** Optionaler Baseline-Typ in `030_baseline.R`
   (`baseline_persistence_entity_col`/`_date_col`/`_lag`, Default `NULL`,
   No-op gegen road-accident-risk regressionsgetestet). Rossmann zeigte: die
   Persistence-Baseline ist NICHT universell besser als der Mittelwert
   (RMSE 0.4263 vs. 0.4165) - haengt von der Regelmaessigkeit des
   Zeitmusters ab. Deshalb bewusst als OPTIONALER Zusatzbericht umgesetzt,
   NICHT als Ersatz/Default fuer die naive-Mean-Baseline. Siehe
   `REFERENZ_AVAILABILITY_MASKING.md` Abschnitt 5.

3. **Oracle- vs. feasible-Baseline trennen - ERLEDIGT, 2. Bestaetigung.**
   `oracle_feasible_comparison()` in `oracle_feasible_baseline.R`
   (Template-Root, baut auf `012_feature_availability_audit.R`s
   `train_only_cols` auf), inkl. Segment-Aufschluesselung. Rossmann-Befund:
   +55% relative RMSE-Verbesserung durch eine einzige Oracle-Spalte
   (`Customers`) - modellunabhaengig reproduziert (LightGBM im Prototyp,
   Ranger im Backport-Funktionstest). Siehe `REFERENZ_AVAILABILITY_
   MASKING.md` Abschnitt 3.

4. **Validierungs-Maskierung aus Test-Verfuegbarkeit spiegeln - ERLEDIGT,
   2. Bestaetigung, mit einer wichtigen Methodik-Lehre.** `apply_
   availability_profile()`/`mask_validation_by_availability_profile()` in
   `availability_masking.R`. Rossmann-Fund: eine erste Version, die nur
   ROHE Spalten prueft, uebersah eine echte 5.2%-Luecke in einem daraus
   ABGELEITETEN Feature - die Backport-Funktion nimmt daher einen expliziten
   `derived_from`-Parameter, der Rohspalten-Deltas auf abgeleitete Features
   uebertraegt. Siehe `REFERENZ_AVAILABILITY_MASKING.md` Abschnitt 1-2.

5. **Legal-history-Feature-Helper - ERLEDIGT, 2. Bestaetigung.**
   `months_since_known()`/`weeks_since_known()`/`current_or_last_known()` in
   `entity_history.R` (Template-Root). Rossmann-Verifikation: korrekter
   NA->0-Uebergang exakt am Ereignisdatum (Store 5, Wettbewerbseroeffnung
   2015-04-01), nie ein Blick in die eigene Zukunft der Entity. Siehe
   `ML_Learning/rossmann-store-sales-forecasting/README.md`.

   **Neues, eigenstaendiges Referenzdokument**: `REFERENZ_AVAILABILITY_
   MASKING.md` haelt die Theorie hinter allen 5 Punkten fest (Missingness
   als eigene Verteilungseigenschaft, Beobachtbarkeits-Shift als
   Covariate-Shift-Spezialfall) - bisher fehlte diese Erklaerungsebene,
   `WORKFLOW_GUARDS.md` deckte nur das WAS/WIE ab, nicht das WARUM.

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

10. **Exposure als echter log-Offset — Verdrahtungs-Helfer. ERLEDIGT,
    Backport abgeschlossen (2026-08-12).** Drei Wege,
    zuerst in `tweet` verifiziert: (a) nativer mlr3-`offset`-col-role
    (`task$set_col_roles(col, "offset")`) — von `regr.glm`/`regr.glmnet`/`regr.xgboost`
    bei Training UND Vorhersage genutzt, ueberlebt `po("encode")`; (b) LightGBM
    hat KEINE offset-Property → native API `dtr$set_field("init_score", log(exp))`,
    Predict `mu = exp * response`; (c) Tweedie-GLM braucht base-R
    `glm(family = statmod::tweedie(var.power=p, link.power=0))`, weil mlr3 `regr.glm`
    kein Family-Objekt akzeptiert. **2. unabhaengiges Projekt**:
    `ML_Learning/dataCar-exposure-offset-test/` (Standalone, kein Git) -
    `dataCar` aus dem CRAN-Paket `insuranceData` (Australian Private Auto
    2004/05, 67.856 Zeilen; NICHT auf OpenML gefunden trotz gruendlicher
    Suche, aber eine echte unabhaengige Quelle). Beide Wege (a) und (b)
    bestaetigt: Ratio-Test fuer den mlr3-Offset-Weg exakt 2.0 (identisch zu
    tweet), LightGBM-`init_score`-Mechanismus funktioniert. **Neuer Befund,
    ANDERS als bei tweet**: der Offset wirkt hier bei LightGBM messbar
    (Poisson-Devianz 0.3751 mit vs. 0.3944 ohne Offset, deutlich ausserhalb
    der gepoolten Fold-SD ~0.0062 - bei tweet war der Effekt nicht messbar,
    Δ0.0015 « Fold-SD 0.008). Der Nutzen des Offsets ist also
    datensatzabhaengig - ein zusaetzliches Argument, ihn als generische,
    immer verfuegbare Option ins Template aufzunehmen statt projektspezifisch
    zu entscheiden. **Backport umgesetzt**: `add_log_offset(task,
    offset_col_name)` in `000_config.R` (mit Unit-Test verifiziert: rohe
    Exposure-Spalte wird korrekt aus den Features entfernt, kein
    Informations-Duplikat; Ratio-Test exakt 2.0). Neuer Config-Wert
    `offset_col <- NULL` (Default, rueckwirkungsfrei fuer Projekte ohne
    Exposure - road-accident-risk laeuft unveraendert, verifiziert per
    `020_task.R`-Rerun). `020_task.R` ruft den Helfer automatisch auf, wenn
    ein neues Projekt `offset_col` setzt. **Bewusste Grenze dokumentiert**:
    der Helfer wirkt automatisch fuer jeden Learner mit `offset`-Property
    (regr.glm/regr.glmnet/regr.xgboost); fuer regr.lightgbm/regr.catboost
    (keine offset-Property) wirft `mlr3::benchmark()` nur eine Warnung und
    ignoriert den Offset (verifiziert: kein Fehler, kein Leck, aber auch
    kein Nutzen) - ein LightGBM-Modell, das den Offset tatsaechlich nutzt,
    braucht die native `lightgbm`-API ausserhalb der Template-`benchmark()`-
    Abstraktion (siehe `tweet/080_boosting_benchmark.R`), bewusst NICHT
    generisch erzwungen.

11. **Metrik-Angemessenheits-A/B - als generalisierte Lehre dokumentiert
    (2026-08-12, siehe `DEVIANCE_MEASURES.md` Abschnitt 1).** Vier
    Praediktoren (near_zero / naive_mean / null_offset / full) auf RMSE/MAE
    **vs.** Devianz. Macht messbar, dass bei hoher Nullmasse RMSE/MAE
    ~0-Vorhersagen belohnen und Modelle kaum rangieren, die Devianz aber
    klar trennt (tweet: RMSE-Spanne +0,4 % vs. Devianz +15497 %; das
    bessere Modell hatte sogar schlechteren RMSE). Generalisiert zu „ist
    mein Loss die richtige Metrik?" fuer jedes schiefe/nullmassige Ziel -
    bewusst KEIN Code-Helfer (der konkrete Test haengt zu stark vom
    jeweiligen Loss ab), der Denkansatz selbst ist aber jetzt permanent in
    `DEVIANCE_MEASURES.md` festgehalten statt nur hier in ephemerer
    Backlog-Prosa. Weiterhin 1-Projekt-Kandidat fuer einen echten Code-
    Backport (kein zweiter Datensatz noetig, da kein Code geplant ist).

12. **Durable Befunde - uebertragen in `DEVIANCE_MEASURES.md` Abschnitt 7
    (2026-08-12), ERLEDIGT.** (a) Offset-Wirkung ist modellklassenabhaengig
    — linearer GLM profitiert klar, flexibler Boost bei Poisson kaum und
    bei Tweedie sogar negativ (Terzil-Rauschen) - UND datensatzabhaengig
    (dataCar-Gegenprobe: half LightGBM dort ~5 % Devianz). (b) Referenz
    IMMER auf identischen Folds rechnen. (c) externer Sanity-Check via D²,
    nicht absolute Devianz. Plus ein neuer vierter Punkt aus der Ensemble-
    Selection-Session: eine aggregierte Metrik-Verbesserung ist nicht
    automatisch eine Verbesserung fuer jede Teilpopulation - vor jedem
    Vertrauen in eine Gesamtzahl bei einem schiefen Ziel nach Teilgruppen
    aufschluesseln.

---

## Herkunft: Sensitivitaetstest Target-Leak-Audit (OpenML 42712 Bike-Sharing)

13. **Kumulative Top-k-Importance-Schwelle fuer `013_target_leak_audit.R`
    (Schritt 1) - ERLEDIGT, umgesetzt und verifiziert (2026-08-12).** Anlass:
    Sensitivitaetstest am bekannten Bike-Sharing-Leak (`casual + registered
    == count` exakt bei 100% der Zeilen). Der Guard fand den Leak korrekt
    (`registered` 94.7% Gain-Share > Schwelle, Zerlegung RMSE 3.12 -> 32.50),
    liess aber `casual` (5.3%, unter der 50%-Einzelschwelle) in der
    "ehrlichen" Zerlegung stehen - die berichteten 32.50 RMSE waren selbst
    noch ~20% zu optimistisch (voll ehrlich: 40.67). Der Guard pruefte nur
    Einzelfeature-Konzentration, keine gemeinsam wirkenden Leak-Paare/-Gruppen.

    **Umsetzung**: neuer kumulativer Check in Schritt 1, der die fuehrenden
    `leak_audit_cumulative_max_k` Features darauf prueft, ob sie ZUSAMMEN
    ueber `leak_audit_cumulative_share_threshold` (Default 0.98 - bewusst
    HOCH, nicht 0.80, siehe unten) der Gain-Importance tragen.
    **Kritische Design-Entscheidung, per Test korrigiert**: der Check laeuft
    NUR, wenn Schritt 1 bereits mindestens einen Einzelverdaechtigen
    gefunden hat (`suspects_importance` nicht leer) - er ERWEITERT einen
    bestehenden Verdacht, statt einen neuen aus einer sauberen Verteilung zu
    erzeugen. Ohne diese Bedingung (erste Implementierung, direkt widerlegt):
    road-accident-risk (dieses Repos eigenes Referenzprojekt) hat 3 legitime
    Features (curvature/lighting/speed_limit), die zusammen 88% der
    Importance tragen, keins einzeln ueber 50% - ohne die Bedingung waeren
    diese faelschlich als Leak-Verdacht geflaggt worden (genau das im
    urspruenglichen Backlog-Eintrag befuerchtete Risiko, empirisch
    bestaetigt). Mit der Bedingung: road-accident-risk bleibt sauber (kein
    Einzelverdaechtiger -> Check uebersprungen), bike-sharing findet
    `casual` korrekt als Leak-Partner (`registered`+`casual` = 100.0% >
    98%), die Zerlegungs-RMSE landet exakt bei **40.6715** - der zuvor nur
    manuell erreichbare "voll ehrlich"-Wert.

    Config-Erweiterung in `000_config.R`: `leak_audit_cumulative_share_
    threshold <- 0.98`, `leak_audit_cumulative_max_k <- 5L`. Verifiziert an
    2 Faellen (road-accident-risk: kein Falsch-Alarm; bike-sharing-Leak-Test:
    korrekter Fund) - beide im selben Repo, daher weiterhin technisch
    1-Projekt-Kandidat fuer die BACKPORT-Regel, aber die Design-Entscheidung
    selbst ist bereits gegen einen echten False-Positive-Fall gehaertet.

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

## Herkunft: Cross-Template-Port aus dem Klassifikations-Template (2026-08-21)

23. **Korrelierte Feature-Cluster (Schritt 1b) fuer `013_target_leak_audit.R`
    - PORTIERT UND VERIFIZIERT.** Anlass (Klassifikations-Seite):
    `lending-club-leak-test` zeigte einen massiven Leak (BAcc 0.9983 voll
    vs. 0.5317 ehrlich), den der Guard komplett uebersah, weil 10
    Post-Outcome-Felder zusammen nur ~31% Gain-Importance trugen (keins
    einzeln ueber 30%, die kumulative Top-k-Erweiterung betrachtet nur die
    FUEHRENDEN Gain-Features und greift bei Redundanz nicht). Neuer
    Mechanismus: numerische Features nach Korrelation clustern, groessten
    Cluster (nach summierter Gain-Importance) per Retraining testen, nur
    bei substanziellem Score-Effekt (`leak_audit_cluster_drop_threshold`,
    hier metrikrichtungs-agnostisch ueber `abs()` statt BAcc-spezifisch
    hoeher-ist-besser) als Verdacht flaggen. Kostenkontrolle: hoechstens 1
    zusaetzliches Retraining, nur bei Vorfilter-Trigger (Cluster-Summe >
    `leak_audit_advisory_share_threshold`, hier neu eingefuehrt - gab es auf
    der Regressionsseite bisher nicht).

    **Bekannte Grenze (aus der Klassifikations-Seite mitgebracht)**: der
    Check loest den Lending-Club-Extremfall selbst NICHT vollstaendig
    (informatives Signal, aber unter der Warnschwelle - bei extremer
    Redundanz ueber viele Felder vermischt eine niedrige Korrelations-
    schwelle legitime Features, eine hohe fragmentiert die Gruppe). Eine
    getestete Alternative (iterative Einzelfeature-Entfernung) scheiterte
    noch deutlicher und war viel teurer - nicht portiert. Trotzdem
    behalten: echte, wenn auch unvollstaendige Verbesserung, bei sauberen
    Projekten praktisch kostenlos.

    **Regressionsgetestet gegen das Template-eigene Projekt** (`road-
    accident-risk`, die bekannte 3-legitime-Features-88%-Spezifitaets-
    kontrolle): Schritt 1/2/4/5 byte-identisch zu den vorherigen Zahlen
    (curvature 36.4% + lighting 27.0% + speed_limit 25.3% = 88.0%), Schritt
    1b bleibt korrekt still (kein Cluster mit |r|>=0.5 gefunden) - echter
    No-op. Positive Bestaetigung stammt vom Klassifikations-Template
    (synthetisch UND real, siehe dessen TARGETS.md) - kein eigener
    Regressions-Positivfall gebaut, da der Mechanismus (Korrelations-
    Clustering + Retraining-Zerlegung) task-typ-unabhaengig ist und die
    No-op-Regressionstestung hier die verbleibende Restunsicherheit
    (Uebertragungsfehler beim Portieren) abdeckt.

---

## Herkunft: Multi-Layer-Stacking-Test (2026-08-25) - NICHT uebernommen

24. **Mehrschichten-Stacking (AutoGluon-Idee) auf `accident_risk` getestet
    - NEGATIV, wie auf der Klassifikations-Seite.** `multilayer_stack_test.R`
    (Root-Skript, baut auf dem bestehenden `127_ensemble_candidate_pool.R`-
    Pool auf, kein neues Basis-Training): 3-Wege-Split, Layer-1 (glmnet/
    ranger/lightgbm) lernt aus den rohen Basis-Vorhersagen, Layer-2 (glmnet)
    lernt NUR aus den Layer-1-Vorhersagen, RMSE minimieren statt BAcc/AUC
    maximieren. Ergebnis: `greedy_ensemble` 0.05615 < `best_single` 0.05624
    < `equal_blend` 0.05690 < `multilayer_stack` 0.05693 < `single_layer_
    stack` 0.05703 - Greedy Ensemble Selection gewinnt klar, beide Stacking-
    Varianten liegen dahinter. War eine von 4 Projektbestaetigungen fuer
    dieselbe Frage im Klassifikations-Template (health_condition/s6e6/s6e8 +
    dieses Projekt, siehe dessen `TARGETS.md` fuer die volle Tabelle/
    Herleitung) - dieses Projekt lieferte die einzige Regressions-Bestaetigung
    und bestaetigte dieselbe Richtung wie 3 der 4 Klassifikationslaeufe:
    Mehrschichten schlaegt einlagiges Stacking (0.05693 < 0.05703), aber
    beides bleibt hinter dem bestehenden Greedy-Ensemble zurueck. **Nicht ins
    Template zurueckgefuehrt** - dieselbe Begruendung wie klassifikationsseitig
    (korrelierte Baumkandidaten limitieren den Nutzen jeder Kombinations-
    methode). Frage gilt als beantwortet, nicht als "noch offen".

---

## Herkunft: Beijing-Air-Quality-Panel-Projekt (2026-09-11)

25. **Kandidat 6 (benannte Domain-Feature-Bloecke, Refit auf denselben
    Folds) - Disziplin am 2. Panel-Projekt bestaetigt, kein Modul-Backport
    noetig.** `beijing-air-quality-panel/028_feature_blocks.R`: 6 benannte
    Bloecke (`station`/`calendar`/`meteo`/`lag`/`rolling`/gelaggter
    Schadstoff-Block), kumulativ hinzugefuegt UND leave-one-block-out, beides
    auf DENSELBEN einmal instanziierten zeitgeblockten Folds (manuelle
    Fold-Schleife statt `resample()`, umgeht mlr3s Task-Hash-Check bei
    feature-gefilterten Klonen). Paarweiser Delta je Fold, `|Mittel/SD| >
    ~2` als Schwelle fuer "Effekt klar ueber dem Fold-Rauschen".

    Ergebnis: nur der Meteorologie-Block hat einen klaren Effekt (Ratio
    -3,37, RMSE 91,7 -> 61,2). Der Lag-Block ist GRENZWERTIG (Ratio -1,51,
    unter der Schwelle). Rolling-Features und der gelaggte Schadstoff-Block
    sind praktisch wirkungslos (Ratios nahe 0). **Das bestaetigt genau den
    Kandidat-6-Mechanismus**: ein naiver Vergleich gegen Zahlen aus getrennt
    gesplitteten Laeufen haette den grenzwertigen Lag-Effekt leicht als
    "eindeutig" und den Rolling-/Schadstoff-Nulleffekt leicht als kleinen
    echten Gewinn fehlinterpretiert - beides waere gewoehnliches
    Fold-Rauschen gewesen. Der paarweise Vergleich auf identischen Folds
    macht den Unterschied sichtbar.

    Kandidat 6 beschreibt eine METHODIK (Disziplin), kein Template-Modul -
    "erledigt" heisst hier: die Methodik hat sich an einem zweiten,
    unabhaengigen Panel-Projekt (nach GeoAI-Drought) bewaehrt, nicht dass
    Code zurueckgefuehrt wurde. Volle Zahlen/Tabelle:
    `ML_Learning/beijing-air-quality-panel/README.md` Abschnitt "Kandidat 6".

26. **Kandidat 7 (Segment-Blends vor Modellvielfalt) - NEGATIVERGEBNIS am
    Beijing-Projekt.** `029_segment_blend.R`: Segmentdiagnose per OOF ueber
    dieselben zeitgeblockten Folds (Klimatologie `station x month x hour`
    NUR aus den Fold-Trainingsdaten) findet `month == 12` (Dezember) klar
    als schwaechstes Segment (OOF-RMSE 88,08 vs. global 58,83). Ein
    Blend-Gewicht-Grid (Modell vs. Klimatologie, nur auf dem Segment) zeigt
    aber: RMSE steigt MONOTON mit dem Klimatologie-Gewicht - bestes Gewicht
    ist w=0, die Klimatologie hilft nie, nicht einmal in kleiner Dosis.
    Subsegment-Check (Station x Dezember) dadurch trivial (`delta=0`
    ueberall). Bestaetigung auf dem Held-out-Test rechnerisch ein No-op
    (w=0), explizit ausgewiesen statt nur behauptet.

    Grund (plausibel): die station-monatliche Klimatologie ist zu grob fuer
    Dezember (mischt milde und extreme Heizsaison-/Inversions-Episoden ueber
    alle Jahre) - das Modell (mit `lag_24h` + Meteorologie) ist bereits
    naeher an der aktuellen Situation als ein grober historischer
    Durchschnitt. **Kein Backport** - Negativergebnis analog zu Rossmanns
    Persistence-Gegenbefund (Kandidat 2), dokumentiert statt verworfen.
    Volle Zahlen: `ML_Learning/beijing-air-quality-panel/README.md`
    Abschnitt "Kandidat 7".

27. **Kandidat 8 (Residualisierung nur als Hypothese) - KLARES
    NEGATIVERGEBNIS am Beijing-Projekt.** `031_residualization.R`: direktes
    Modell (`pm25` als Ziel) vs. Residual-Modell (`pm25 - clim(station,
    month, hour)` als Ziel, Klimatologie zurueckaddiert), identisches
    Featureset, identische 5 zeitgeblockte Folds, paarweiser Delta je Fold.
    Residualisierung ist in ALLEN 5 Folds schlechter (Mittel +7,45 RMSE, SD
    2,88, Ratio **2,59** - klar ueber der |2|-Schwelle, gleiches Vorzeichen
    durchgehend). Held-out-Test bestaetigt dieselbe Richtung (+2,45 RMSE).

    Plausible Erklaerung: LightGBM lernt eine station-/monats-/
    stundenabhaengige Baseline bereits selbst (Baumsplits auf diesen
    kategorialen Features) UND kann dabei flexibel mit anderen Features
    (v.a. Lags) interagieren - eine vorab abgezogene, additive, aus groben
    Gruppenmitteln bestehende Klimatologie nimmt genau diese Interaktions-
    freiheit und fuegt Rauschen ein (kleine Gruppen). Konsistent mit
    Kandidat 7 (dieselbe Klimatologie half dort auch nicht als Blend).
    **Kein Backport** - Negativergebnis dokumentiert, Kandidat-8-Disziplin
    (immer gegen das direkte Modell auf identischen Folds messen, nie als
    Default) damit bestaetigt. Volle Zahlen:
    `ML_Learning/beijing-air-quality-panel/README.md` Abschnitt "Kandidat 8".

28. **Kandidat 9 (Segmentbelegungs-Check + Kompositionsdiagnose) - erledigt,
    nutzt das bereits bestehende `composition_reweighting.R`.**
    `032_composition_diagnosis.R`: (A) Segmentbelegungs-Check bestaetigt,
    dass das Kandidat-7-Zielsegment (`month == 12`) im echten Test 8852
    Zeilen (17,3 %) hat - kein verdeckter No-op wie bei Drought Phase 8.
    (B) `segment_composition_shift()` + `reweight_metric_by_test_
    composition()` auf die zeitgeblockte-CV-vs.-Test-Luecke angewendet:
    Total-Variation-Distance der Monatsverteilung CV-Testfolds vs. echter
    Test = 0,469 (deutlich auffaellig - CV-Folds streuen ueber alle 12
    Monate, der echte Test ist ausschliesslich Sept-Feb). Die
    test-komponierte Schaetzung (65,94) erklaert **126 %** der CV-Test-
    Luecke (CV-Praxis 56,09 -> echter Test 63,88) - die Luecke ist
    vollstaendig ein Kompositionseffekt, kein zusaetzlicher Werte-Shift.

    Kein neuer Backport noetig - das Modul existiert bereits (Kandidat 15
    der urspruenglichen 5-Projekt-Bestaetigung). Dieser Fund ist eine
    weitere, sechste Anwendung/Bestaetigung. Volle Zahlen:
    `ML_Learning/beijing-air-quality-panel/README.md` Abschnitt "Kandidat 9".

    **Damit sind alle 4 urspruenglich offenen Kandidaten (6-9) aus dem
    Beijing-Projekt abgearbeitet**: 1 Backport (8, Warnhinweis in
    `WORKFLOW_GUARDS.md`), 2 dokumentierte Negativergebnisse ohne
    Backport-Bedarf (7, und Kandidat 6 als bestaetigte Methodik-Disziplin),
    1 erfolgreiche Anwendung eines bereits bestehenden Moduls (9).

---

## Aufnahme-Kriterium erfuellt? → hier abhaken und ins Template verschieben

| Kandidat | 2. Projekt / No-op-Beleg | Status |
|---|---|---|
| 1 zeitgeblocktes Resampling | GeoAI-Drought (1) + Rossmann (1) | erledigt (`time_blocked_resampling.R`) |
| 2 Persistence-Baseline | GeoAI-Drought (1) + Rossmann (Gegenprobe) | erledigt, opt-in (`030_baseline.R`), kein Default |
| 3 oracle/feasible-Baseline | GeoAI-Drought (1) + Rossmann (1) | erledigt (`oracle_feasible_baseline.R`) |
| 4 Availability-Spiegelung | GeoAI-Drought (1) + Rossmann (1) | erledigt (`availability_masking.R`) |
| 5 legal-history-Features | GeoAI-Drought (1) + Rossmann (1) | erledigt (`entity_history.R`) |
| 6 benannte Feature-Bloecke | `beijing-air-quality-panel` (1, `028_feature_blocks.R`, 24h-Horizont) | erledigt (Disziplin bestaetigt, kein Modul - siehe unten) |
| 7 Segment-Blends | `beijing-air-quality-panel` (1, `029_segment_blend.R`) | erledigt (Negativergebnis dokumentiert - siehe unten) |
| 8 Residualisierung als Option | GeoAI-Drought (1, "nicht stabil besser") + `beijing-air-quality-panel` (1, Ratio 1,04 nach Bugfix) + `electricity-load-panel` (1, Ratio 0,86) | erledigt (2026-09-11 korrigiert) - urspruenglich als "klar schlechter, Ratio 2,59" dokumentiert, beruhte auf einem `merge()`-`sort=FALSE`-Bug (siehe `WORKFLOW_GUARDS.md` #8); nach Fix an KEINEM der 3 Projekte ein verlaesslicher Effekt in beide Richtungen - Kernaussage bleibt "kein Default-Hebel, immer messen", nur die "klar schlechter"-Formulierung war falsch |
| 9 Segmentbelegung-Check | `beijing-air-quality-panel` (1, `032_composition_diagnosis.R`) | erledigt - siehe unten, nutzt bereits vorhandenes `composition_reweighting.R` |
| 10 Exposure-Offset-Verdrahtung | tweet (1) + dataCar (1) | erledigt (Backport in `000_config.R`/`020_task.R`) |
| 11 Metrik-Angemessenheits-A/B | tweet (1) | erledigt (Doku, kein Code geplant) |
| 12 Durable Befunde (Doku) | tweet (1) + dataCar (Gegenprobe) | erledigt |
| 13 kumulative Top-k-Importance-Schwelle | openml-bike-sharing (1) + road-accident-risk (Gegenprobe) | erledigt |
| 14 ADR-Kandidaten (targets-Scope, gemeinsames Schema) | beide Repos (ADR 005/006) | erledigt |
| 15 Datei-Kopien auf hartcodierte Pfade pruefen (Lektion) | – | erledigt (Fix) |
| 16 Caruana-Greedy-Ensemble-Selection | bestaetigt in Klassifikation (2) + hier (road-accident-risk) | erledigt (Punkt 22) |
| 17 Meta-Learning-Warmstart aus zentraler DB | Standalone (2, siehe Punkt 17) | geprueft, negativ, nicht weiterverfolgt |
| 18 Successive Halving/Hyperband fuers Tuning | Standalone (2, siehe Punkt 18) | geprueft, negativ, nicht weiterverfolgt |
| 19 Univariate Drift-Tests (`univariate_drift.R`) | Klassifikation (2) + hier (eigener Regressionstest) | erledigt |
| 23 Korrelierte Feature-Cluster (Leak-Audit Schritt 1b) | Klassifikation (synthetisch+real) + hier (No-op road-accident-risk) | erledigt |
| 24 Label-freie CV-LB-Kompositionsdiagnose (`composition_reweighting.R`) | 5 Projekte (Drought/Rossmann/geoai + PumpItUp/Richter als Gegenproben), ADR-003 klar erfuellt | erledigt (2026-09-10, identisch zum Klassifikations-Template, `test_composition_reweighting.R`) |
| 25 `add_regular_lags()` - regelmaessige hochfrequente Lag-/Rolling-Features je Entity | `electricity-load-panel` (1, nativ) + `beijing-air-quality-panel` (1, rueckwirkend auf den Helfer umgestellt) | erledigt (2026-09-11), ADR-003 erfuellt - `regular_lags_helper.R`, 7 synthetische Checks gruen (`test_regular_lags_helper.R`), Beijing-Retrofit per `026`/`029`-Referenzlauf bestaetigt (RMSE-Unterschied <0,2, innerhalb der bestehenden LightGBM-Run-zu-Run-Streuung) |
| 26 `combined_task_helper.R` - EIN gemeinsamer Task aus Train+Test statt zwei getrennter Tasks | `beijing-air-quality-panel` (Falle 3x aufgetreten trotz Dokumentation: `026`, `029` zweimal) + `electricity-load-panel` (2. Projekt, von Anfang an nativ verwendet statt nachtraeglich umgestellt) | erledigt (2026-09-11) - Falle war seit Kandidat 8 nur als Prosa in `WORKFLOW_GUARDS.md` #8 dokumentiert, verhinderte das erneute Hineinlaufen aber NICHT; jetzt als Code-Baustein `build_combined_task_regr()` zurueckgefuehrt, `test_combined_task_helper.R` gruen (5 Checks) |
| 27 Missing-Data-Mechanismus-Audit (MCAR/MAR/MNAR) - ist Fehlen informativ statt naiv median-/mode-zu-imputieren? | Klassifikation+Regression (Modul, 24/20 synthetische Checks je Template) + `beijing-air-quality-panel` (1 reales Projekt, inkl. Verfeinerung) | erledigt (2026-09-14) - `missingness_mechanism_audit.R` in beiden Templates (identisch, baut auf `univariate_drift.R` auf). Optionaler `min_effect_size`-Schwellenwert ergaenzt (KS-D/Cramers V zusaetzlich zur Signifikanz) nach realem Reibungsfund (bei n=360k war fast jede Spalte "signifikant"); erneuter Beijing-Lauf mit `min_effect_size=0.1` differenziert klar zwischen 7 Spalten mit echtem Ziel-Effekt (D>=0,14) und 3 Spalten mit nur statistischem, keinem praktisch relevanten Signal (CO/SO2/NO2, D<=0,065). Nur 1 reales Projekt bisher - fuer ADR-003 wuenschenswert, aber nicht blockierend, da Modul + Verfeinerung beide synthetisch UND real verifiziert sind |
| 28 Quantil-/Verteilungsregression als Alternative/Ergaenzung zu `conformal_prediction.R` | `electricity-load-panel` (1, `033_quantile_vs_conformal_intervals.R`, extreme Heteroskedastizitaet) | erledigt (2026-09-14) - neues `quantile_regression.R` (`regr.lightgbm` mit `objective="quantile"`, 8 synthetische Checks inkl. Heteroskedastizitaets-Fall). Neues Template-Skript `132_quantile_prediction_intervals.R` (Ergaenzung zu `128`). Reale Bestaetigung eindeutig: Conformals konstante Marge ueberdeckt kleine Kunden massiv (100% statt 90%) UND unterdeckt grosse Kunden drastisch (33,4% statt 90%, Faktor >400 Lastunterschied), Quantilregression haelt die Coverage pro Kunde durchgehend nah am Ziel. Nur 1 Projekt (nicht ADR-003-reif fuer eine "immer besser"-Aussage), aber Modul+Skript sind eigenstaendig nutzbar, kein Backport-Gate noetig (additive Ergaenzung, kein Ersatz) |
| 29 Negative Stacking-Gewichte (JOSS-Kandidat #8, `stacks`-Mechanik) - 2. unabhaengiger Test | Klassifikation (1, s6e9 `163_stacking_negative_weights.R`, 2x Nullbefund - 24 + 25 Kandidaten, jeweils 0 negative Koeffizienten gewaehlt) | offen (2026-09-14) - bisher nur 1 Projekt (n=1, negativ), braucht ein 2. Projekt mit grossem/redundantem Ensemble-Kandidatenpool (`127_ensemble_candidate_pool.R`) fuer ADR-003-Reife; hier in der Regression noch nie getestet |
| 30 Robuste Loss-Funktionen bei extremen Ziel-Ausreissern (Huber/Quantil statt reinem RMSE) | keins (0) | offen (2026-09-14) - `electricity-load-panel` als guter Testfall (Kundenmittel 16 bis 6669 kW, Faktor >400 Streuung); Vergleich `regr.lightgbm` mit `objective="huber"`/`"quantile"` vs. Default-RMSE auf identischen Folds |
