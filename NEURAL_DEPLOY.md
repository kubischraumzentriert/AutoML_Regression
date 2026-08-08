# Neuronale Modelle: R-Entwicklung, Python-GPU-Export

Policy fuer neuronale Tabellen-Modelle (v. a. FT-Transformer) als Ensemble-
Diversitaet. **Dieses Repo bleibt R-only.** Python ist keine Abhaengigkeit,
sondern ein duenner, wegwerfbarer Deploy-Export ganz am Schluss.

Zurueckgefuehrt aus dem Klassifikations-Template (`kubischraumzentriert/AutoML`,
`NEURAL_DEPLOY.md` dort) - die Policy und die dokumentierte R+GPU-Sackgasse sind
aufgabentyp-unabhaengig, gelten fuer Regression identisch.

## Grundregel

> Alles in R entwickeln und entscheiden (mlr3, mlr3torch, r-torch) - inklusive
> eines FT-Transformer-PROTOTYPS auf einem Sample zur Diversitaets-Pruefung.
> **Erst wenn** der R-Prototyp zeigt, dass das neuronale Modell von den GBMs
> **dekorreliert** ist (Korrelation ~0.9x statt ~0.99) **und** hilft, EIN
> self-contained Python-Script fuer Kaggle-GPU erzeugen - als Export, nicht ins
> Repo committet. Vorlage re-parametrisieren, nicht neu schreiben.

## Warum diese Trennung

- **R = Oekosystem und Entscheidungen.** Exploration, Devianz-/Signal-
  Diagnostik, CV, Modellwahl, Parameter-Suche und der FT-Prototyp (mlr3torch
  `lrn("regr.ft_transformer")`, lokal/CPU auf einem Sample) laufen hier.
- **Python = nur der GPU-Lauf.** Der einzige Punkt, an dem R praktisch versagt,
  ist **Kaggle + GPU + neuronal**. Der R-Weg dort ist eine mehrfache Sackgasse
  (siehe unten, am Klassifikations-Projekt s6e8 dokumentiert). Python mit
  vorinstalliertem torch(+CUDA) ist der begehbare Weg.

## Ablauf

1. **In R (dieses Repo):** GBMs (LightGBM/XGBoost/CatBoost) tunen, Features/
   Offset/Devianzmetrik festlegen, per CV die Zielmetrik optimieren. Wenn die
   GBMs zu korreliert sind (Blend gibt kaum mehr her), einen FT-Transformer-
   Prototyp (`lrn("regr.ft_transformer")`, Sample/CPU) bauen und die
   **Korrelation zu den GBMs** + Zielmetrik pruefen.
2. **Gate:** Nur weiter, wenn der Prototyp dekorreliert (~0.9x) UND konkurrenzfaehig
   genug ist. Sonst kein neuronales Modell - die GBMs sind dann ausgereizt.
3. **Export:** Ein Python-Deploy-Script re-parametrisieren, nicht neu schreiben.
   Ausgangs-Vorlage (aus dem Klassifikations-Projekt, Struktur uebertraegt sich):
   `C:\Users\HP\ML_Learning\predictingsmartphoneAddiction_s6e8\s6e8_blend_ft_kaggle.py`
   (Blend aus LightGBM+XGBoost+CatBoost+FT-Transformer, `SAMPLE_FRAC`/Device-
   Auto-Detect). Fuer Regression anpassen: `BCEWithLogitsLoss` -> `MSELoss` (bzw.
   die passende Devianz, falls Poisson/Tweedie-Ziel - siehe `DEVIANCE_MEASURES.md`),
   Sigmoid-Ausgabekopf entfaellt, GBM-Learner auf `LGBMRegressor`/`XGBRegressor`/
   `CatBoostRegressor` umstellen, Rang-Average-Blend durch Mittelwert-Blend
   ersetzen (Regression hat keine Rang-Invarianz-Eigenschaft wie AUC).
4. **Kaggle:** Python-Notebook, GPU-Accelerator an, Daten anhaengen, erst mit
   `SAMPLE_FRAC=0.05` schnelltesten (laeuft in Minuten, `device=cuda` pruefen),
   dann `SAMPLE_FRAC=1.0` fuer die echte Submission.

## Was 1:1 uebertraegt - und was nur ungefaehr

**Exakt** (R -> Python):
- **GBM-Parameter** - lightgbm/xgboost/catboost sind in R UND Python DIESELBEN
  Bibliotheken, die getunten Werte gelten unveraendert.
