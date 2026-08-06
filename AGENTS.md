# Hinweise fuer AI-Coding-Agenten (Codex, Claude Code, etc.)

Diese Datei ist der erste Anlaufpunkt fuer automatisierte Agenten, die in
diesem Repo arbeiten - analog zu `WorkflowDescription.md` fuer Menschen.
Schwesterprojekt: `kubischraumzentriert/AutoML` (Klassifikations-Template),
dessen `AGENTS.md`/`WorkflowDescription.md` dasselbe Muster tragen.

## Workflow-Diagramm aktuell halten

`WorkflowDescription.md` enthaelt ein Mermaid-Flowchart mit dem kompletten
Ablauf (`010`-`165`) inkl. aller Entscheidungspunkte, dazu die Bootstrap-
Workflow-Liste, das Signal-Gate/Stop-Regel-Detail und die Abgrenzung zum
Klassifikations-Template; `WORKFLOW_GUARDS.md` dokumentiert die einzelnen
Guard-Skripte (`012`/`013`/`015`/`018`/`125`/`158`) noch ausfuehrlicher.
Aendert ein Commit eine dieser Entscheidungen - ein neues Skript zwischen
bestehenden Schritten, eine neue oder veraenderte Verzweigung (z.B. neue
Signal-Gate-Schwelle, neue Guard-Stufe), eine geaenderte empfohlene
Reihenfolge - MUSS das Diagramm in `WorkflowDescription.md` im selben
Commit nachgezogen werden, nicht nur der Skript-Code. Eine reine
Parameter- oder Bugfix-Aenderung ohne neue Verzweigung braucht keine
Diagramm-Aenderung.

Vor dem Commit pruefen: veraendert der Commit die *Reihenfolge* der
Skripte, eine *Entscheidungsregel* (z.B. Signal-Gate-Stop-Regel, Leak-
Audit-Schwellen), oder fuegt er eine neue Guard-/Gate-Stufe hinzu (wie das
Neural-Gate aus `NEURAL_DEPLOY.md`)? Falls ja: `WorkflowDescription.md`
und ggf. `WORKFLOW_GUARDS.md` aktualisieren, sonst reicht der Code allein.

## Git-Arbeitsweise

- Vor groesseren Aenderungen `git status` pruefen. Wie beim
  Klassifikations-Template kann ein Repo dieser Familie gelegentlich
  parallel bearbeitet werden - keine fremden, unbekannten Aenderungen
  zuruecksetzen oder ueberschreiben.
- Beim Staging gezielt nur die tatsaechlich selbst geaenderten Dateien
  hinzufuegen, kein blindes `git add -A`/`git add .`.
- Standardarbeitsweise: zuerst lokal aendern, die Aenderung kurz
  zusammenfassen (was und warum), dann **committen nur nach ausdruecklicher
  Rueckfrage oder Freigabe** durch den Nutzer.
- **Pushen ist ein separater, erneut zu bestaetigender Schritt** - nie im
  selben Zug wie der Commit, auch nicht nach einer bereits erteilten
  Commit-Freigabe.
- Inhaltlich zusammenhaengende Aenderungen gemeinsam committen, nicht
  kuenstlich aufsplitten.

## Ressourcenschonende Arbeitsweise

- Bei einem klar abgegrenzten Thema gezielt die passende Datei lesen
  (Skript, Abschnitt in `WORKFLOW_GUARDS.md`/`BACKLOG.md`), nicht
  routinemaessig das ganze Repo laden.
- `git status`, `git diff --stat` und gefilterte Ausgaben bevorzugen statt
  vollstaendiger Logs/Diffs.
- Grosse Dateien (`README.md`, `BACKLOG.md`, `WORKFLOW_GUARDS.md`,
  `DATABASE.md`, `DEVIANCE_MEASURES.md`) gezielt ueber Ueberschriften/Suche
  lesen, nicht routinemaessig vollstaendig.
- Vor mehrminuetigen R-Laeufen (`100_lightgbm_tuning.R` Bayesian
  Optimization, `018_adversarial_validation.R` auf grossem Sample,
  `110_oof_ensemble.R`/`120_full_holdout_confirmation.R`) die Laufzeit grob
  abschaetzen (`estimate_tuning_runtime()` aus `db_logging.R` gibt
  Median-/P90-Schaetzungen aus bereits geloggten Laeufen) und bei
  gestapelten teuren Schritten vor dem Start explizit sagen, wie lange es
  dauert und ob der Scope reduziert werden soll - nicht erst, wenn der
  Nutzer nachfragt, wieso es so lange dauert.
