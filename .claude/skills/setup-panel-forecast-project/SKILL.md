---
name: setup-panel-forecast-project
description: Setzt ein neues Panel-/Forecasting-Regressionsprojekt aus dem MLR3_Regression-Template auf (Entity x Zeit, zeitgeblockter Split) und fuehrt es durch die Diagnose- und Framing-Schritte. Nutzen, wenn der Nutzer ein neues OpenML-/Kaggle-/UCI-Zeitreihen-/Panel-Regressionsprojekt aufsetzen will ("setz das X-Projekt auf", "neues Forecasting-Projekt", "Panel-Datensatz mit dem Regression-Template"). Fuer generische Template-Fallen (mlr3 "different column info", 030-Ladeordnung) siehe stattdessen WORKFLOW_GUARDS.md Abschnitt 8 - die gelten fuer JEDES Projekt, nicht nur Panel/Forecast.
---

# Panel-/Forecasting-Regressionsprojekt aufsetzen

Wiederholbares Verfahren, bisher an EINEM Projekt gezogen
(`beijing-air-quality-panel`, 2026-09-10/11 - 2. Zeuge fuer die offenen
`MLR3_Regression`-BACKLOG-Kandidaten 6-9). Vorlaeufig, noch nicht an
einem zweiten Panel-Projekt gegengeprueft - beim naechsten Panel-Projekt
schaerfen/korrigieren. Fruehere Panel-Projekte als Referenz (aeltere,
nicht ueber diesen Skill entstandene Vorlaeufer): `AStepAheadOfdrought`,
`rossmann-store-sales-forecasting` (beide `ML_Learning`).

**Abgrenzung**: dieser Skill deckt nur das PANEL-/FORECASTING-SPEZIFISCHE
ab (Zeitachse, Entitaet, zeitgeblockter Split, Lag-Features). Generische
Fallen, die JEDES Projekt aus diesem Template treffen koennen (nicht nur
Panel/Forecast), stehen in `WORKFLOW_GUARDS.md` Abschnitt 8, nicht hier -
dort nachschlagen bei mlr3-Task-Fehlern oder einem abbrechenden
`030_baseline.R`.

## Wann anwenden

Ein neuer Datensatz mit **Entity x Zeit**-Struktur (dieselbe Entitaet in
vielen Zeilen ueber die Zeit) und **Regressionsziel** soll mit dem
`MLR3_Regression`-Template bearbeitet werden - typischerweise ein echter
Forecast (Zukunftszeitraum vorhersagen), nicht ein i.i.d.-Zufallssplit.

## Ablauf

### 1. `001_fetch.R`: Daten holen + zeitgeblockter Split

- Reproduzierbarer, idempotenter Download (erst laden/entpacken, wenn
  `train.csv` fehlt) - Rohdaten sind per `.gitignore` (`*.csv`/`*.zip`)
  ohnehin nicht versioniert.
- Panel zusammenfuegen, Kalender-Features ableiten (`year`/`month`/
  `day`/`hour`/`dow`/`is_weekend`), Zeilen ohne Zielwert entfernen,
  `setorder(entity, datetime)`, `id := .I`.
- **Split zeitgeblockt**: Test = ein echter, zusammenhaengender
  Zukunftszeitraum (bei den bisherigen Panel-Projekten ~6 Wochen bis
  6 Monate, ~10-15 % der Zeilen), NIE ein Zufallssplit.
- **`datetime` ist BEWUSST kein Modell-Feature** (absolute Zeit als
  Feature macht die Adversarial-Validation trivial, s.u.). Die
  zyklische Zeitinfo steckt in den Kalender-Features. `datetime` nur
  fuer den Split und `time_blocked_resampling.R`s `dt`-Parameter -> `id
  -> datetime` separat nach `_artifacts/time_index.csv`, NICHT in
  `train.csv`/`test.csv`.
- Lokal-only-Projekte (kein Kaggle/Zindi): `test.csv` DARF die echte
  Zielspalte tragen (ehrliches Scoring, kein Leaderboard) - im README
  vermerken.

### 2. `000_config.R` anpassen

Aus dem Template kopieren, dann zusaetzlich zu den Standard-Vars setzen:

- `entity_col <- "<entity>"`.
- `prediction_bounds <- c(0, Inf)` fuer nicht-negative Ziele
  (Default-Template ist `c(0, 1)`, fuer eine Wahrscheinlichkeit).
- `baseline_persistence_entity_col <- NULL` LASSEN, solange `datetime`
  kein Task-Feature ist (die Persistence-Baseline in `030_baseline.R`
  braucht die Datumsspalte IM Task). Regulaere Lag-Features kommen ueber
  ein eigenes `025_forecast_features.R` (s.u.).
