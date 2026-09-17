# =============================================================================
# univariate_drift.R -- Univariate statistische Drift-Tests (Ergaenzung zur
# Adversarial Validation in 115_adversarial_validation.R).
# =============================================================================
# Herkunft: "Introducing MLOps" (Treveil/Dataiku 2020), Kap. 7 - Domain-
# Classifier (== unsere Adversarial Validation) und univariate Tests sind
# komplementaer, nicht redundant. Verifiziert an 2 unabhaengigen OpenML-
# Datensaetzen + 3 Szenarien (echter Zeit-Drift, Zufalls-Kontrolle,
# konstruierter Drift) - siehe TARGETS.md fuer Zahlen und Details.
#
# Je Feature: Kolmogorov-Smirnov-Test (stetig) oder Chi-Quadrat-Test
# (kategorial), mit Benjamini-Hochberg-Korrektur ueber alle Features
# (bei vielen Features/Zeilen wird sonst fast alles "statistisch
# signifikant" - siehe MLOps-Buch-Kaveat). Effektgroesse (KS-D bzw.
# Cramers V, beide 0-1) wird zusaetzlich zum p-Wert berichtet, da p-Werte
# allein bei grossen Datensaetzen triviale Abweichungen ueberbetonen.
#
# Mehrwert gegenueber der Adversarial-Validation-AUC allein: die AUC sagt
# nur "trennbar ja/nein/wie stark insgesamt", die univariaten Tests sagen
# WELCHE Features treiben (mit Effektgroesse je Feature) - im Sensitivitaets-
# test trennte die Adversarial-AUC z.B. nicht zwischen echtem Markt-Drift
# und stabiler Kalenderstruktur, die univariaten Tests taten es.

#' @param ref data.table/data.frame mit Referenz-Zeilen (z.B. Train)
#' @param new data.table/data.frame mit Vergleichs-Zeilen (z.B. Test), gleiche Spalten wie ref
#' @return data.table, sortiert nach p_adj_BH aufsteigend (staerkster Drift zuerst)
run_univariate_drift_tests <- function(ref, new) {
  stopifnot(identical(sort(names(ref)), sort(names(new))))
  cols <- names(ref)
  out <- vector("list", length(cols))
  for (i in seq_along(cols)) {
    cname <- cols[i]
    rv <- ref[[cname]]; nv <- new[[cname]]
    row <- tryCatch({
      if (is.numeric(rv)) {
        rv2 <- rv[!is.na(rv)]; nv2 <- nv[!is.na(nv)]
        if (length(rv2) < 2 || length(nv2) < 2 || (sd(rv2) == 0 && sd(nv2) == 0)) {
          data.table::data.table(feature = cname, type = "numeric (KS)", statistic = NA_real_,
                                  p_value = NA_real_, effect_size = "n/a (konstant/zu wenig Werte)")
        } else {
          t <- suppressWarnings(ks.test(rv2, nv2))
          data.table::data.table(feature = cname, type = "numeric (KS)",
                                  statistic = unname(t$statistic), p_value = t$p.value,
                                  effect_size = sprintf("D=%.3f", unname(t$statistic)))
        }
      } else {
        rv2 <- as.character(rv); rv2[is.na(rv2)] <- "__NA__"
        nv2 <- as.character(nv); nv2[is.na(nv2)] <- "__NA__"
        tab <- table(c(rv2, nv2), c(rep("ref", length(rv2)), rep("new", length(nv2))))
        if (nrow(tab) < 2) {
          data.table::data.table(feature = cname, type = "factor (Chi2)", statistic = NA_real_,
                                  p_value = NA_real_, effect_size = "n/a (nur 1 Auspraegung)")
        } else {
          t <- suppressWarnings(chisq.test(tab))
          n <- sum(tab); k <- min(nrow(tab) - 1, ncol(tab) - 1)
          cramers_v <- sqrt(unname(t$statistic) / (n * max(k, 1)))
          data.table::data.table(feature = cname, type = "factor (Chi2)",
                                  statistic = unname(t$statistic), p_value = t$p.value,
                                  effect_size = sprintf("CramersV=%.3f", cramers_v))
        }
      }
    }, error = function(e) {
      data.table::data.table(feature = cname, type = if (is.numeric(rv)) "numeric (KS)" else "factor (Chi2)",
                              statistic = NA_real_, p_value = NA_real_,
                              effect_size = paste("Fehler:", conditionMessage(e)))
    })
    out[[i]] <- row
  }
  res <- data.table::rbindlist(out)
  res$p_adj_BH <- stats::p.adjust(res$p_value, method = "BH")
  data.table::setorder(res, p_adj_BH, na.last = TRUE)
  res
}

#' Konsolen-Zusammenfassung + Speichern als CSV.
#' @param alpha Signifikanzschwelle NACH BH-Korrektur (Default 0.05).
report_univariate_drift <- function(ref, new, out_path, alpha = 0.05) {
  res <- run_univariate_drift_tests(ref, new)
  n_sig <- sum(res$p_adj_BH < alpha, na.rm = TRUE)
  cat(sprintf("\n=== Univariate Drift-Tests (KS/Chi2, BH-korrigiert, alpha=%.2f) ===\n", alpha))
  cat(sprintf("%d von %d Features signifikant drift-verdaechtig.\n", n_sig, nrow(res)))
  if (n_sig > 0) {
    cat("Top-Features nach Drift-Staerke:\n")
    print(res[p_adj_BH < alpha][, .(feature, type, effect_size, p_adj_BH)])
  } else {
    cat("Kein Feature zeigt signifikanten Drift - konsistent mit einer unauffaelligen Adversarial-Validation-AUC.\n")
  }
  data.table::fwrite(res, out_path)
  cat("Gespeichert:", out_path, "\n")
  invisible(res)
}