- Feature-/Offset-/Modell-Entscheidungen, und das Urteil "lohnt sich ein
  neuronales Modell ueberhaupt?".

**Nur ungefaehr:**
- Die **FT-Transformer-Architektur/Hyperparameter**. mlr3torch-FT (R) und ein
  hand-gerollter PyTorch-FT (Python) sind NICHT dasselbe Modell - die in R
  "gefundenen" FT-Params sind ein Richtwert, kein Transfer. Deshalb muss die
  Python-FT beim Export SELBST kurz validiert werden: ein Holdout-Vergleich
  (Einzelmodelle + Blend, mit/ohne FT) VOR der Submission.

## Kaggle-Umgebung (Python)

- Vorinstalliert auf GPU-Images: `torch`(+CUDA), `lightgbm`, `xgboost`,
  `catboost`, `pandas`, `numpy`, `scikit-learn` - **kein pip/Internet noetig**.
- Ein self-contained FT-Transformer (reines PyTorch, ~80 Zeilen) braucht keine
  `rtdl`-Abhaengigkeit -> laeuft auch bei Internet-aus.
- Nur der FT-Transformer nutzt die GPU; die GBMs laufen auf CPU (robust, keine
  GPU-Parameter-Versionsfallen).

## Warum NICHT der R-Weg auf Kaggle (dokumentierte Sackgasse, Klassifikations-Projekt s6e8)

Der Versuch, `mlr3torch`-FT direkt auf Kaggle+GPU zu fahren, scheiterte dreifach:
1. **Versionsskew**: Kaggles `mlr3misc` (0.16) zu alt fuer das neue
   `mlr3pipelines` (braucht >= 0.17). Fix nur mit ganzem mlr-Stack aus
   `mlr-org.r-universe.dev` + Kernel ZWEIMAL neu starten (alte geladene
   Namespaces kleben sonst).
2. **libtorch-Download 404**: `torch::install_torch()` waehlte fuer libtorch
   2.8.0 die Variante `cu117` - diesen Build gibt es nicht (404).
3. **GPU gar nicht an**: `nvidia-smi` fehlte, weil der Accelerator nicht
   eingeschaltet war.

Konsequenz: fuer neuronale Modelle auf Kaggle-GPU **Python nehmen**, nicht R.
Diese Sackgasse ist bislang nur am Klassifikations-Template dokumentiert -
noch keine unabhaengige Regressions-Bestaetigung, aber der Mechanismus (R-
Paket-Oekosystem auf Kaggle, nicht der Aufgabentyp) ist identisch.

## Bisheriger Ergebnis-Beleg (nur Klassifikation, noch keine Regressions-Bestaetigung)

Klassifikations-Projekt s6e8 (AUC): LightGBM+TE `0.96731` -> 3-GBM-Blend
`0.96775` -> +FT-Transformer (Python/GPU) `0.96810`. Der dekorrelierte FT
holte `+0.00035`, was die zu 0.99 korrelierten GBMs nicht konnten - die
Diversitaets-These bestaetigt. **Fuer Regression steht diese Bestaetigung noch
aus** - die Policy wird hier vorsorglich uebernommen (die zugrunde liegende
Kaggle-R-GPU-Sackgasse ist aufgabentyp-unabhaengig), aber ohne eigene
Regressions-Zahlen. Bei der ersten Regressions-Anwendung diesen Abschnitt mit
echten Werten ergaenzen.

## Querverweis: CPU-Laufzeit-Beleg gegen Voll-Training (nur Klassifikation, s6e8, 2026-08-08)

Ebenfalls noch ohne eigene Regressions-Bestaetigung, aber mechanismus-
unabhaengig vom Aufgabentyp (reine Torch-CPU-Trainingsgeschwindigkeit):
im Klassifikations-Template brauchte ein FT-Transformer-Prototyp fuer nur
15 Epochen/`d_token=64` auf 20% der s6e8-Daten bereits ~33 Minuten CPU-Zeit
- weit unter Kaggle-Produktionseinstellungen (40-80 Epochen, volle Daten),
hochgerechnet mehrere Stunden. Details, Zahlen und die daraus abgeleitete
30-Minuten-Faustregel siehe `NEURAL_DEPLOY.md` im Klassifikations-Template
sowie `adr/002-r-only-python-gpu-export.md` (hier wie dort). Gilt bis zur
ersten Regressions-eigenen Messung als plausibler Richtwert, nicht als
bestaetigte Zahl fuer Regressionsmodelle.