- `segment_metric_cols <- c("<entity>", "<kategorie>", "month")` fuer
  `125_segment_metrics.R` (Kandidaten 7/9).
- Optional ein Schalter (z.B. `forecast_variant`), der `train_path`/
  `test_path` auf ein separates Forecast-Featureset umlenkt statt auf
  die Nowcast-Rohdaten.

### 3. Diagnose-Reihenfolge + Framing-Entscheidung

Basisreihenfolge wie `WORKFLOW_GUARDS.md` Abschnitt 5 - zwei
Panel-spezifische Interpretationen kommen dazu:

1. **`013_target_leak_audit.R`**: bei Panel-Daten mit gleichzeitig
   gemessenen Zusatzgroessen (andere Sensoren am selben Ort/zur selben
   Zeit) flaggt der Guard sie oft ueber Einzel- oder Cluster-Schwelle.
   **Schritt-5-Urteil**: ko-gemessene Features sind fuer einen
   *Nowcast* ("Sensor X ausgefallen, aus Nachbarsensoren schaetzen")
   legitim ex-ante, fuer einen *Forecast* ex-post/nicht bekannt. Framing-
   Entscheidung treffen und im README begruenden. Bei Forecast: raus,
   nur GELAGGT als benannter Block wieder zulaessig (Kandidat 6).
2. **`018_adversarial_validation.R`**: ein Adversarial-AUC nahe 1,0 auf
   einem zeitgeblockten Split ist **fast immer trivial** (`year`/`month`
   trennen per Konstruktion) - KEIN Covariate-Shift-Alarm wie bei einem
   echten Werte-Shift. Die inhaltliche Frage ist **welche Periode ist
   der Test** - eine einzelne Saison verschiebt die Zielverteilung dort
   systematisch. Das ist ein **Kompositionseffekt** -> zeitgeblockte CV
   + `composition_reweighting.R` nach der Perioden-Variable als
   Diagnose.

### 4. Forecast-Featureset + zeitgeblockte Referenz

- Regulaere Lag-/Rolling-Features je Entity bauen (`entity_history.R`
  deckt das NICHT ab, siehe `WORKFLOW_GUARDS.md` Abschnitt 7) - Lags
  ueber den KOMBINIERTEN Train+Test bauen und dann splitten, damit die
  ersten Test-Zeilen korrekt Train-Vergangenheit nutzen (kein Leck,
  Rueckblick auf bekannte Vergangenheit ist legitim).
- Referenz-Lauf: Modell unter zeitgeblockter CV vs. Zufalls-CV vs.
  echtem Held-out-Test, gegen Persistence-Baselines. Die zeitgeblockte
  CV liegt naeher am echten Test als die Zufalls-CV - je schwerer/
  kompositionsgetriebener die Aufgabe, desto groesser der Unterschied.
- **Horizont bewusst waehlen**: ein dominanter kurzer Lag (bei stark
  autokorrelierten Zielen, z.B. Sensordaten) macht die Aufgabe fast
  Persistenz - Modell und Baseline liegen dann kaum auseinander. Fuer
  echten Feature-Engineering-Spielraum (Kandidaten 6-9) eine Variante
  mit laengerem Vorlauf aufsetzen: ALLE Features, die innerhalb des
  gewaehlten Vorlaufs liegen, fallen weg (nicht nur der kuerzeste Lag -
  auch Rolling-Fenster, die in den Vorlauf hineinreichen), und durch
  vorlauf-sichere Varianten (laengere Lags, Rolling-Fenster ab dem
  Vorlauf) ersetzen.

## Dokumentation

- Projekt-`README.md` erklaerend fuehren: Aufgabe, Split,
  Framing-Entscheidung (Nowcast vs. Forecast, mit den Leak-Audit-
  Zahlen), eine Tabelle "welcher BACKLOG-Kandidat wird hier wie
  getestet", laufender Stand mit Zahlen, Reibungsfunde fuers Template.
- Nach jedem Pipeline-Schritt einen eigenen Commit (`ML_Learning` ist
  lokal, kein Remote - nur committen, kein Push).
- Reibungsfunde direkt in der Projekt-`README.md` unter "Reibung fuers
  Template" sammeln. Generische Fallen (treffen jedes Projekt) wandern
  von dort in `WORKFLOW_GUARDS.md`, echte neue Backport-Kandidaten in
  `MLR3_Regression/BACKLOG.md` - projektspezifische Beobachtungen
  (konkrete Zahlen/Spaltennamen) bleiben im Projekt-README, nicht in
  diesem Skill.
