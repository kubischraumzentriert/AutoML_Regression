---
name: setup-panel-forecast-project
description: Setzt ein neues Panel-/Forecasting-Regressionsprojekt aus dem MLR3_Regression-Template auf (Entity x Zeit, zeitgeblockter Split) und fuehrt es durch die ersten Diagnose- und Framing-Schritte. Nutzen, wenn der Nutzer ein neues OpenML-/Kaggle-/UCI-Zeitreihen-/Panel-Regressionsprojekt aufsetzen will ("setz das X-Projekt auf", "neues Forecasting-Projekt", "Panel-Datensatz mit dem Regression-Template") oder wenn eine der unten genannten Fallen (mlr3 "different column info", 030-Ladeordnung, entity_history-Lags, Adversarial-AUC auf Zeitsplit) auftritt.
---

# Panel-/Forecasting-Regressionsprojekt aufsetzen

Wiederholbares Verfahren, entstanden aus `beijing-air-quality-panel`
(2026-09-10/11, 2. Zeuge fuer die offenen `MLR3_Regression`-BACKLOG-
Kandidaten 6-9). Fruehere Panel-Projekte als Referenz: `AStepAheadOfdrought`,
`rossmann-store-sales-forecasting` (beide `ML_Learning`).

## Wann anwenden

Ein neuer Datensatz mit **Entity x Zeit**-Struktur (dieselbe Entitaet in
vielen Zeilen ueber die Zeit) und **Regressionsziel** soll mit dem
`MLR3_Regression`-Template bearbeitet werden - typischerweise ein echter
Forecast (Zukunftszeitraum vorhersagen), nicht ein i.i.d.-Zufallssplit.

## Ablauf

### 1. `001_fetch.R`: Daten holen + zeitgeblockter Split

- Reproduzierbarer Download in `001_fetch.R` (`download.file(..., method
  = "libcurl")`, idempotent - erst laden/entpacken, wenn `train.csv`
  fehlt). Rohdaten sind per `ML_Learning/.gitignore` (`*.csv`/`*.zip`)
  ohnehin nicht versioniert.
- Panel zusammenfuegen (z.B. `rbindlist` ueber Stations-/Entity-CSVs),
  `datetime` als `POSIXct` bauen, Kalender-Features ableiten (`year`/
  `month`/`day`/`hour`/`dow`/`is_weekend`), Zeilen ohne Zielwert
  entfernen, `setorder(entity, datetime)`, `id := .I`.
- **Split zeitgeblockt**: Test = die letzten N Monate (bei Drought/
  Rossmann/Beijing jeweils die letzten ~6 Wochen bis 6 Monate, ~10-15 %
  der Zeilen) - ein echter Zukunftszeitraum. `train <- dt[datetime <
  cutoff]`, `test <- dt[datetime >= cutoff]`.
- **`datetime` ist BEWUSST kein Modell-Feature** (absolute Zeit als
  Feature ist eine Forecasting-Fussangel und macht die Adversarial-
  Validation trivial, s.u.). Die zyklische Zeitinfo steckt in den
  Kalender-Features. `datetime` wird nur fuer den Split und fuer
  `time_blocked_resampling.R`s `dt`-Parameter gebraucht -> `id ->
  datetime` separat nach `_artifacts/time_index.csv` schreiben, NICHT in
  `train.csv`/`test.csv`.
- Lokal-only-Projekte (kein Kaggle/Zindi): `test.csv` DARF die echte
  Zielspalte tragen (ehrliches Scoring, kein Leaderboard). Im README
  vermerken - `012_feature_availability_audit.R` meldet das Ziel dann als
  harmloses "test-only feature".

### 2. `000_config.R` anpassen

Aus dem Template kopieren, dann setzen:

- `target_col`, `id_col <- "id"`, `project_name`, `entity_col <-
  "<entity>"`.
- `primary_measure_id <- "regr.rmse"` + `baseline_measure_ids` (RMSE +
  MAE als robustere Kontrollmetrik, bei rechtsschiefem Ziel wichtig).
- `prediction_bounds <- c(0, Inf)` fuer nicht-negative Ziele
  (Default-Template ist `c(0, 1)` - fuer eine Wahrscheinlichkeit;
  `pmin(Inf, x)` ist ein No-op fuer die obere Schranke).
