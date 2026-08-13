# Devianz-Measures — Theorie, Hintergrund, Literatur

Begleitdokument zu `deviance_measures.R` (Code) und `WORKFLOW_GUARDS.md` §6
(Nutzung). Hier steht das *Warum*: die verteilungstheoretische Grundlage der
Poisson-/Tweedie-Devianz und die Quellen.

## 1. Warum Devianz statt RMSE/MAE?

RMSE/MAE unterstellen implizit **konstante, symmetrische** Fehler (Normal-/L1-
Annahme). Zähl- und Schadenlastziele sind aber **nicht-negativ, rechtsschief und
oft mit einer Punktmasse bei 0** (viele schadenfreie Policen). Für solche Ziele
ist die **mittlere Unit-Devianz** die passende Metrik:

- Sie ist die **Verlustfunktion des Modells selbst** (GLM/Boosting mit
  Poisson-/Tweedie-Objective minimieren genau die Devianz).
- Sie ist ein **strictly proper scoring rule** für den bedingten Erwartungswert
  unter der angenommenen Varianzstruktur — RMSE belohnt bei hoher Nullmasse das
  Vorhersagen von ~0 und trennt sinnvolle Modelle kaum (siehe die A/B-Diagnose in
  `BACKLOG.md`, Kandidat 11: RMSE-Spanne über Prädiktoren teils < 1 %, Devianz
  > 100 %; bei Tweedie noch drastischer, +0,4 % vs. +15497 % — `full_glm` hatte
  dort sogar einen SCHLECHTEREN RMSE als der nutzlose Konstant-Prädiktor, RMSE
  hätte also das bessere Modell verworfen).

**Generalisierte Frage** (Kandidat 11, verallgemeinert über Tweedie hinaus):
"ist mein Loss überhaupt die richtige Metrik?" ist bei JEDEM schiefen/
nullmassigen Ziel zu stellen, nicht nur bei Count-/Schadendaten - der Test
selbst ist einfach (vier naive Prädiktoren wie `near_zero`/`naive_mean`/
`null_offset`/`full` auf RMSE/MAE UND der eigentlichen Loss-Funktion
vergleichen; wenn RMSE kaum trennt, aber die Loss-Funktion klar rangiert, ist
RMSE der falsche Bewertungsmaßstab). Bisher nur an `tweet` bestätigt (1
Projekt) - kein generischer Code-Helfer, da der Test stark vom jeweiligen
Loss abhängt; der Denkansatz selbst ist aber uneingeschränkt übertragbar.

Devianz geht auf die GLM-Theorie von **Nelder & Wedderburn (1972)** zurück:
die (skalierte) Devianz ist −2× die Log-Likelihood-Differenz zwischen dem
gefitteten und dem saturierten Modell.

## 2. Exponential-Dispersions-Modelle und die Potenz-Varianzfunktion

Poisson, Gamma, Normal, Inverse-Gauss und die Tweedie-Familie sind alle
**Exponential-Dispersions-Modelle (EDM)** (Jørgensen 1987, 1997). Ein EDM ist
über seine **Varianzfunktion** `V(mu)` charakterisiert:

```
Var(Y) = phi * V(mu)
```

Die **Tweedie-Familie** ist der Spezialfall mit einer **Potenz-Varianzfunktion**

```
V(mu) = mu^p      (p = "Tweedie-Potenz", auch tweedie_variance_power)
```

Der Parameter `p` wählt das Familienmitglied:

| p | Verteilung | Träger |
|---|---|---|
| 0 | Normal | reell |
| (0,1) | — (existiert nicht) | — |
| 1 | Poisson | {0,1,2,…} |
| **(1,2)** | **Compound Poisson-Gamma** | **{0} ∪ (0,∞)** |
| 2 | Gamma | (0,∞) |
| 3 | Inverse Gauss | (0,∞) |

## 3. Warum "Tweedie" — und warum (1,2) zu Versicherungsdaten passt

