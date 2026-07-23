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
