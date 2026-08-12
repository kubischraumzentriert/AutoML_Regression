rm(list = ls())

suppressPackageStartupMessages({
  library(data.table)
  library(mlr3)
  library(mlr3extralearners)
})

source("000_config.R")

set.seed(seed)
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# Target-Leak-Audit
# =============================================================================
# Eine zu gute Baseline auf einer schweren Aufgabe ist ein Warnsignal, kein
# Erfolg. WICHTIG: CV<->Leaderboard-Uebereinstimmung faengt einen Leak NICHT -
# das Artefakt steckt meist auch in den Testdaten, ein Leak taeuscht also
# konsistent hohe CV- UND LB-Werte vor. Nur ein Feature-Audit deckt das auf.
# Zurueckgefuehrt aus dem Klassifikations-Template (dort an African-Credit-
# Scoring bestaetigt: eine naive F1-0.88-Baseline auf 1.8% positiver Klasse
# war ein Ex-post-Leak; nach Bereinigung F1 ~0.41, extern am Leaderboard fast
# exakt bestaetigt). Vier von fuenf Schritten sind automatisiert, Schritt 5
# (Verfuegbarkeit zur Entscheidungszeit) bleibt fachliches Urteil.
#
# Schritt 2 (Determinismus) ist fuer STETIGE Ziele adaptiert: statt
# P(Klasse|Wert) in {0,1} wird geprueft, ob die Zielstreuung INNERHALB einer
# Wertgruppe nahe Null ist relativ zur Gesamtstreuung - das Feature "pinnt"
# den Zielwert dann nahezu fest.
#
# Bewusst OHNE subset_fraction: Determinismus-/Stratum-Befunde brauchen
# Volumen - ein Subset kann seltene Gruppen unterrepraesentieren und sogar das
# Vorzeichen eines Befunds verfaelschen (dieselbe Screening-Falle wie bei
# exact-value Target-Encoding im Klassifikations-Template).
cat("=== Target-Leak-Audit ===\n")
cat("Eine zu gute Baseline auf einer schweren Aufgabe ist ein Warnsignal, kein\n")
cat("Erfolg. CV<->Leaderboard-Uebereinstimmung faengt einen Leak NICHT (das\n")
cat("Artefakt steckt meist auch in den Testdaten).\n\n")

train <- fread(train_path)
if (id_col %in% names(train)) train[, (id_col) := NULL]

char_cols <- names(train)[vapply(train, is.character, logical(1))]
train[, (char_cols) := lapply(.SD, as.factor), .SDcols = char_cols]
# Datumsspalten (Date/IDate/POSIXct, z.B. aus fread()) werden von mlr3-Tasks
# nicht unterstuetzt -> numerisch (Tage/Sekunden seit Epoch) statt fallenlassen,
# ein Datum kann selbst leak-relevant sein (z.B. "erfasst am" nach dem Ausgang).
date_cols <- names(train)[vapply(train, function(x) inherits(x, c("Date", "IDate", "POSIXct")), logical(1))]
train[, (date_cols) := lapply(.SD, as.numeric), .SDcols = date_cols]
train[, (target_col) := as.numeric(get(target_col))]

# LightGBM verarbeitet fehlende Werte und Faktoren nativ, daher ohne
# Imputations-Pipeline - vereinfacht auch den Zugriff auf importance().
task_full <- as_task_regr(train, target = target_col, id = "leak_audit")
feature_cols <- task_full$feature_names
target_vals <- train[[target_col]]
target_sd <- sd(target_vals, na.rm = TRUE)

# --- Schritt 1: Feature-Importance-Konzentration ----------------------------
cat("=== Schritt 1: Feature-Importance-Konzentration ===\n")
learner_imp <- lrn("regr.lightgbm", num_iterations = 200)
learner_imp$train(task_full)
imp <- learner_imp$importance()
importance_dt <- data.table(feature = names(imp), gain = as.numeric(imp))
importance_dt[, share := gain / sum(gain)]
setorder(importance_dt, -share)
fwrite(importance_dt, leak_audit_importance_path)
print(importance_dt)

suspects_importance <- importance_dt[share > leak_audit_importance_share_threshold, feature]
if (length(suspects_importance) > 0) {
  cat(sprintf(
    "\nWARNUNG: %s traegt/tragen ueber %.0f%% der Gain-Importance - genauer pruefen.\n",
    paste(suspects_importance, collapse = ", "), leak_audit_importance_share_threshold * 100
  ))
} else {
  cat(sprintf(
    "\nKein Feature traegt ueber %.0f%% der Gain-Importance.\n",
    leak_audit_importance_share_threshold * 100
  ))
}