Benannt nach **Maurice C. K. Tweedie** (1919–1996), britischer Statistiker/
Medizinphysiker, der diese Klasse in **Tweedie (1984)** charakterisierte. Den
**Namen** prägte **Bent Jørgensen** (ab 1987); Tweedie selbst nannte sie nicht so.

Der Bereich **1 < p < 2** ist die **Compound-Poisson-Gamma-Verteilung**: eine
Poisson-verteilte *Anzahl* von Gamma-verteilten *Beträgen*. Ergebnis ist eine
Variable mit **Punktmasse bei 0** (kein Schaden) **plus positiv-stetigem Teil**
(Schadenhöhe). Das ist exakt die Struktur von Schadenlast/Pure Premium — daher
ist Tweedie das Standardmodell im Nicht-Leben-Pricing (**Smyth & Jørgensen 2002**;
**Wüthrich & Merz 2023**). Grenzfälle: `p→1` reine Häufigkeit (Poisson),
`p→2` reine Höhe je Schaden (Gamma).

## 4. Unit-Devianz-Formeln (wie in `deviance_measures.R`)

Mittlere Unit-Devianz `d(y, mu)`, identisch zu sklearn
`mean_poisson_deviance` / `mean_tweedie_deviance`:

```
Poisson (p=1):  d = 2 * ( y*log(y/mu) - (y - mu) ),           0*log0 := 0
Tweedie (p!=1,2): d = 2 * ( y^(2-p)/((1-p)(2-p))
                            - y*mu^(1-p)/(1-p)
                            + mu^(2-p)/(2-p) )
Gamma  (p=2):   d = 2 * ( log(mu/y) + y/mu - 1 )
Normal (p=0):   d = (y - mu)^2
```

Für `1 < p < 2` gilt `2-p > 0`, also ist `y^(2-p) = 0` bei `y = 0` — die
**Nullmasse trägt endlich bei** (kein `log(0)`/`0^(neg)`-Problem wie bei p≥2).
Verifiziert gegen `glm()`-Residualdevianz in `test_deviance.R`.

## 5. Zwei Rollen von p — nicht verwechseln

`p` taucht an **zwei** Stellen auf:

1. **Modell** — `tweedie_variance_power` beim Training (nimmt die Varianzstruktur
   der Verteilung an). Lohnt zu tunen.
2. **Metrik** — die Potenz der Devianz bei der **Bewertung** (`p_eval`).

Der Devianz-**WERT** hängt stark von `p_eval` ab (in einem Fall ~11× über
p=1.1..1.9; niedriges p ⇒ frequenzgewichtet, hohes p ⇒ severitygewichtet).
**`p_eval` MUSS über alle verglichenen Modelle fix sein**, sonst ist der
Vergleich bedeutungslos. Das betrifft auch Studienvergleiche: eine Tweedie-D²/
Devianz-Zahl ist nur bei gleichem `p_eval` UND gleicher Ziel-Formulierung
(Betrag+Offset vs. Rate+Gewichte) rankbar.

## 6. Exposure als log-Offset

Beide Objectives nutzen den **log-Link**. Exposure `e` geht als **Offset**
`log(e)` in den linearen Prädiktor: `mu = e * exp(f(x))`. So modelliert man den
Erwartungswert *bei gegebener Exposure* (Rate × Exposure), statt Exposure als
Feature zu missbrauchen. Die Verdrahtung ist seit 2026-08-12 ein generischer
Template-Helfer (`add_log_offset(task, offset_col_name)` in `000_config.R`,
siehe `BACKLOG.md` Kandidat 10 für Details und die dokumentierte Grenze bei
LightGBM/CatBoost).

## 7. Durable Befunde (Kandidat 12, aus mehreren Sessions)

Kleinere, aber wiederholt relevante Lektionen, die keinen eigenen Code
brauchen, aber leicht vergessen werden:

