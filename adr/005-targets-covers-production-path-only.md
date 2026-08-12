# 005: `targets`-Pipeline deckt nur den finalen Produktionspfad ab, nicht die explorativen Skripte

Status: Accepted
Datum: 2026-08-12 (Entscheidung selbst aelter - stand bisher nur als Prosa
in `README.md` Zeile 123, hier zur ADR befoerdert, weil sie das Kriterium
aus `adr/README.md` erfuellt: echte Alternative, und ein kuenftiger Agent
koennte plausibel versucht sein, "fuer volle Reproduzierbarkeit" auch die
explorativen Skripte in den `targets`-Graphen aufzunehmen)

## Kontext

`_targets.R` orchestriert per `targets`-Paket den Pfad von der Task-
Erzeugung bis zur Submission (`020_task.R` bis `155_predict_submission.R`).
Daneben gibt es eine deutlich groessere Zahl explorativer Einzel-Skripte
(`030`-`145`: Baselines, Feature-Engineering-Vergleiche, Klassengewichts-
Suche, Adversarial Validation, Fehleranalyse, Ensemble Selection, ...), die
NICHT im `targets`-Graphen stehen. `targets`s Kernvorteil - inkrementelles
Neubauen nur veralteter Ziele bei einer Config-Aenderung - koennte
theoretisch auch auf diese Skripte angewendet werden.

## Entscheidung

`targets` deckt bewusst **nur** den finalen Produktionspfad ab (Task bis
Submission). Die explorativen Skripte `030`-`145` bleiben eigenstaendige,
manuell ausgefuehrte R-Skripte ausserhalb des `targets`-Graphen.

## Begruendung

1. **Einmalige Entscheidungsfindung, keine wiederholte Produktion.** Die
   explorativen Skripte beantworten Fragen wie "welches Modell, welche
   Gewichtung, welche Feature-Familie" - das laeuft typischerweise EINMAL
   pro Projekt, nicht wiederholt bei jeder `000_config.R`-Aenderung.
   `targets`s Caching-Vorteil (nur veraltete Ziele neu bauen) bringt hier
   kaum etwas im Verhaeltnis zum Aufwand, jedes Skript als `tar_target()`
   mit korrekten Abhaengigkeiten zu modellieren.
2. **Doppelrolle als Methodik-Vorlage.** Die Skripte dienen einem neuen
   Klassifikationsaufgaben-Workflow als Kopiervorlage fuer die METHODIK
   (wie man Klassengewichte testet, wie man Adversarial Validation
   aufsetzt) - als eigenstaendige, lesbare R-Datei ist das direkt
   nachvollziehbar und kopierbar. In einen `targets`-Graphen eingebettet
   waere dieses Muster schwerer zu erkennen und zu uebertragen.
3. **Wartungsaufwand vs. Nutzen.** Ein vollstaendiger Graph aus 30+
   explorativen Skripten waere breit und komplex zu pflegen (jede
   Abhaengigkeit muss korrekt deklariert sein), ohne dass der
   Reproduzierbarkeits-Nutzen (inkrementelles Caching) im Verhaeltnis zum
   Wartungsaufwand steht - diese Skripte aendern sich nach der initialen
   Analyse eines Projekts ohnehin selten.

## Konsequenz

`tar_make()` baut ausschliesslich den Pfad Task-Erzeugung -> finales
Modell -> Submission. Ein kuenftiger Agent, der versucht, "der
Vollstaendigkeit halber" auch `030`-`145` in den `targets`-Graphen
aufzunehmen, sollte diese ADR zuerst lesen - die Trennung ist eine
bewusste Entscheidung, kein vergessener Ausbauschritt.

## Alternativen erwogen

- **Vollstaendiger `targets`-Graph inkl. aller explorativen Skripte** -
  verworfen, siehe Begruendung Punkte 1-3.
- **Teilweise Aufnahme** (z.B. nur die am haeufigsten wiederholten
  Diagnose-Skripte wie `100_lightgbm_tuning.R`) - nicht evaluiert, kein
  konkreter Bedarf beobachtet, der den Zusatzaufwand rechtfertigen wuerde.