# --- Kumulative Top-k-Erweiterung eines BESTEHENDEN Verdachts (Punkt 13) ----
# Der Einzelfeature-Check oben uebersieht einen Leak-PARTNER, der knapp unter
# der Einzelschwelle liegt (Anlass: bike-sharing-Leak `casual`+`registered`==
# `count` - `registered` allein ueber der Einzelschwelle, `casual` mit ~5%
# knapp darunter, blieb bisher im "ehrlichen" Feature-Set stehen).
#
# WICHTIG: dieser Check laeuft NUR, wenn Schritt 1 bereits mindestens einen
# Einzelverdaechtigen gefunden hat - er ERWEITERT einen bestehenden Verdacht,
# er ERZEUGT keinen neuen aus einer sauberen Verteilung. Ohne diese Bedingung
# markiert der Check faelschlich die staerksten LEGITIMEN Features als
# verdaechtig, sobald wenige Features gemeinsam den Grossteil der Importance
# tragen (empirisch beobachtet: road-accident-risk hat 3 legitime Features,
# die zusammen 88% der Importance tragen, keins einzeln ueber 50% - ohne diese
# Bedingung waeren sie faelschlich geflaggt worden). Nur die fuehrenden
# `leak_audit_cumulative_max_k` Features werden ueberhaupt betrachtet.
importance_dt[, cum_share := cumsum(share)]
if (length(suspects_importance) == 0) {
  suspects_cumulative <- character(0)
  cat("Kein Feature ueber der Einzelschwelle - kumulative Erweiterung uebersprungen (kein Ausgangsverdacht, siehe Kommentar oben).\n")
} else {
  top_k_candidates <- importance_dt[seq_len(min(leak_audit_cumulative_max_k, nrow(importance_dt)))]
  crossing_idx <- which(top_k_candidates$cum_share > leak_audit_cumulative_share_threshold)
  suspects_cumulative <- if (length(crossing_idx) > 0) {
    top_k_candidates$feature[seq_len(min(crossing_idx))]
  } else {
    character(0)
  }
  new_cumulative_suspects <- setdiff(suspects_cumulative, suspects_importance)
  if (length(new_cumulative_suspects) > 0) {
    cat(sprintf(
      "WARNUNG: zusammen mit dem/den bereits verdaechtigen Feature(s) tragen die fuehrenden %d Feature(s)\n",
      length(suspects_cumulative)
    ))
    cat(sprintf(
      "  (%s) ueber %.0f%% der Gain-Importance - %s NEU gegenueber der Einzelschwelle,\n",
      paste(suspects_cumulative, collapse = ", "), leak_audit_cumulative_share_threshold * 100,
      paste(new_cumulative_suspects, collapse = ", ")
    ))
    cat("  Verdacht auf ein Leak-PAAR/eine Leak-GRUPPE (nicht nur ein Einzelfeature).\n")
  } else {
    cat(sprintf(
      "Kumulative Top-%d-Schwelle (%.0f%%) bestaetigt nur die bereits per Einzelschwelle Verdaechtigen - kein Zusatzbefund.\n",
      length(suspects_cumulative), leak_audit_cumulative_share_threshold * 100
    ))
  }
}

# --- Schritt 2: Determinismus (Zielstreuung je Wertgruppe) ------------------
# Nur Spalten mit ueberschaubarer Kardinalitaet (Kategorien oder kleine
# numerische Codes) - bei quasi-stetigen Spalten ist jeder Wert quasi
# eindeutig, "Determinismus" waere dort bedeutungslos.
cat("\n=== Schritt 2: Determinismus (Zielstreuung je Wertgruppe) ===\n")
low_card_cols <- feature_cols[vapply(feature_cols, function(c) {
  data.table::uniqueN(train[[c]]) <= leak_audit_cardinality_max
}, logical(1))]

compute_determinism <- function(col_name) {
  dt <- data.table(value = as.character(train[[col_name]]), target = target_vals)
  dt <- dt[!is.na(value)]
  agg <- dt[, .(n = .N, mean_target = mean(target, na.rm = TRUE), sd_target = sd(target, na.rm = TRUE)), by = value]
  agg[, feature := col_name]
  agg[, sd_ratio := ifelse(target_sd > 0, sd_target / target_sd, NA_real_)]
  agg[, .(feature, value, n, mean_target, sd_target, sd_ratio)]
}