- `baseline_persistence_entity_col <- NULL` LASSEN, wenn `datetime` kein
  Task-Feature ist - die Persistence-Baseline in `030_baseline.R` liest
  die Datumsspalte aus `task_train_small$data()` und wuerde sonst
  scheitern. Regulaere Lag-Features kommen ueber ein eigenes
  `025_forecast_features.R` (s.u.), nicht ueber diesen `030`-Einzeiler.
- `segment_metric_cols <- c("<entity>", "<kategorie>", "month")` fuer
  `125_segment_metrics.R` (Kandidaten 7/9).
- Optional ein Schalter `forecast_variant <- TRUE`, der `train_path`/
  `test_path` auf `train_fc.csv`/`test_fc.csv` umlenkt (Forecast-
  Featureset) statt auf die Nowcast-Rohdaten.

### 3. Template-Skripte kopieren

Alle `*.R` aus `MLR3_Regression/` ausser `_targets.R`, `test_*.R`,
`multilayer_stack_test.R`, plus `db_schema.sql`. NIEMALS aus einer
anderen lokalen Projekt-Kopie.

### 4. Diagnose-Reihenfolge + Framing-Entscheidung

1. **`013_target_leak_audit.R`** (volle Daten). Bei Panel-Daten mit
   gleichzeitig gemessenen Zusatzgroessen (andere Sensoren am selben Ort
   zur selben Zeit): der Guard flaggt sie meist ueber die Einzel-Schwelle
   ODER den Korrelations-Cluster-Check (Schritt 1b). **Schritt-5-Urteil**:
   solche ko-gemessenen Features sind fuer einen *Nowcast* ("Sensor X
   ausgefallen, schaetze aus den Nachbarsensoren") legitim ex-ante, fuer
   einen *Forecast* aber ex-post/nicht bekannt. Framing-Entscheidung
   treffen und im README festhalten. Bei Forecast: ko-gemessene
   Zusatzgroessen raus, nur als GELAGGTER benannter Block wieder zulaessig
   (Kandidat 6).
2. **`012_feature_availability_audit.R`** + **`018_adversarial_
   validation.R`**.
   - Ein Adversarial-AUC nahe 1,0 auf einem zeitgeblockten Split ist
     **fast immer trivial**: `year`/`month` trennen Train/Test per
     Konstruktion. Das ist KEIN Covariate-Shift-Alarm wie bei einem
     echten Werte-Shift (z.B. `geoai-aquaculture`). Vor dem Alarmieren
     die univariaten Drift-Top-Features anschauen - wenn `year`/`month`
     dominieren, ist es der Kalender.
   - Die inhaltliche Frage: **welche Periode ist der Test?** Ist es EINE
     Saison (nur Winter, nur Trockenzeit, ...), dann ist die
     Zielverteilung dort verschoben und ein ueber alle Saisons
     trainiertes Modell unter-/ueberschaetzt systematisch. Das ist ein
     **Kompositionseffekt** -> zeitgeblockte CV + `composition_
     reweighting.R` nach `month`/Saison als Diagnose.

### 5. `025_forecast_features.R` + `026_forecast_reference.R`

- **`025`**: regulaere Lag-/Rolling-Features je Entity bauen -
  `data.table::shift(value, h)` fuer Lags (1h/24h/168h o.ae.),
  `frollmean(shift(value, 1L), k, align = "right", na.rm = TRUE)` fuer
  Rolling-Mittel der VERGANGENEN k Perioden (das `shift(1)` haelt die
  aktuelle Periode raus). Alles `by = entity`, nach `datetime` sortiert.
  Lags/Rolling ueber den KOMBINIERTEN Train+Test bauen und dann splitten -
  so nutzen die ersten Test-Zeilen korrekt Train-Vergangenheit (kein
  Leck, Rueckblick ist legitim). Ko-gemessene Zusatzgroessen entfernen,
  ihre `*_lag_Nh`-Varianten separat lassen (Kandidat 6).
- **`026`**: LightGBM unter **zeitgeblockter CV** (`make_resampling(task,
  "time_blocked", date_col = "datetime", dt = <id->datetime in Task-
  Zeilenreihenfolge>, k = 5L)`) vs. **Zufalls-CV** vs. **echtem Held-out-
  Test**, gegen Persistence-Baselines (`value_lag_24h` als Vorhersage)
  und den Mittelwert. Die zeitgeblockte CV liegt naeher am echten Test
  als die Zufalls-CV - die Restluecke ist der Kompositionsanteil.
- **Horizont bewusst waehlen**: ein dominanter Lag-1 (bei stark
  autokorrelierten Zielen wie Luftqualitaet: r ~0,95) macht die Aufgabe
  fast Persistenz - das Modell schlaegt `value_lag_1h` kaum. Fuer echten
  Feature-Engineering-Spielraum (Kandidaten 6-9) eine N-Schritt-Variante
  aufsetzen: `lag_1h`/`lag_24h` raus, nur `lag_168h` + Rolling + Kalender
  + Meteorologie.

## Bekannte Fallen

- **`030_baseline.R` bricht beim ersten Lauf ab**, wenn `task_train_
  small.rds` noch nicht existiert: `030` sourct `040_preprocessing.R`
  (definiert `make_imputed_learner`), laedt dann bei fehlendem Artefakt
  `source("020_task.R")` nach - und `020_task.R` beginnt mit `rm(list =
  ls())`, was `make_imputed_learner` wieder loescht. **Fix**: `020_task.R`
  immer zuerst separat laufen lassen (so auch in `WorkflowDescription.md`
  als Reihenfolge vorgesehen).

- **mlr3 "Learner ... received task with different column info (feature
  type or factor level ordering) during train and predict"** bei zwei
  SEPARAT gebauten Tasks (einer aus `train.csv`, einer aus `test.csv`):
  `fread` inferiert Spaltentypen je Datei unabhaengig (dieselbe Spalte
  wird `numeric` im Train, `integer` im Test, wenn die Testscheibe zufaellig
  nur ganze Zahlen enthaelt - `012_feature_availability_audit.R` zeigt
  diese Typ-Deltas), und Faktor-Level-Mengen/-Reihenfolgen koennen
  abweichen. **Fix**: EINEN gemeinsamen Task aus `rbind(train, test)`
  bauen (mit einem `.is_test`-Flag), numerische Spalten explizit
  `as.numeric`, Charakter explizit `as.factor`, dann per `row_ids`
  trennen: `learner$train(task_all, row_ids = train_rows)` /
  `learner$predict(task_all, row_ids = test_rows)`. Nie zwei Tasks.

