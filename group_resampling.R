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