if (length(low_card_cols) == 0) {
  # z.B. rein kontinuierliche Feature-Saetze ohne jede Spalte
  # <= leak_audit_cardinality_max - rbindlist(list()) haette hier eine
  # spaltenlose Tabelle erzeugt und den nachfolgenden Zugriff zum Absturz
  # gebracht, daher expliziter Kurzschluss statt stillem/kaputtem Leerfall.
  cat(sprintf(
    "Keine Spalte mit <= %d eindeutigen Werten - Schritt uebersprungen.\n",
    leak_audit_cardinality_max
  ))
  determinism_dt <- data.table(
    feature = character(0), value = character(0), n = integer(0),
    mean_target = numeric(0), sd_target = numeric(0), sd_ratio = numeric(0), flagged = logical(0)
  )
} else {
  determinism_dt <- rbindlist(lapply(low_card_cols, compute_determinism), fill = TRUE)
  determinism_dt[, flagged := !is.na(sd_ratio) & sd_ratio <= leak_audit_determinism_sd_ratio & n >= leak_audit_determinism_min_n]
  setorder(determinism_dt, -flagged, -n)
}
fwrite(determinism_dt, leak_audit_determinism_path)

flagged_determinism <- determinism_dt[flagged == TRUE]
if (nrow(flagged_determinism) > 0) {
  cat(sprintf(
    "WARNUNG: %d Wert-Gruppe(n) mit stark reduzierter Zielstreuung (SD-Ratio<=%.2f, n>=%d) gefunden:\n",
    nrow(flagged_determinism), leak_audit_determinism_sd_ratio, leak_audit_determinism_min_n
  ))
  print(flagged_determinism)
} else if (length(low_card_cols) > 0) {
  cat(sprintf(
    "Keine Wert-Gruppe mit n>=%d zeigt eine SD-Ratio <= %.2f.\n",
    leak_audit_determinism_min_n, leak_audit_determinism_sd_ratio
  ))
}
suspects_determinism <- unique(flagged_determinism$feature)

# --- Schritt 3: Within-Stratum-Korrelation (optional) -----------------------
# Prueft, ob ein verdaechtiges NUMERISCHES Feature auch INNERHALB derselben
# Stufe einer eigentlich neutralen kategorialen Spalte (leak_audit_stratify_cols)
# noch stark mit dem Ziel korreliert. Bleibt die Korrelation stratum-uebergreifend
# hoch, ist das Feature eher outcome- statt ex-ante-getrieben (der entscheidende
# Ex-post-Test). Braucht projektspezifisches Wissen, welche Spalte "neutral"
# sein sollte -> ohne Konfiguration wird dieser Schritt uebersprungen.
cat("\n=== Schritt 3: Within-Stratum-Korrelation ===\n")
numeric_cols <- feature_cols[vapply(train[, ..feature_cols], is.numeric, logical(1))]
numeric_suspects <- intersect(union(suspects_importance, suspects_cumulative), numeric_cols)

if (length(leak_audit_stratify_cols) == 0 || length(numeric_suspects) == 0) {
  cat("Uebersprungen (kein 'leak_audit_stratify_cols' konfiguriert oder keine\n")
  cat("numerischen Verdaechtigen aus Schritt 1).\n")
} else {
  stratum_dt <- rbindlist(lapply(numeric_suspects, function(nf) {
    rbindlist(lapply(leak_audit_stratify_cols, function(sc) {
      dt <- data.table(value = train[[sc]], feat = train[[nf]], target = target_vals)
      dt <- dt[!is.na(value) & !is.na(feat) & !is.na(target)]
      agg <- dt[, .(
        n = .N,
        mean_feature = mean(feat),
        cor_feature_target = if (.N >= 3) cor(feat, target) else NA_real_
      ), by = value]
      agg[, `:=`(numeric_feature = nf, stratify_col = sc)]
      agg
    }))
  }), fill = TRUE)
  fwrite(stratum_dt, leak_audit_stratum_path)
  print(stratum_dt)
  cat("\nGespeichert:", leak_audit_stratum_path, "\n")
  cat("Interpretation: bleibt die Korrelation zum Ziel INNERHALB der meisten\n")
  cat("Stratum-Stufen hoch, ist das Feature vermutlich outcome-getrieben statt\n")
  cat("ex-ante bekannt - manuelles Urteil, siehe README.\n")
}

