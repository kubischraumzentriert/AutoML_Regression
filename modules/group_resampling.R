suppressPackageStartupMessages({ library(mlr3); library(data.table) })

# ============================================================================
# Group-aware Resampling - generischer Baustein (classif & regr).
# Fuer Aufgaben, deren Ziel die Generalisierung auf NEUE Entitaeten ist (neue
# Patienten/Nutzer/Geraete/Molekuele), wobei dieselbe Entitaet in mehreren Zeilen
# vorkommt. Zufaellige CV memoriert die Entitaet und UEBERSCHAETZT massiv; group-CV
# (alle Zeilen einer Gruppe im selben Fold) gibt die ehrliche Zahl.
# ============================================================================

# Setzt group_col als Rolle "group" (und entfernt sie aus den Features). Danach
# haelt rsmp("cv") alle Zeilen einer Gruppe zusammen (GroupKFold).
set_group_role <- function(task, group_col) {
  task <- task$clone(deep = TRUE)
  task$col_roles$feature <- setdiff(task$col_roles$feature, group_col)
  task$col_roles$group <- group_col
  task
}

# Diagnose: random-CV vs group-CV auf DERSELBEN Aufgabe. Grosse Luecke => die
# Aufgabe ist gruppen-sensitiv, random-CV ueberschaetzt die Generalisierung auf
# neue Gruppen -> fuer den Deployment-Fall "neue Entitaet" die group-CV-Zahl nehmen.
# task_grouped: eine mit set_group_role() vorbereitete Aufgabe.
diagnose_group_cv <- function(task_grouped, learner, measure, folds = 5, seed = 42) {
  gcol <- task_grouped$col_roles$group
  stopifnot(length(gcol) == 1)
  # random-Variante: group-Rolle entfernen -> group_col ist rollenlos (kein Feature,
  # keine Gruppe) und wird ignoriert -> zufaellige CV.
  t_rand <- task_grouped$clone(deep = TRUE); t_rand$col_roles$group <- character(0)
  set.seed(seed); s_rand <- resample(t_rand, learner$clone(deep = TRUE), rsmp("cv", folds = folds))$aggregate(measure)
  set.seed(seed); s_grp <- resample(task_grouped, learner$clone(deep = TRUE), rsmp("cv", folds = folds))$aggregate(measure)
  data.table(measure = measure$id, random_cv = round(s_rand, 4), group_cv = round(s_grp, 4),
             gap = round(unname(s_grp - s_rand), 4))
}

# Permutationstest: traegt eine VERMUTETE Gruppenspalte (aus Weltwissen, z.B. "das
# ist eine Patienten-ID") echte Struktur - oder ist sie statistisch nicht von einer
# beliebigen Aufteilung gleicher Groesse zu unterscheiden? Billiger Vortest VOR
# diagnose_group_cv() (nur Varianzzerlegung, kein Modelltraining) - die
# Nullverteilung wird durch tatsaechliches Mischen der Labels erzeugt, nicht per
# Formel angenommen.
#
# Teststatistik eta^2 (Anteil der Gesamtvarianz von `target`, den die
# Gruppenzugehoerigkeit erklaert - klassische Varianzzerlegung hinter der
# One-Way-ANOVA/F-Statistik): SS_zwischen / SS_gesamt.
#
# target: numerischer Vektor. group: Vektor/Faktor gleicher Laenge (zu testende
# Gruppierung). n_perm: Anzahl Permutationen fuer die Nullverteilung.
# Rueckgabe: list(eta2_observed, p_value, eta2_null) - eta2_null fuer eigene
# Diagnostik/Histogramme.
#
# ADR-003: an 2 unabhaengigen Projekten bestaetigt (SubjektDatensatz/Parkinson-
# Telemonitoring, AStepAheadOfdrought/Klima-Panel) - siehe
# REFERENZ_GROUP_AWARE_CV.md fuer Theorie/Herkunft/Zahlen.
.eta_squared <- function(y, g) {
  total_ss <- sum((y - mean(y))^2)
  between_ss <- sum(tapply(y, g, function(yi) length(yi) * (mean(yi) - mean(y))^2))
  between_ss / total_ss
}

