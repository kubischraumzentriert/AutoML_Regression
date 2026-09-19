# =============================================================================
# feature_importance_stability.R -- ist die Gain-Importance-Rangfolge
# stabil ueber Folds/Seeds, oder Rauschen aus einem einzigen Lauf?
# =============================================================================
# Herkunft: Bestandsaufnahme 2026-09-14. `015_target_leak_audit.R` (und
# viele andere Diagnosen) verlassen sich auf `learner$importance()` aus
# EINEM einzigen Trainingslauf auf dem vollen Task - nie geprueft, ob
# diese Rangfolge selbst robust ist. Genau die Lehre aus Kandidat 27
# (bei grossem n wird fast alles "signifikant") uebertragen auf
# Feature-Importance: eine einzelne Zahl kann Rauschen sein, auch wenn
# sie plausibel aussieht. Dieses Modul prueft die Stabilitaet direkt,
# indem derselbe Learner-Typ ueber mehrere Folds/Seeds trainiert und die
# Importance-Rangfolgen paarweise verglichen werden (Spearman-Rang-
# korrelation + Top-k-Jaccard-Overlap).
#
# Baut auf `paired_fold_comparison.R`s `extract_folds()` auf (falls
# gesourct) - benutzt nur `$train`, importance() ist ein reines
# Trainingsartefakt, braucht keinen Test-Split.

#' Trainiert denselben Learner-Typ ueber mehrere Folds/Seeds, sammelt
#' `importance()` je Lauf in einer gemeinsamen Matrix.
#'
#' @param folds Liste von Listen mit mind. `$train` (Row-Ids) - z.B.
#'   `extract_folds()` aus `paired_fold_comparison.R`, oder eine eigene
#'   Liste `list(list(train = ids1), list(train = ids2), ...)`.
#' @param train_fn `function(train_ids)` -> ein TRAINIERTER mlr3-Learner
#'   mit `"importance"`-Property (z.B. `classif.lightgbm`/`regr.ranger`).
#' @return `matrix` (Features x Folds), fehlende Features in einem Lauf
#'   (z.B. nie gesplittet) werden als 0 gefuehrt, NICHT als NA - ein
#'   Feature, das ein Learner konsequent auf 0 Importance setzt, ist ein
#'   echtes (stabiles!) Ergebnis, kein fehlender Wert.
collect_importance_across_folds <- function(folds, train_fn) {
  imp_list <- lapply(folds, function(f) {
    lr <- train_fn(f$train)
    imp <- lr$importance()
    imp
  })
  all_features <- unique(unlist(lapply(imp_list, names)))
  mat <- matrix(0, nrow = length(all_features), ncol = length(folds),
                dimnames = list(all_features, seq_along(folds)))
  for (i in seq_along(imp_list)) {
    mat[names(imp_list[[i]]), i] <- imp_list[[i]]
  }
  mat
}

#' Paarweise Spearman-Rangkorrelation ueber alle Fold-Kombinationen.
#'
#' @param importance_matrix Rueckgabe von `collect_importance_across_folds()`.
#' @return Liste mit `pairwise` (`data.table`, eine Zeile je Fold-Paar)
#'   und `mean_correlation` (Mittelwert ueber alle Paare - nahe 1 =
#'   stabile Rangfolge, nahe 0 = praktisch zufaellig neu gemischt).
pairwise_rank_correlation <- function(importance_matrix) {
  n_folds <- ncol(importance_matrix)
  stopifnot("mindestens 2 Folds noetig fuer einen paarweisen Vergleich" = n_folds >= 2)
  combs <- utils::combn(n_folds, 2)
  rows <- lapply(seq_len(ncol(combs)), function(j) {
    a <- combs[1, j]; b <- combs[2, j]
    rho <- stats::cor(importance_matrix[, a], importance_matrix[, b], method = "spearman")
    data.table::data.table(fold_a = a, fold_b = b, spearman = rho)
  })
  pairwise <- data.table::rbindlist(rows)
  list(pairwise = pairwise, mean_correlation = mean(pairwise$spearman))
}

#' Paarweiser Jaccard-Overlap der Top-k-Feature-Mengen ueber alle
#' Fold-Kombinationen.
#'
#' @param k Groesse der "Top"-Menge (Default 10, oder alle Features
#'   falls weniger vorhanden).
#' @return Liste mit `pairwise` und `mean_jaccard` (1 = identische
#'   Top-k-Mengen in jedem Fold-Paar, 0 = keine Ueberschneidung).
pairwise_topk_overlap <- function(importance_matrix, k = 10) {
  n_folds <- ncol(importance_matrix)
  stopifnot("mindestens 2 Folds noetig fuer einen paarweisen Vergleich" = n_folds >= 2)
  k <- min(k, nrow(importance_matrix))
  topk_sets <- lapply(seq_len(n_folds), function(i)
    names(sort(importance_matrix[, i], decreasing = TRUE))[seq_len(k)])
  combs <- utils::combn(n_folds, 2)
  rows <- lapply(seq_len(ncol(combs)), function(j) {
    a <- combs[1, j]; b <- combs[2, j]
    inter <- length(intersect(topk_sets[[a]], topk_sets[[b]]))
    uni <- length(union(topk_sets[[a]], topk_sets[[b]]))
    data.table::data.table(fold_a = a, fold_b = b, jaccard = inter / uni)
  })
  pairwise <- data.table::rbindlist(rows)
  list(pairwise = pairwise, mean_jaccard = mean(pairwise$jaccard))
}

#' Report je Feature: mittlerer Rang, Rang-SD, Anteil der Folds mit
#' Top-k-Mitgliedschaft. Sortiert nach mittlerem Rang (bestes Feature
#' zuerst).
#'
#' @return `data.table` mit `feature`, `mean_rank`, `sd_rank`,
#'   `topk_share` (Anteil der Folds, in denen das Feature in den Top-k
#'   lag).
feature_importance_stability_report <- function(importance_matrix, k = 10) {
  k <- min(k, nrow(importance_matrix))
  n_folds <- ncol(importance_matrix)
  # Rang je Fold (1 = wichtigstes Feature), absteigend nach Importance.
  ranks <- apply(importance_matrix, 2, function(col) rank(-col, ties.method = "average"))
  topk_membership <- apply(ranks, 2, function(r) r <= k)
  res <- data.table::data.table(
    feature = rownames(importance_matrix),
    mean_rank = apply(ranks, 1, mean),
    sd_rank = apply(ranks, 1, stats::sd),
    topk_share = apply(topk_membership, 1, mean)
  )
  data.table::setorder(res, mean_rank)
  res
}