# --- Schritt 4: Ehrlich-vs-aufgeblasen-Zerlegung -----------------------------
# Fairer, gepaarter Split (dieselben Zeilen fuer beide Varianten): einmal mit
# allen Features, einmal ohne die Verdaechtigen aus Schritt 1+2. Die Differenz
# quantifiziert, wieviel vom Score "Leak" statt echtes Signal war.
cat("\n=== Schritt 4: Ehrlich-vs-aufgeblasen-Zerlegung ===\n")
suspects <- head(Reduce(union, list(suspects_importance, suspects_cumulative, suspects_determinism)), leak_audit_suspect_top_n)

if (length(suspects) == 0) {
  cat("Keine verdaechtigen Features aus Schritt 1/2 - Audit unauffaellig,\n")
  cat("Zerlegung uebersprungen.\n")
} else {
  cat("Verdaechtige Features:", paste(suspects, collapse = ", "), "\n\n")

  holdout <- rsmp("holdout", ratio = validation_ratio)
  holdout$instantiate(task_full)
  train_ids <- holdout$train_set(1)
  test_ids <- holdout$test_set(1)

  task_reduced <- task_full$clone(deep = TRUE)
  task_reduced$select(setdiff(feature_cols, suspects))

  measures <- msrs(baseline_measure_ids)
  learner_dec <- lrn("regr.lightgbm", num_iterations = 200)

  score_task <- function(task) {
    l <- learner_dec$clone(deep = TRUE)
    l$train(task, row_ids = train_ids)
    pred <- l$predict(task, row_ids = test_ids)
    setNames(vapply(measures, function(m) pred$score(m), numeric(1)), baseline_measure_ids)
  }

  scores_full <- score_task(task_full)
  scores_reduced <- score_task(task_reduced)

  decomposition_dt <- as.data.table(rbind(scores_full, scores_reduced))
  decomposition_dt[, variante := c("mit Verdaechtigen (voll)", "ohne Verdaechtige")]
  setcolorder(decomposition_dt, c("variante", baseline_measure_ids))
  fwrite(decomposition_dt, leak_audit_decomposition_path)
  print(decomposition_dt)

  drop <- scores_full[[primary_measure_id]] - scores_reduced[[primary_measure_id]]
  cat(sprintf(
    "\n%s: voll=%.4f  ohne Verdaechtige=%.4f  Differenz=%.4f\n",
    primary_measure_id, scores_full[[primary_measure_id]], scores_reduced[[primary_measure_id]], drop
  ))
  cat("Ein grosser Abfall (bzw. Anstieg bei RMSE/MAE) bestaetigt, dass die\n")
  cat("verdaechtigen Features einen substanziellen Teil des Scores tragen - je\n")
  cat("nach Schritt-5-Urteil gehoert der ehrliche (reduzierte) Wert als\n")
  cat("realistische Erwartung, nicht der volle.\n")
  cat("\nGespeichert:", leak_audit_decomposition_path, "\n")
}

# --- Schritt 5: Verfuegbarkeit zur Entscheidungszeit (manuelles Urteil) -----
cat("\n=== Schritt 5: Verfuegbarkeit zur Entscheidungszeit (manuelles Urteil) ===\n")
if (length(suspects) > 0) {
  cat("Fuer jedes verdaechtige Feature (", paste(suspects, collapse = ", "), ") pruefen:\n", sep = "")
  cat("  - Ist der Wert zum Zeitpunkt der Vorhersage TATSAECHLICH bekannt (ex-ante),\n")
  cat("    oder haengt er vom Ausgang/einer spaeteren Entscheidung ab (ex-post)?\n")
  cat("  - Ist er nur DEFINITORISCH mit dem Ziel gekoppelt (z.B. strukturell an\n")
  cat("    dessen Berechnung beteiligt), statt inhaltlich prediktiv?\n")
  cat("  Nicht automatisierbar - siehe Klassifikations-Template-README\n")
  cat("  'Target-Leakage-Audit' fuer die drei Kategorien (Ex-post-Leak /\n")
  cat("  definitorisch gekoppelt / legitim ex-ante) und den Praezedenzfall.\n")
} else {
  cat("Keine Verdaechtigen aus Schritt 1/2 - kein manuelles Urteil noetig.\n")
}

cat("\nGespeichert:\n")
cat("Importance    :", leak_audit_importance_path, "\n")
cat("Determinismus :", leak_audit_determinism_path, "\n")
if (length(leak_audit_stratify_cols) > 0 && length(numeric_suspects) > 0) {
  cat("Within-Stratum:", leak_audit_stratum_path, "\n")
}
