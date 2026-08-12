# 006: Beide Templates halten ihr `experiments.db`-Schema bewusst identisch

Status: Accepted
Datum: 2026-08-12 (Entscheidung selbst aelter - stand bisher nur als
Prosa/durch Kopieren gelebte Praxis, hier zur ADR befoerdert, weil sie das
Kriterium aus `adr/README.md` erfuellt: echte Alternative, und ein
kuenftiger Agent koennte plausibel versucht sein, in einem Template
"unnoetige" Spalten zu bereinigen, ohne die Cross-Template-Konsequenz zu
sehen)

## Kontext

`MLR3_Klassifikation` und `MLR3_Regression` sind zwei eigenstaendige
Repos, jedes mit eigenem `db_schema.sql`. Manche Spalten ergeben fuer den
jeweiligen Aufgabentyp nur eingeschraenkt Sinn (z.B. `mconf_class_weight_
power` ist bei Regressionsprojekten meist `NA`). Ohne explizite Absprache
koennten beide Schemata unabhaengig voneinander evolvieren.

## Entscheidung

Beide Templates halten ihr `experiments.db`-Schema (Tabellen, Spalten-
namen/-praefixe, Views) bewusst **strukturell identisch** - auch dort, wo
eine Spalte fuer den jeweiligen Aufgabentyp nicht durchgehend genutzt wird.

## Begruendung

1. **Cross-Template-Merges funktionieren bereits, nicht nur hypothetisch.**
   `merge_project_experiments.R`s Auto-Discovery durchsucht bekannte
   Projekt-Wurzeln unabhaengig vom Aufgabentyp - in der zentralen
   `MLR3_Klassifikation`-DB liegen bereits Regressions-Projekte
   (`tweet-freMTPL2-poisson`, `tweet-freMTPL2-tweedie`), weil deren lokale
   `experiments.db` exakt demselben Schema folgt und sich daher
   klaglos einmergen liess. Bei einem Schema-Drift waere das nicht moeglich.
2. **Geteilte `db_logging.R`-Funktionen.** Die Logging-Helfer werden per
   Copy zwischen den Templates uebertragen (siehe Punkt 15 im Regressions-
   `BACKLOG.md` - eine vergessene Pfad-Anpassung bei so einer Kopie war
   bereits ein realer Fehler). Diese Funktionen (`db_create_model_config`,
   `db_log_metric_result`, ...) funktionieren nur korrekt, wenn das
   Zielschema mit dem Quellschema uebereinstimmt - ein Schema-Drift wuerde
   sie bei der naechsten Kopie stillschweigend brechen (falsche Spalten-
   namen, fehlende CHECK-Constraints).
3. **Views 1:1 uebertragbar.** `v_model_results`, `v_best_per_algorithm_
   metric` etc. sind ebenfalls unveraendert zwischen beiden Repos kopiert -
   Schema-Konsistenz vermeidet, dass eine View in einem Repo funktioniert
   und im anderen mit einem SQL-Fehler abbricht.

## Konsequenz

Eine Schema-Aenderung (neue Spalte, neue Tabelle, geaenderter CHECK-
Constraint) muss **immer in beiden Repos gleichzeitig** nachgezogen
werden, auch wenn sie zunaechst nur fuer ein Template einen konkreten
Anwendungsfall hat. Ein kuenftiger Agent, der in einem Template eine
scheinbar ungenutzte Spalte bereinigen will, sollte diese ADR zuerst lesen
und die Aenderung im Schwester-Repo spiegeln, statt sie dort zu vergessen.

## Alternativen erwogen

- **Unabhaengig evolvierende Schemata je Template** - verworfen, siehe
  Begruendung Punkte 1-3 (bricht Cross-Template-Merges und geteilte
  Logging-Funktionen).
- **Ein gemeinsames Schema-Repo/Package statt Duplikation** - nicht
  evaluiert, waere eine groessere strukturelle Aenderung (echte geteilte
  Abhaengigkeit statt der bewusst eigenstaendigen Repos, siehe ADR 001s
  Begruendung fuer Eigenstaendigkeit) fuer einen bisher handhabbaren
  Duplikations-Aufwand (zwei `db_schema.sql`-Dateien, synchron gehalten).
