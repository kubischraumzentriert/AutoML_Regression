# 004: DB-Merge deckt nur aggregierte Tabellen ab, nicht Zeilenebene

Status: Accepted
Datum: 2026-08-08 (Entscheidung selbst aelter - stand bisher nur als
Kopfkommentar in `merge_project_experiments.R`, hier zur ADR befoerdert,
analog zum Klassifikations-Template)

## Kontext

`merge_project_experiments.R` (siehe ADR 001) konsolidiert Projekt-DBs in
die zentrale Template-DB. Die DB enthaelt neben aggregierten Tabellen
(`project`/`workflow`/`run`/`run_config`/`model_config`/`resampling`/
`hyperparam`/`metric_result`) auch zwei Zeilenebene-Tabellen: `prediction`
und `prediction_prob` (eine Zeile je Beobachtung/Vorhersage).

## Entscheidung

Der Merge kopiert **ausschliesslich** die acht aggregierten Tabellen.
`prediction`/`prediction_prob` werden **nie** in die zentrale DB
uebernommen - sie bleiben ausschliesslich in der jeweiligen projekteigenen
`experiments.db`.

## Begruendung

1. **Zeilenebene ist projektspezifisch und projektuebergreifend nicht
   sinnvoll vergleichbar.** `row_id`/`truth`/`response` beziehen sich auf
   unterschiedliche Datensaetze und Zielspalten je Projekt - eine Zeile aus
   Projekt A neben einer Zeile aus Projekt B in derselben Tabelle ergibt
   keinen auswertbaren Sinn.
2. **Technischer Grund**: `prediction`/`prediction_prob` nutzen bewusst
   lokale `INTEGER`-Keys (`pred_seq`/`pprob_pred_seq`, SQLite-rowid-Alias)
   statt UUID-Text-Keys wie alle anderen Tabellen (Platzgrund bei
   potenziell sehr vielen Zeilen, siehe `db_schema.sql`-Kopfkommentar). Ein
   Merge muesste diese Keys beim Kopieren neu vergeben und alle
   referenzierenden Fremdschluessel mit umschreiben - ohne echten Nutzen
   (siehe Punkt 1) lohnt sich dieser Zusatzaufwand nicht.

## Konsequenz

Die projekteigenen `experiments.db`-Dateien bleiben vollstaendig und
unveraendert - sie behalten ihre kompletten `prediction`-Daten fuer lokale
Analysen. Die zentrale DB eignet sich fuer aggregierte Cross-Projekt-Fragen
(Laufzeiten, Algorithmus-/Metrik-Muster, Tuning-Erfolgsquote), NICHT fuer
zeilengenaue Cross-Projekt-Analysen - das war nie das Ziel.

## Alternativen erwogen

- **Zeilenebene mit Key-Neuvergabe mitmergen** - verworfen, siehe Punkt 2,
  ohne belegten Nutzen (Punkt 1) nicht gerechtfertigt.
- **Zeilenebene mit Projekt-Praefix statt Neuvergabe mergen** - nicht
  evaluiert, gleiches Problem wie oben: kein Anwendungsfall bekannt, der
  zeilengenaue Cross-Projekt-Vergleiche brauchte.
