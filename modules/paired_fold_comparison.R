# =====================================================================
# paired_fold_comparison.R -- generischer Helfer fuer die "paired
# same-folds"-Vergleichsmethodik (BACKLOG.md Kandidat 6 und seither
# wiederholt: Kandidat 8/30).
# =====================================================================
# Disziplin: JEDE Variante (Feature-Set, Learner-Objective, Residual- vs.
# Direktmodell, ...) wird auf DENSELBEN, einmal instanziierten Folds
# gemessen - ein Vergleich gegen eine Zahl aus einem separat gesplitteten
# Lauf ist nicht interpretierbar (Fold-Rauschen ueberdeckt kleine Effekte).
#
# Herkunft: dieses Muster wurde in `028_feature_blocks.R` (Kandidat 6),
# `031_residualization.R` (Kandidat 8) und `034_robust_loss_functions.R`
# (Kandidat 30) jeweils per Hand neu geschrieben - fast identischer Code,
# 3x. Genau die Lehre aus dem `combined_task_helper.R`-Fund (BACKLOG.md
# Kandidat 26): wiederholter Code ist eine Falle, nur ein wiederverwend-
# barer Baustein verhindert das zuverlaessig.
#
# `variant_fn` traegt bewusst die GESAMTE Fold-Logik (Task-Zugriff,
# Learner-Training, Vorhersage, ggf. Zusatzschritte wie eine leckagefreie
# Klimatologie) - NICHT als task+learner-Paar erzwungen, damit auch
# komplexere Varianten wie Residualisierung (eigenes Fold-Target, eigene
# Vorhersage-Rekonstruktion) hineinpassen, nicht nur "derselbe Task,
# anderer Learner".

#' Extrahiert Train-/Test-Row-Ids aus EINEM instanziierten mlr3-Resampling,
#' fuer die wiederholte Wiederverwendung ueber mehrere Varianten hinweg
#' (umgeht mlr3s Task-Hash-Check bei feature-gefilterten Task-Klonen -
#' siehe `setup-panel-forecast-project`-Skill).
#'
#' @param resampling Ein bereits `$instantiate()`tes mlr3-Resampling
#'   (z.B. `make_resampling(task, "time_blocked", ...)`).
#' @return Liste (eine je Fold) mit `train`/`test` Row-Id-Vektoren.
extract_folds <- function(resampling) {
  stopifnot("resampling muss bereits instanziiert sein ($instantiate())" = resampling$is_instantiated)
  lapply(seq_len(resampling$iters), function(i)
    list(train = resampling$train_set(i), test = resampling$test_set(i)))
}

#' Fuehrt EINE Variante ueber ALLE Folds aus.
#'
#' @param folds Rueckgabe von `extract_folds()`.
#' @param variant_fn `function(train_ids, test_ids)` -> benannter
#'   numerischer Vektor (eine oder mehrere Metriken je Fold, IMMER
#'   dieselben Namen/Laenge ueber alle Folds).
#' @return `matrix` (Folds x Metriken).
run_variant_on_folds <- function(folds, variant_fn) {
  per_fold <- lapply(folds, function(f) variant_fn(f$train, f$test))
  res <- do.call(rbind, per_fold)
  rownames(res) <- seq_along(folds)
  res
}

#' Paarweiser Delta (Variante - Baseline) je Metrik, mit SD/Ratio.
#'
#' @param baseline,variant `matrix`-Rueckgaben von `run_variant_on_folds()`
#'   auf DENSELBEN Folds (gleiche Zeilenanzahl/-reihenfolge vorausgesetzt).
#' @param metrics Zu vergleichende Spaltennamen (Default: alle in beiden
#'   Matrizen gemeinsamen Spalten).
#' @param label Bezeichnung der Variante fuer die Ergebnistabelle.
#' @return `data.table` mit `delta` = mean(variant - baseline) je Fold,
#'   `sd_fold_delta`, `ratio` = `delta / sd_fold_delta`. Bei einer
#'   "kleiner ist besser"-Metrik (z.B. RMSE) ist ein positives `delta`
#'   eine Verschlechterung. `|ratio| > ~2` gilt als klar ueber dem
#'   Fold-zu-Fold-Rauschen (siehe `BACKLOG.md`-Disziplin Kandidat 6).
paired_fold_delta <- function(baseline, variant, metrics = NULL, label = "variant") {
  stopifnot("baseline und variant muessen auf denselben Folds (gleiche Zeilenanzahl) beruhen" = nrow(baseline) == nrow(variant))
  if (is.null(metrics)) metrics <- intersect(colnames(baseline), colnames(variant))
  data.table::rbindlist(lapply(metrics, function(m) {
    d <- variant[, m] - baseline[, m]
    data.table::data.table(vergleich = label, metrik = m,
                           delta = mean(d), sd_fold_delta = stats::sd(d),
                           ratio = mean(d) / stats::sd(d))
  }))
}
