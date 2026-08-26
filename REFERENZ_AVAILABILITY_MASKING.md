# Referenz: Verfuegbarkeits-Maskierung, Oracle- vs. Feasible-Baseline, zeitgeblocktes Resampling

Theoretischer Hintergrund zu `012_feature_availability_audit.R` (bereits im
Template), `availability_masking.R`, `oracle_feasible_baseline.R` und
`time_blocked_resampling.R` (neu, dieser Backport). Der Code dokumentiert das
WAS; diese Referenz erklaert das WARUM. Verifiziert an 2 unabhaengigen Panel-/
Forecasting-Projekten (GeoAI-Drought `AStepAheadOfdrought`; Rossmann Store
Sales, siehe `ML_Learning/rossmann-store-sales-forecasting/README.md`).

---

## 1. Das Problem: Missingness ist selbst eine Verteilungseigenschaft

`012_feature_availability_audit.R` prueft bereits, ob ein Feature in Training
und Test unterschiedlich oft fehlt (`missing_rate_delta`). Der Teil, der bisher
fehlte: WAS folgt daraus fuer die lokale Bewertung?

Eine Kreuzvalidierung zieht ihre Folds ausschliesslich aus den Trainingsdaten.
Sie **erbt automatisch deren Missingness-Rate** - nicht die der echten
Testdaten oder der spaeteren Produktionsumgebung. Ist ein Feature im Training
haeufiger bekannt als es im Deployment sein wird (typische Ursachen: andere
Datenquelle, andere Zeitperiode, andere Teilpopulation, ein Sensor/eine
Meldekette, die im Trainingszeitraum zuverlaessiger lief), bewertet die CV das
Modell auf **sauebereren** Daten, als es im Ernstfall bekommt. Das Ergebnis ist
eine optimistisch verzerrte lokale Metrik, OHNE dass man das an der Zahl selbst
erkennen koennte - der Fehler zeigt sich nicht als Warnung, sondern als eine CV,
die "einfach zu gut" ist.

Das ist ein Spezialfall von Covariate Shift (siehe `REFERENZ_DISTRIBUTION_
SHIFT.md` im Klassifikations-Template fuer den allgemeinen Fall): hier
verschiebt sich nicht der WERT eines Features, sondern der
**Beobachtbarkeits-Indikator** (`is.na(x)`) selbst.

## 2. Der Fix: `apply_availability_profile()` / `mask_validation_by_availability_profile()`

Da `test.csv` schon VOR dem Training vorliegt, lässt sich die Luecke messen,
ohne die Zielwerte zu kennen: `missing_rate_delta = mean(is.na(test[[col]])) -
mean(is.na(train[[col]]))`, gekappt bei 0 (nur Faelle interessant, in denen
Test SCHLECHTER verfuegbar ist als Training - der umgekehrte Fall ist fuer die
CV-Optimismus-Frage irrelevant). Dieses Delta wird anschliessend als
zusaetzliche Zufalls-NA-Rate in die lokalen Validierungsfolds injiziert - die
CV bewertet das Modell dann auf einer Datenqualitaet, die der echten
Testsituation entspricht, statt der (moeglicherweise besseren)
Trainingsqualitaet.

