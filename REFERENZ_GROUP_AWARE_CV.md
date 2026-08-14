# Referenz: Group-aware Resampling + Permutationstest fuer Gruppen-Kandidaten

Theoretischer Hintergrund zu `group_resampling.R`: warum Standard-k-fold-CV
bei geclusterten/hierarchischen Daten (mehrere Zeilen pro Entitaet - Patient,
Ort, Geraet, Kunde ...) die Generalisierungsfaehigkeit systematisch
ueberschaetzt, wie mlr3 das strukturell loest, und wie sich eine vermutete
Gruppenspalte statistisch bestaetigen laesst, bevor man ihr vertraut.

---

## 1. Herkunft

Entstanden aus einer gemeinsam erarbeiteten didaktischen Aufarbeitung des
bereits laenger bestehenden `group_resampling.R`-Moduls (`set_group_role()`/
`diagnose_group_cv()`, urspruenglich aus `SubjektDatensatz`/Parkinson-
Telemonitoring zurueckgefuehrt). Die Frage "wie erkennt man automatisiert,
ob eine vermutete Spalte ueberhaupt eine echte Gruppe ist" fuehrte zu zwei
neuen Funktionen (`test_group_significance()`, `scan_group_candidates()`),
zuerst dokumentiert in `ML_Learning/SubjektDatensatz/DIDAKTIK_GROUP_CV.md`
(separates, rein lokales Repo, siehe `adr/003` fuer die DIDAKTIK-Konvention).

## 2. Das Problem: die i.i.d.-Annahme hinter k-fold CV

Standard-k-fold-CV nimmt implizit an, dass jede Zeile ein unabhaengiges,
neues Stueck Information ist (i.i.d. - independent and identically
distributed). Bei Mehrfachmessungen derselben Entitaet (z.B. ~140 Aufnahmen
je Patient, ~137 Zeitpunkte je Messort) ist das offensichtlich verletzt:
zwei Zeilen derselben Entitaet teilen sich eine entitaetsspezifische
"Signatur", unabhaengig vom eigentlich interessierenden Zusammenhang.
Landet eine Zeile im Trainings- und eine andere Zeile derselben Entitaet im
Test-Fold, muss das Modell die eigentliche Beziehung nicht lernen, um gut
abzuschneiden - Wiedererkennung reicht. Random-CV kann das nicht erkennen,
weil sie nur auf einzelne Zeilen schaut, nicht auf Entitaetszugehoerigkeit.