test_group_significance <- function(target, group, n_perm = 999, seed = 42) {
  stopifnot(length(target) == length(group), n_perm >= 1)
  obs <- .eta_squared(target, group)
  set.seed(seed)
  # sample(group) permutiert nur die ZUORDNUNG Zeile->Label - die Gruppengroessen
  # (Multiset der Label-Haeufigkeiten) bleiben exakt erhalten, nur wer zu welcher
  # Pseudo-Gruppe gehoert wird zufaellig. Das simuliert "gleiche Gruppengroessen,
  # aber keine echte Entitaetsstruktur".
  eta2_null <- vapply(seq_len(n_perm), function(i) .eta_squared(target, sample(group)), numeric(1))
  # Einseitiger p-Wert (echte Gruppenstruktur kann eta^2 nur erhoehen, nie senken) -
  # +1/+1-Korrektur (Davison & Hinkley 1997): der beobachtete Wert zaehlt selbst
  # als eine von n_perm+1 moeglichen Anordnungen, verhindert p=0.
  p_value <- (1 + sum(eta2_null >= obs)) / (n_perm + 1)
  list(eta2_observed = obs, p_value = p_value, eta2_null = eta2_null)
}

# Kandidaten-Scan: wendet test_group_significance() auf mehrere Spalten an, um
# einen Verdacht ("koennte X eine echte Gruppe/Entitaet sein?") zu priorisieren.
# BEWUSST kein Standard-Pipeline-Schritt - nur bei konkretem Verdacht gezielt
# aufrufen (z.B. eine ID-artige Spalte im Rohdatensatz), sonst blaeht das den
# Workflow unnoetig auf (viele Spalten x viele Permutationen ist nicht billig).
#
# eta^2/p-Wert allein reichen NICHT: eine niedrig-kardinale Spalte (z.B.
# Geschlecht) kann signifikant sein, ohne ein Gruppen-Risiko zu sein - es gibt
# keine "neuen" Level, auf die man generalisieren muesste. `moegliche_entitaet`
# filtert deshalb zusaetzlich auf Kardinalitaet (genug verschiedene Level, aber
# nicht quasi-eindeutig je Zeile). Das reduziert offensichtliche Fehlalarme,
# ERSETZT aber nicht die menschliche semantische Pruefung - eine geschlossene
# Kategorie (z.B. 6 echte Auspraegungen) oder eine GETEILTE Zeitachse (viele
# Level, aber keine wiederholbare Entitaet - bestaetigt an AStepAheadOfdrought:
# `time` wird trotz fehlender echter Entitaetsstruktur markiert) koennen den
# Filter trotzdem durchrutschen. Siehe REFERENZ_GROUP_AWARE_CV.md Abschnitt
# "Grenzen" fuer beide dokumentierten Faelle.
#
# data: data.table. target_col: Zielspalte. candidate_cols: zu pruefende
# Spalten (Default: alle character/factor/niedrig-aufloesende integer Spalten
# ausser target_col). min_cardinality/max_cardinality_ratio: Kardinalitaets-
# Filter fuer `moegliche_entitaet` (Level >= min_cardinality UND Level/n <=
# max_cardinality_ratio).
scan_group_candidates <- function(data, target_col, candidate_cols = NULL,
                                   n_perm = 999, seed = 42,
                                   min_cardinality = 5, max_cardinality_ratio = 0.3) {
  n <- nrow(data)
  if (is.null(candidate_cols)) {
    is_cat <- vapply(data, function(x) {
      (is.character(x) || is.factor(x) || is.integer(x)) && length(unique(x)) < n
    }, logical(1))
    candidate_cols <- setdiff(names(data)[is_cat], target_col)
  }
  res <- lapply(candidate_cols, function(cc) {
    grp <- data[[cc]]
    card <- length(unique(grp))
    test <- test_group_significance(data[[target_col]], grp, n_perm = n_perm, seed = seed)
    data.table(
      column = cc, cardinality = card, cardinality_ratio = round(card / n, 4),
      avg_group_size = round(n / card, 1), eta2 = round(test$eta2_observed, 4),
      p_value = round(test$p_value, 4),
      moegliche_entitaet = test$p_value < 0.05 && card >= min_cardinality &&
        (card / n) <= max_cardinality_ratio)
  })
  out <- rbindlist(res)
  setorder(out, p_value, -eta2)
  out
}