- **Offset-Wirkung ist modellklassenabhängig, nicht universell.** Ein
  linearer GLM profitiert klar vom Offset (Poisson: passt exakt zum
  linearen Prädiktor). Ein flexibler Boost (LightGBM) profitiert bei
  Poisson kaum messbar (tweet: Δ0,0015 « Fold-SD 0,008) und kann bei
  Tweedie sogar SCHLECHTER werden (65,7 vs. 61,5, außerhalb der Streuung -
  Ursache: die multiplikative Rate-Korrektur `mu=Exposure·exp(f(x))`
  verstärkt Rauschen im niedrigen Exposure-Terzil). **Gegenprobe** (dataCar,
  2026-08-12): hier half der Offset LightGBM sehr wohl (~5 % Devianz-
  Verbesserung) - der Nutzen ist also nicht nur modell-, sondern auch
  DATENSATZABHÄNGIG. Konsequenz: den Offset generisch verfügbar machen und
  empirisch je Projekt prüfen, nicht pauschal annehmen oder verwerfen.
- **Referenzmodelle IMMER auf identischen Folds rechnen.** Ein Single-
  Split-GLM gegen ein 5-fach-CV-LightGBM verglichen drehte einmal das
  Ergebnis um - der scheinbare Gewinner war nur ein Splitting-Artefakt.
- **Externer Sanity-Check über D² (skaleninvariant), nicht die absolute
  Devianz.** Rate+Gewichte-Formulierung und Offset-Formulierung liegen auf
  verschiedenen Skalen - ein roher Devianz-Vergleich zwischen ihnen ist
  bedeutungslos, D² (relativ zum Null-Modell) ist es nicht.
- **Eine aggregierte Metrik-Verbesserung ist nicht automatisch eine
  Verbesserung für jede Teilfrage** (Ensemble-Selection-Session,
  2026-08-12, siehe [[project_count_tweedie_deviance]]): ein Ensemble kann
  die Gesamt-Devianz klar verbessern, obwohl es bei den seltenen,
  praktisch wichtigen Schadenzeilen sogar konservativer/schlechter ist als
  ein einfacheres Modell - weil die dominante Nullmasse den Durchschnitt
  bestimmt. Vor jedem Vertrauen in eine aggregierte Zahl bei einem schiefen
  Ziel: nach Teilpopulationen (hier y=0 vs. y>0) aufschlüsseln.

## 8. Literatur

- **Tweedie, M. C. K. (1984).** An index which distinguishes between some
  important exponential families. In *Statistics: Applications and New
  Directions* (Ghosh & Roy, Hrsg.), 579–604. Indian Statistical Institute.
- **Jørgensen, B. (1987).** Exponential dispersion models (with discussion).
  *JRSS B* 49(2), 127–162. — prägt den Namen "Tweedie".
- **Jørgensen, B. (1997).** *The Theory of Dispersion Models.* Chapman & Hall.
- **Nelder, J. A. & Wedderburn, R. W. M. (1972).** Generalized linear models.
  *JRSS A* 135(3), 370–384. — Devianz/GLM.
- **Smyth, G. K. & Jørgensen, B. (2002).** Fitting Tweedie's compound Poisson
  model to insurance claims data. *ASTIN Bulletin* 32(1), 143–157.
- **Dunn, P. K. & Smyth, G. K. (2005).** Series evaluation of Tweedie exponential
  dispersion model densities. *Statistics and Computing* 15, 267–280. — Basis des
  R-Pakets `tweedie`; `statmod::tweedie()` liefert die GLM-Familie.
- **Noll, A., Salzmann, R. & Wüthrich, M. V. (2018).** Case Study: French Motor
  Third-Party Liability Claims. *SSRN 3164764* — der freMTPL2-Benchmark.
- **Wüthrich, M. V. & Merz, M. (2023).** *Statistical Foundations of Actuarial
  Learning and its Applications.* Springer (Open Access).
- **scikit-learn**: `mean_tweedie_deviance` / Beispiele "Tweedie regression on
  insurance claims" und "Poisson regression and non-normal loss".
