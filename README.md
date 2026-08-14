# AutoML Regression

Ein wiederverwendbares `mlr3`-AutoML-Template für tabellarische
Regressionsaufgaben (R) — Schwesterprojekt zum Klassifikations-Template
[`AutoML`](https://github.com/kubischraumzentriert/AutoML), gleiche
Methodik, geteiltes Datenbankschema.

## Warum dieses Template anders ist

- **Nichts wird ungeprüft übernommen.** Jedes neue Diagnose-Modul (z.B.
  Conformal-Prediction-Intervalle, Leak-Audit-Guards, Ensemble Selection)
  muss erst synthetisch auf bekanntem Ground Truth verifiziert und dann an
  **zwei unabhängigen Projekten** bestätigt werden, bevor es ins Template
  zurückfließt — festgehalten als Architekturentscheidung ([`adr/003`](adr/003-backport-after-confirmation.md)),
  nicht nur als Konvention im Kopf.
- **Negativbefunde werden dokumentiert, nicht versteckt.** Kandidaten, die
  (noch) keine zweite Bestätigung haben oder sich als Sackgasse erwiesen
  haben, stehen offen in [`BACKLOG.md`](BACKLOG.md), statt stillschweigend
  zu verschwinden.
- **Metrik-Wahl wird selbst hinterfragt.** RMSE ist nicht automatisch die
  richtige Zielgröße — bei schiefen/nullmassigen Zielen (z.B. Versicherungs-
  Schadenzahlen) kann sie irreführen (siehe unten).

## Ein paar bestätigte Ergebnisse

**Die falsche Metrik kann das schlechtere Modell gewinnen lassen.** Bei
einem Versicherungs-Schadendatensatz mit vielen Nullen (`tweet`, Count-
Regression) unterschieden sich zwei Modelle in RMSE kaum (+0,4%) — aber in
der eigentlich passenden Metrik (Poisson-/Tweedie-Devianz) um **+15497%**.
Das vermeintlich bessere Modell nach RMSE hatte sogar die **schlechtere**
Devianz. Konsequenz: das Template prüft jetzt aktiv, ob RMSE/MAE für ein
gegebenes Ziel überhaupt die richtige Metrik ist, statt sie automatisch zu
verwenden.

**Ein Datenleck wurde erst durch systematisches Nachbohren vollständig
gefunden, nicht beim ersten Blick.** Bei einem Bike-Sharing-Datensatz
erkannte der automatisierte Guard korrekt, dass die Spalte `registered`
das Ziel praktisch definiert (RMSE sprang von 3.12 auf 32.50, sobald sie
entfernt wurde) — übersah aber zunächst eine zweite, kleinere Leck-Quelle
(`casual`, die zusammen mit `registered` das Ziel zu 100% erklärt). Nach
Korrektur lag der wirklich ehrliche Wert bei RMSE 40.67 — rund 20% höher,
als die erste "bereinigte" Zahl vermuten ließ.

**Mehrere Modelle klug kombinieren statt nur das beste einzeln zu
nehmen.** Greedy Ensemble Selection (Caruana et al. 2004, aus dem
Klassifikations-Template portiert) schlug beim eigenen Referenzprojekt
sowohl das beste Einzelmodell (RMSE 0.0565) als auch einen einfachen
gleichgewichteten Blend (RMSE 0.0572): **RMSE 0.0564**.

**Unsicherheitsintervalle wurden gegen ihr eigenes mathematisches
Versprechen geprüft, nicht nur berichtet.** Ein Conformal-Prediction-Modul
soll garantieren, dass z.B. 90% der echten Werte im vorhergesagten
Intervall liegen. Gemessen am eigenen Referenzprojekt (51.775 Zeilen):
empirische Trefferquote **90.1%** bei Zielwert 90.0% — die Garantie hält
tatsächlich, nicht nur in der Theorie.

## Mehr Tiefe

- [`README_DETAILS.md`](README_DETAILS.md) — Projektidentität und die `targets`-Pipeline im Detail.
- [`WorkflowDescription.md`](WorkflowDescription.md) — der komplette Ablauf als Mermaid-Diagramm inkl. aller Entscheidungspunkte; auch ohne KI-Unterstützung nachvollziehbar.
- [`BACKLOG.md`](BACKLOG.md) — Kandidaten ohne zweite Projektbestätigung, vollständige Entscheidungshistorie.
- [`adr/`](adr/) — Architekturentscheidungen (warum lokale Projekt-DBs statt einer geteilten Live-DB, R-only-Policy, die ≥2-Projekt-Backport-Regel).
