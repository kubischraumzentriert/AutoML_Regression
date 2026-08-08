# 001: Lokale Projekt-DB statt geteilter Live-DB, zentrale Konsolidierung per Merge-Skript

Status: Accepted
Datum: 2026-08-08

## Kontext

Jedes von diesem Template abgeleitete Projekt loggt Experimente (Runs,
Hyperparameter, Metrik-Ergebnisse) in eine SQLite-`experiments.db`. Die
Frage kam auf, ob alle Projekte von Anfang an direkt in eine gemeinsame,
zentrale DB schreiben sollten, statt jedes Projekt eine eigene DB zu geben
- das wuerde projektuebergreifende Analysen (Laufzeitschaetzung, Muster wie
"wie oft schlaegt Tuning den Default") sofort und ohne manuellen Schritt
ermoeglichen.

## Entscheidung

Jedes Projekt behaelt seine **eigene lokale** `_artifacts/experiments.db`.
Die zentrale Template-DB (`_artifacts/experiments.db` in diesem Repo) wird
**nachtraeglich** per `merge_project_experiments.R` befuellt (analog zum
Klassifikations-Template, dort zuerst umgesetzt und auf automatisches
Auffinden erweitert - dieses Repo sollte bei Gelegenheit dieselbe
Auto-Discovery uebernehmen, siehe `BACKLOG.md`):

- Findet Projekt-DBs (im Klassifikations-Template bereits) automatisch
  unter den bekannten Wurzeln (`R_Workspace`, `ML_Learning`) - keine
  hardcodierte Liste, die veraltet.
- Idempotent: `proj_name` ist sowohl R-seitig geprueft als auch DB-seitig
  `UNIQUE` erzwungen - mehrfaches Ausfuehren ist gefahrlos, keine Duplikate.
- Sichert die Ziel-DB vor jedem Lauf per Dateikopie.
- Sollte als letzter dokumentierter Workflow-Schritt festgehalten werden
  (`WorkflowDescription.md`), nicht als Code-Abhaengigkeit im Projekt selbst.

## Begruendung

- **Eigenstaendigkeit der Projektordner**: ein Projekt laesst sich ohne das
  Template-Repo lauffaehig kopieren/archivieren/teilen - kein absoluter
  Pfad zurueck zum Template noetig.
- **Keine Schreibkonkurrenz**: mehrere Projekte/Sessions koennen gleichzeitig
  lokal arbeiten (in diesem Oekosystem beobachtet - siehe Parallel-Session-
  Hinweis in `AGENTS.md`), ohne dass eine gemeinsame SQLite-Datei parallel
  von mehreren Prozessen beschrieben wird (Dateisperren-Risiko).

## Alternativen erwogen

- **Direktes Schreiben in eine gemeinsame DB von Anfang an** - verworfen,
  siehe beide Gruende oben.
- **Zentrale DB als Cloud-/Server-DB statt SQLite** - nicht evaluiert, waere
  eine deutlich groessere Aenderung fuer einen bisher nicht nachgewiesenen
  Bedarf.

## Konsequenz

Cross-Projekt-Analysen (z.B. Laufzeitschaetzung fuer ein neues Projekt aus
bereits gemessenen Laufzeiten anderer Projekte) sind nur so aktuell wie der
letzte Merge-Lauf. Wird `merge_project_experiments.R` nicht regelmaessig
ausgefuehrt, veraltet die zentrale DB - das ist ein bewusst akzeptierter
Trade-off gegenueber den Vorteilen oben.
