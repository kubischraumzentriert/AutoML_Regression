# 002: R-only-Template, Python nur als wegwerfbarer Kaggle-GPU-Export

Status: Accepted
Datum: 2026-08-08 (Entscheidung selbst seit 2026-08 gelebt und in
`NEURAL_DEPLOY.md` ausfuehrlich dokumentiert - hier als ADR gebuendelt;
zurueckgefuehrt aus dem Klassifikations-Template, dort zuerst entschieden
und mit s6e8-Zahlen belegt)

## Kontext

Ein neuronales Tabellenmodell (v.a. FT-Transformer via `mlr3torch`) kann als
Ensemble-Diversitaet neben den GBMs wertvoll sein, wenn diese zu stark
korreliert sind. Die Frage: soll Python als Repo-Abhaengigkeit aufgenommen
werden, um neuronale Modelle einfacher auf Kaggle-GPU zu betreiben?

## Entscheidung

Dieses Repo bleibt **R-only**. Python ist **niemals** eine Repo-Abhaengigkeit,
sondern hoechstens ein duenner, wegwerfbarer Export fuer den finalen
Kaggle-GPU-Lauf - erzeugt erst, wenn ein R-Prototyp zeigt, dass sich ein
neuronales Modell lohnt (dekorreliert von den GBMs UND konkurrenzfaehig,
siehe Gate-Kriterium in `NEURAL_DEPLOY.md`).

## Begruendung

- **R/mlr3 ist das etablierte Oekosystem** fuer Entwicklung/Entscheidungen
  (Exploration, Devianz-/Signal-Diagnostik, CV, Modellwahl) - ueber viele
  Projekte validiert.
- **R-Weg auf Kaggle+GPU ist eine dokumentierte, mehrfache Sackgasse**
  (`mlr3misc`-Versionsskew, libtorch-404-Download, GPU-Accelerator-Fallstrick
  - am Klassifikations-Template dokumentiert, Mechanismus aufgabentyp-
  unabhaengig, siehe `NEURAL_DEPLOY.md`).
- **CPU-Training neuronaler Modelle in R ist fuer Prototypen/Entscheidungen
  geeignet, aber NICHT fuer Produktionsqualitaet bei groesseren
  Datenmengen** - empirisch belegt im Klassifikations-Template (s6e8,
  2026-08-08): ein FT-Transformer-Prototyp brauchte fuer nur 15 Epochen/
  `d_token=64` auf 20% der Daten bereits ~33 Minuten CPU-Zeit; hochgerechnet
  auf Kaggle-Produktionseinstellungen (40-80 Epochen, 100% Daten) liegt das
  im Bereich mehrerer Stunden. **Noch keine eigene Regressions-Messung**,
  aber der Mechanismus ist aufgabentyp-unabhaengig (reine Torch-CPU-
  Trainingsgeschwindigkeit).

## Faustregel

Liegt die hochgerechnete CPU-Laufzeit eines neuronalen Modells bei
Produktionseinstellungen ueber ca. **30 Minuten**, gilt CPU-Training fuer
dieses Projekt als nicht praktikabel - entweder Python-GPU-Export nutzen
oder das neuronale Modell fuer dieses Projekt verwerfen. Fuer die
Hochrechnung immer den **Ziel-Algorithmus selbst** an ein bis zwei kleinen
Stichprobengroessen timen - ein anderer, billigerer Algorithmus (rpart/
`regr.lm`) ist dafuer KEIN verlaesslicher Proxy (andere Skalierungs-
charakteristik, bei neuronalen Netzen zusaetzlich ein fixer Overhead pro
Epoche, der nicht mit der Zeilenzahl schrumpft).

Fuer Projekte mit ausreichend wenigen Zeilen kann CPU-Training dagegen
direkt tragfaehig sein - dann entfaellt der Python-Export komplett
(niedrigere Zeilenschwelle bisher nicht formal definiert, siehe
`BACKLOG.md`-Kandidat).

## Alternativen erwogen

- **Python als permanente Repo-Abhaengigkeit** - verworfen, um Werkzeug-
  vielfalt/Wartungslast nicht zu erhoehen; das R-Oekosystem deckt alles
  ausser dem finalen GPU-Lauf ab.
- **Neuronales Modell komplett meiden** - verworfen, da im Klassifikations-
  Template ein voll trainierter FT-Transformer (Python/GPU) einen echten,
  gemessenen Gewinn brachte (+0.00035 AUC ueber dem 3-GBM-Blend, s6e8).

## Konsequenz

Gilt aufgabentyp-unabhaengig (derselbe Mechanismus: R-Paket-Oekosystem auf
Kaggle, nicht Klassifikation vs. Regression) - siehe auch das Pendant-ADR
im Klassifikations-Template, wo die Erstbestaetigung stattfand. Eine
Bestaetigung in einem Template zaehlt aber nicht automatisch als
Bestaetigung fuers andere (siehe ADR 003) - bei der ersten eigenen
Regressions-Anwendung diese ADR mit echten Zahlen ergaenzen.