Dieses Muster (Beobachtungen geclustert nach Patient/Ort/Zeitraum/Geraet,
waehrend die Clusterzugehoerigkeit selbst nicht zur eigentlichen
Fragestellung gehoert) ist der **Normalfall**, nicht die Ausnahme. Roberts
et al. (2017, *Ecography* 40(8), 913-929, "Cross-validation strategies for
data with temporal, spatial, hierarchical, or phylogenetic structure")
fassen das systematisch zusammen: Standard-CV ueberschaetzt in solchen
Faellen die Generalisierungsfaehigkeit systematisch, nicht zufaellig in
beide Richtungen. Der Split muss entlang der Struktur erfolgen, die beim
Deployment ebenfalls unbekannt sein wird.

## 3. Die mlr3-Loesung: Gruppen-Rolle statt eigener Resampling-Klasse

Andere Werkzeuge (z.B. scikit-learn) tauschen die Resampling-Strategie
komplett aus (`GroupKFold` statt `KFold`). mlr3 geht einen anderen Weg: die
Gruppenspalte bekommt im Task die Rolle `"group"` - **jede** abgeleitete
`Resampling`-Klasse (nicht nur CV) respektiert das dann automatisch. Aus der
`mlr3`-Dokumentation (`Resampling.Rd`), woertlich: *"observations with the
same value of the variable with role 'group' are marked as 'belonging
together'. For each resampling iteration, observations of the same group
will be exclusively assigned to be either in the training set or in the
test set."*

`set_group_role(task, group_col)` entfernt die Spalte aus den Features
(sonst waere die Entitaets-ID selbst ein Leak) und setzt die Rolle. Der
eigentliche Resampling-Aufruf danach bleibt identisch zum ungruppierten
Fall (`rsmp("cv", folds)$instantiate(task)`) - nur der hineingereichte Task
unterscheidet sich. `diagnose_group_cv()` vergleicht random-CV gegen
group-CV auf derselben Aufgabe; eine grosse Luecke zeigt Gruppen-
Sensitivitaet an.

## 4. Der Permutationstest: eine vermutete Gruppe statistisch bestaetigen

Welche Spalte ueberhaupt eine Gruppenspalte ist, kann kein Algorithmus
automatisch herausfinden - das erfordert Weltwissen (siehe Abschnitt 6).
Aber OB eine per Weltwissen vermutete Spalte tatsaechlich echte Struktur
traegt, laesst sich statistisch pruefen, bevor man ihr vertraut.

**Teststatistik** eta^2 (Anteil der Gesamtvarianz von `target`, den die
Gruppenzugehoerigkeit erklaert - dieselbe Varianzzerlegung wie hinter der
klassischen One-Way-ANOVA/F-Statistik): `SS_zwischen / SS_gesamt`.

**Die Nullverteilung wird erzeugt, nicht angenommen**: die Werte der
Gruppenspalte werden zufaellig unter den Zeilen gemischt (`sample(group)`)
- das erhaelt die Gruppengroessen exakt, zerstoert aber jede echte
Aehnlichkeit innerhalb einer (Pseudo-)Gruppe. Wiederholt (`n_perm`-mal)
ergibt das die Verteilung von eta^2, die man rein durch Zufall erwarten
wuerde. Der p-Wert ist der Anteil dieser Zufallswerte, die den echten Wert
erreichen oder uebertreffen (einseitig, `+1`-Korrektur nach Davison &
Hinkley 1997 gegen `p=0`).

`test_group_significance(target, group, n_perm, seed)` implementiert das
fuer eine einzelne Spalte; `scan_group_candidates(data, target_col,
candidate_cols, ...)` wendet es auf mehrere Spalten an und liefert eine
nach p-Wert sortierte Kandidatenliste. Kein Standard-Pipeline-Schritt -
bewusst nur bei konkretem Verdacht aufrufen (viele Spalten x viele
Permutationen ist nicht billig).

## 5. Grenzen: Kardinalitaet reicht als Filter nicht immer

eta^2/p-Wert allein reichen nicht: eine niedrig-kardinale Spalte kann
signifikant sein, ohne ein Gruppen-Risiko zu sein (es gibt keine "neuen"
Level, auf die man generalisieren muesste - z.B. Geschlecht). Deshalb
filtert `moegliche_entitaet` zusaetzlich auf Kardinalitaet
(`min_cardinality`/`max_cardinality_ratio`). Das reduziert offensichtliche
Fehlalarme, ersetzt aber NICHT die menschliche semantische Pruefung - zwei
in Abschnitt 6 dokumentierte Faelle zeigen das konkret: ein Confounder
(Alter als Stellvertreter fuer Patientenidentitaet) und eine geteilte
Zeitachse (viele Level, aber keine wiederholbare Entitaet - das eigentliche
Risiko dort ist zeitliche Extrapolation, die zeitbasierte statt
gruppenbasierte CV braucht).

## 6. Reale Anwendung (2 Projekte, ADR-003 erfuellt)

| Projekt | Domaene | Zeilen | Getestete Spalte | eta^2 | p-Wert |
|---|---|---:|---|---:|---:|
| `SubjektDatensatz` (Parkinson-Telemonitoring) | medizinisch | 5875 | `subject.` (echte Patienten-ID, 42 Level) | 0.934 | 0.001 |
| `SubjektDatensatz` | medizinisch | 5875 | kuenstliche Zufallsgruppe (Negativkontrolle) | 0.007 | 0.556 |
| `AStepAheadOfdrought` | Klima/Hydrologie | 49960 (Stichprobe aus 2.15 Mio.) | `location_id` (echter Messort, 365 Level) | 0.193 | 0.005 |
| `AStepAheadOfdrought` | Klima/Hydrologie | 49960 | kuenstliche Zufallsgruppe (Negativkontrolle) | 0.007 | 0.650 |

Beide Projekte: der echte Entitaetskandidat liegt weit ausserhalb der
eigenen Nullverteilung (Faktor >20 gegenueber deren Median), die
Zufallskontrolle landet exakt im Zentrum ihrer Nullverteilung - der Test
trennt korrekt, an zwei strukturell unabhaengigen Domaenen (medizinisch vs.
Klima/Hydrologie, 5875 vs. 2.15 Mio. Zeilen, aehnliches
Kardinalitaets-Verhaeltnis ~0.007-0.0073).

**Beide Projekte bestaetigten zusaetzlich unabhaengig den Grenzfall aus
Abschnitt 5**: `SubjektDatensatz`s `age` (Confounder der Patientenidentitaet)
und `AStepAheadOfdrought`s `time` (geteilte Zeitachse, keine wiederholbare
Entitaet) werden beide vom Kardinalitaetsfilter durchgelassen, obwohl sie
keine echten Gruppen im eigentlichen Sinn sind - zwei strukturell
verschiedene Bestaetigungen, dass die Kardinalitaetsgrenze eine Heuristik
bleibt, kein Ersatz fuer semantisches Urteil.

## 7. Status

**Backportiert (2026-08-14)**: `test_group_significance()`/
`scan_group_candidates()` in `group_resampling.R` ergaenzt. Kostenhinweis:
bei sehr grossen Datensaetzen (>~500k Zeilen) vor dem Aufruf eine Stichprobe
ziehen, die die Gruppenstruktur erhaelt (nach Entitaeten sampeln, nicht nach
Zeilen - siehe `AStepAheadOfdrought/verify_group_candidate_scan.R` als
Vorlage), sonst wird der Permutationstest unnoetig teuer.

## 8. Quellen

- Roberts, D.R., Bahn, V., Ciuti, S. et al. (2017). "Cross-validation
  strategies for data with temporal, spatial, hierarchical, or
  phylogenetic structure." *Ecography*, 40(8), 913-929.
- Davison, A.C. & Hinkley, D.V. (1997). *Bootstrap Methods and Their
  Application*. Cambridge University Press - Quelle der `+1`-Korrektur
  fuer Permutations-p-Werte.
- `ML_Learning/SubjektDatensatz/DIDAKTIK_GROUP_CV.md`,
  `group_resampling.R`, `032_verify_permutation_test.R`,
  `033_verify_candidate_scan.R` - Ursprungs-Herleitung, synthetische
  Positiv-/Negativkontrolle.
- `ML_Learning/AStepAheadOfdrought/verify_group_candidate_scan.R` - zweite,
  unabhaengige Bestaetigung.