- Nie mehrzeiligen R-Code direkt per `-e` an ein Terminal uebergeben
  (Segfault-/Fehlinterpretations-Risiko unter Windows/Git-Bash) - immer
  zuerst in eine `.R`-Datei schreiben, dann `Rscript.exe datei.R` ausfuehren.
- Rechenintensive Skripte im Hintergrund starten und Fortschritt per
  Log-Datei pruefen, nicht die Konsole blockieren.

## Aufwandskennzahl fuer Antworten

Ab Beginn einer neuen Session soll der Agent den geschaetzten relativen
Aufwand jeder inhaltlichen Antwort auf einer Skala von 1 bis 10 bewerten.
Kein exaktes Token-, Zeit- oder Kostenmass, sondern ein relativer
Arbeitsindikator.

Referenz:

```text
AGENTS.md + WorkflowDescription.md lesen und den Repo-Kontext
arbeitsfaehig aufnehmen = 3/10
```

Orientierung:

- `1-2/10`: direkte Antwort aus vorhandenem Kontext, keine neue Datei lesen.
- `3/10`: vollstaendiger Session-Einstieg (`AGENTS.md` + `WorkflowDescription.md`).
- `4-5/10`: zusaetzlich gezielt `WORKFLOW_GUARDS.md`/`BACKLOG.md`-Abschnitt
  oder ein bis zwei Skripte lesen, `experiments.db`-Abfrage.
- `6-7/10`: mehrere Skripte/Guards abgleichen, ein CV-/Benchmark-Lauf im
  Vordergrund (Minutenbereich), Doku mehrerer Abschnitte anpassen.
- `8-9/10`: neues Skript oder neuer Guard implementiert (z.B. in der
  `012`/`013`/`018`-Familie), laengerer Tuning-/Ensemble-Lauf im
  Hintergrund gestartet.
- `10/10`: grosser Durchstich ueber mehrere Schritte (z.B. neue
  Datenquelle komplett durch den Workflow gefahren), oder eine sehr lange
  gestapelte Analyse.

Am Ende jeder inhaltlichen Antwort angeben:

- Aufwand dieser Antwort mit kurzer Begruendung,
- kumulierte Summe und Durchschnitt (seit Sessionbeginn),
- Anfragen,
- eindeutig gelesene Dateien,
- eindeutig geaenderte Dateien,
- bearbeitete Themen.

Eine Datei wird pro Session nur einmal gezaehlt. Kleine Rueckfragen
innerhalb desselben Arbeitsblocks erzeugen kein neues Thema.

Ein Sessionwechsel sollte nach einem belastbaren Commit-/Push-Stand
geprueft werden, wenn viele Themen parallel offen sind, viele Dateien
geladen wurden, oder der kumulierte Aufwand grob im Bereich `40-50`
(aufsummierte 10er-Skala) liegt - ein grober, nicht dogmatischer
Richtwert, keine einzelne Kennzahl loest den Wechsel automatisch aus.

## Pflege dieser Datei

`AGENTS.md` nach groesseren Arbeiten pruefen und aktualisieren, wenn sich
aendert:

- die Ablauflogik/Entscheidungspunkte (siehe oben, Diagramm-Pflicht),
- die Git- oder Ressourcenschonende Arbeitsweise,
- die Aufwandskennzahl-Referenzwerte, falls sich der typische
  Session-Einstieg deutlich aendert.

Pruffrage am Ende groesserer Arbeiten:

```text
Muss AGENTS.md oder WorkflowDescription.md angepasst werden, damit eine
neue Agentensession korrekt und ressourcenschonend einsteigen kann?
```

## Siehe auch

- `WorkflowDescription.md` - der Workflow selbst, inkl. Diagramm,
  Bootstrap-Workflow-Liste und Signal-Gate/Stop-Regel.
- `README.md` - Projektidentitaet und die `targets`-Pipeline.
- `WORKFLOW_GUARDS.md` - Guard-Skripte im Detail (Leak-Audit, Feature-
  Availability, Adversarial Validation, Segmentmetriken, Submission-Diff).
- `BACKLOG.md` - Kandidaten, die noch keine zweite Projekt-Bestaetigung haben.
- `DATABASE.md` - `experiments.db`-Schema und Abfragen.
- `DEVIANCE_MEASURES.md` - Poisson-/Tweedie-Devianz-Theorie und -Nutzung.
- `NEURAL_DEPLOY.md` - R-only-Policy und Python-GPU-Export fuer neuronale Modelle.