- **`entity_history.R` (Kandidat 5) deckt regelmaessige hochfrequente
  Lags NICHT ab** - es hat `months_since_known()`/`weeks_since_known()`
  (Zeit seit einem Ereignis) und `current_or_last_known()` (letzter Wert
  vor der aktuellen Zeile, ~Lag-1). Fuer stuendliche/taegliche
  Panel-Lags + Rolling-Fenster direkt `data.table::shift`/`frollmean` je
  Entity nutzen (s.o. `025`). Template-Zusatz-Kandidat: ein generischer
  `add_regular_lags(dt, entity, time, value, lags, roll_windows)`-Helfer
  neben den bestehenden Ereignis-Helfern.

- **`mlr3measures::rsq` ist deprecated** - R² manuell rechnen: `1 -
  sum((truth - response)^2) / sum((truth - mean(truth))^2)`.

- **Windows/Git-Bash**: `Rscript.exe` per vollem Pfad
  (`C:\Users\HP\Programme\R\R-4.5.2\bin\Rscript.exe`), KEIN mehrzeiliges
  `-e` (Segfault) - R-Code in eine Datei schreiben und die ausfuehren.
  Lange Laeufe (LightGBM auf mehreren 100k Zeilen x mehreren
  Resamplings) im Hintergrund starten und per Datei-Existenz-Check
  ueberwachen.

## Dokumentation

- Projekt-`README.md` erklaerend fuehren (wie `geoai-aquaculture`/
  `beijing-air-quality-panel`): Aufgabe, Split, Framing-Entscheidung
  (Nowcast vs. Forecast, mit den Leak-Audit-Zahlen), eine Tabelle
  "welcher BACKLOG-Kandidat wird hier wie getestet", laufender Stand mit
  Zahlen, Reibungsfunde fuers Template.
- Nach jedem Pipeline-Schritt einen eigenen Commit (`ML_Learning` ist
  lokal, kein Remote - nur committen).
- Reibungsfunde direkt in der Projekt-`README.md` unter "Reibung fuers
  Template" sammeln; echte Backport-Kandidaten wandern von dort in
  `MLR3_Regression/BACKLOG.md`.
