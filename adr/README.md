# Architekturentscheidungen (ADRs)

Kurze, nummerierte Datensaetze fuer Entscheidungen, die das Verhalten
kuenftiger Sessions/Agenten praegen sollen, aber leicht wieder unbeabsichtigt
rueckgaengig gemacht werden koennten, wenn sie nur als Prosa in README/
NEURAL_DEPLOY/DATABASE dokumentiert waeren. Bewusst schlank gehalten (kein
Graph, kein YAML-Header) - passend zur Groesse dieses Repos.

Status-Werte: `Accepted` (gilt), `Proposed` (Vorschlag, noch nicht final),
`Deprecated` (durch eine neuere ADR ersetzt, hier vermerken warum).

| Nr. | Titel | Status |
|---|---|---|
| [001](001-local-project-db-central-merge.md) | Lokale Projekt-DB statt geteilter Live-DB, zentrale Konsolidierung per Merge-Skript | Accepted |
| [002](002-r-only-python-gpu-export.md) | R-only-Template, Python nur als wegwerfbarer Kaggle-GPU-Export | Accepted |
| [003](003-backport-after-confirmation.md) | Template-Aenderungen erst nach ≥2-Projekt-Bestaetigung oder Null-Ergebnis-Beleg backporten | Accepted |
| [004](004-db-merge-aggregated-tables-only.md) | DB-Merge deckt nur aggregierte Tabellen ab, nicht Zeilenebene (`prediction`/`prediction_prob`) | Accepted |
| [005](005-targets-covers-production-path-only.md) | `targets`-Pipeline deckt nur den finalen Produktionspfad ab, nicht die explorativen Skripte | Accepted |
| [006](006-identical-db-schema-across-templates.md) | Beide Templates halten ihr `experiments.db`-Schema bewusst identisch | Accepted |

## Wann eine implizite Entscheidung zur ADR wird

Viele Design-Entscheidungen stehen bereits als Prosa/Code-Kommentar in
README/NEURAL_DEPLOY/Skript-Kopfkommentaren - nicht jede davon braucht eine
eigene ADR-Datei (sonst verwaessert der Zweck). Befoerdern, wenn BEIDE
zutreffen:

1. Die Entscheidung hatte echte Alternativen (kein Zwang, sondern eine
   bewusste Wahl mit Trade-off).
2. Ein kuenftiger Agent koennte sie plausibel versehentlich umkehren/
   "reparieren", ohne die urspruengliche Begruendung zu sehen.

Sonst reicht die bestehende Prosa-Dokumentation am jeweiligen Ort.

Dieses Verzeichnis existiert **dupliziert** im Schwester-Repo
`kubischraumzentriert/AutoML` (Klassifikations-Template, nicht als
gemeinsame Referenz) - siehe Begruendung in ADR 001 (keine Rueckverweise
zwischen eigenstaendigen Repos). Bei einer Aenderung an einer dieser
Entscheidungen: die passende ADR in BEIDEN Repos pruefen, nicht nur hier.

`AGENTS.md` verweist hierher; die "Pflege dieser Datei"-Prueffrage dort
schliesst ADRs mit ein.