**Wichtige Praxis-Lehre (Rossmann-Bestaetigung)**: die Pruefung muss auf den
tatsaechlich im Modell verwendeten Spalten laufen - inklusive daraus
ABGELEITETER Features. Ein Delta in einer Rohspalte (z.B. "Wann eroeffnete der
naechste Wettbewerber") schlaegt sich zwingend auf jedes daraus abgeleitete
Feature durch (z.B. "Monate seit Wettbewerbseroeffnung" - fehlt das Rohdatum,
ist die Ableitung per Definition ebenfalls unbekannt). Eine Pruefung, die nur
die Rohspalten betrachtet, uebersieht solche Luecken systematisch.

## 3. Oracle- vs. Feasible-Baseline: der Extremfall (Delta = 100%)

Wenn ein Feature im Training komplett vorhanden, im Test aber komplett
ABWESEND ist (`missing_rate_delta = 1`, bereits als `test_only_cols`/
umgekehrt `train_only_cols` von `012` erkannt), ist Maskieren sinnlos - das
Feature darf im deploybaren ("feasible") Modell gar nicht erst verwendet
werden. Ein Modell, das es trotzdem nutzt (z.B. weil es waehrend der
Trainingsphase bequem verfuegbar war), heisst **Oracle-Modell**: es nutzt
Information, die im echten Anwendungsfall nicht existiert.

Der Oracle/Feasible-Vergleich macht das Ausmass des Risikos sichtbar, BEVOR es
in Produktion zum Problem wird: beide Modelle werden auf demselben Holdout
verglichen, aber mit unterschiedlichem Feature-Umfang. Die Differenz ist der
"Optimismus", den man sich einhandelt, wenn man - versehentlich oder aus
Bequemlichkeit - eine train-only-Spalte im finalen Modell belaesst.
**Rossmann-Befund**: bei `Customers` (Kundenzahl, nur in `train.csv`) betrug
dieser Optimismus 55,5% relativer RMSE-Verbesserung - ein besonders deutliches
Beispiel, weil Kundenzahl fast tautologisch mit Umsatz korreliert.

Metriken sollten zusaetzlich nach Segmenten gruppiert werden (siehe
`125_segment_metrics.R`): der Oracle-Vorteil kann in einzelnen Teilgruppen
(seltene Ereignisse, Feiertage, Randfaelle) staerker oder schwaecher ausfallen
als im Gesamtdurchschnitt.

## 4. Zeitgeblocktes Resampling: derselbe Mechanismus, andere Ursache

Zufaellige Kreuzvalidierung bei Zeitreihen-/Panel-Daten hat ein verwandtes,
aber eigenstaendiges Problem: sie erlaubt dem Modell, aus Zeilen zu lernen, die
zeitlich NACH der zu bewertenden Zeile liegen ("Blick in die eigene Zukunft
der Entity") - selbst wenn keine einzige Spalte fehlt. Der Fix ist
strukturell anders (Split nach Zeit, nicht nach Verfuegbarkeit), aber die
Konsequenz ist dieselbe wie bei der Missingness-Luecke: eine zu optimistische
lokale Metrik, die sich erst beim echten (zeitlich spaeteren) Test zeigt.
`make_resampling(purpose = "time_blocked")` instanziiert Rolling-Origin-Folds
(Trainingsblock strikt vor Validierungsblock) statt einer zufaelligen
Fold-Zuweisung.

**Rossmann-Befund**: zufaellige CV war im Mittel optimistischer (RMSE 0.2545
vs. 0.2696 zeitgeblockt, ~6% relativ) UND deutlich weniger stabil zwischen
Folds - beides die erwartete Signatur eines Zeit-Lecks.

## 5. Bewusste Grenze: die Persistence-Baseline ist NICHT immer die bessere Unterkante

Eine verbreitete Forecasting-Heuristik lautet: bei Zeitreihen ist die
"No-Signal"-Unterkante oft `y(t) = y(t-k)` (die letzte/vorherige bekannte
Beobachtung), nicht der globale Mittelwert. Das stimmt nur, wenn das Zeitmuster
regelmaessig genug ist, dass ein Lag-Wert tatsaechlich mehr Information traegt
als reines Rauschen. **Rossmann widerlegt die Heuristik als generelle Regel**:
Verkaeufe schwanken durch unregelmaessige Promo-/Feiertags-Ereignisse so
stark, dass ein Lag-7-Wert (gleicher Wochentag letzte Woche) schlechter
abschneidet als der stabile historische Mittelwert (RMSE 0.4263 vs. 0.4165).
**Konsequenz fuer den Backport**: die Persistence-Baseline wird als
OPTIONALER Baseline-Typ eingefuehrt (aktiv nur bei explizit konfigurierter
Lag-Spalte), niemals als Ersatz fuer `naive_mean` oder als generelle Annahme.
Beide Baselines sollten bei jedem neuen Forecasting-Projekt parallel berechnet
werden, um diese Projekt-zu-Projekt-Variabilitaet zu erfassen, statt sie
anzunehmen.
