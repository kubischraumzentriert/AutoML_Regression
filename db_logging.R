suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(uuid)
})

# Schwellenwertunabhaengige Metriken integrieren ueber alle Klassifikations-
# Schwellenwerte hinweg (z.B. AUC) - Post-hoc-Schwellenwert-Tuning (130/146)
# hat darauf KEINEN Effekt und kann komplett uebersprungen werden. Trainings-
# Klassengewichtung (105) hat dagegen einen kleineren, aber nicht garantiert
# null Effekt (aendert die Verlustfunktion beim Training selbst, nicht nur
# einen Cutoff danach) - empirisch bestaetigt in einem AUC-Projekt (siehe
# TEMPLATE_FRICTION.md von playground-series-s6e5): AUC blieb ueber
# power=0/0.5/1 im Rauschen (Spanne < 0.001), BAcc stieg deutlich (+5 Punkte).
# Schwellenwertabhaengige Metriken (BAcc, MCC, Accuracy, F1) profitieren
# typischerweise stark von beidem.
threshold_independent_measures <- c(
  "classif.auc", "classif.logloss", "classif.prauc",
  "classif.mauc_au1p", "classif.mauc_au1u", "classif.mauc_aunp", "classif.mauc_aunu"
)

is_threshold_independent_metric <- function(measure_id) {
  measure_id %in% threshold_independent_measures
}

# Gibt am Skriptanfang eine kurze Einschaetzung aus, ob sich der jeweilige
# Schritt fuer die aktuelle Zielmetrik (baseline_measure_ids[1]) lohnt -
# statt dass man das nur in Kommentaren/Doku nachlesen kann.
warn_if_threshold_step_low_value <- function(script_name, step_description) {
  primary_metric <- baseline_measure_ids[1]
  if (is_threshold_independent_metric(primary_metric)) {
    cat(
      "Hinweis (", script_name, "): Zielmetrik '", primary_metric, "' ist schwellenwert-",
      "unabhaengig - ", step_description, " hat hier vermutlich wenig/keinen Effekt ",
      "(siehe TARGETS.md-Backlog). Trotzdem sinnvoll, wenn eine explizite Bestaetigung ",
      "gewuenscht ist.\n",
      sep = ""
    )
  } else {
    cat(
      "Hinweis (", script_name, "): Zielmetrik '", primary_metric, "' ist schwellenwert-",
      "abhaengig - ", step_description, " ist hier relevant.\n",
      sep = ""
    )
  }
}

# Oeffnet (und legt bei Bedarf an) die Experiment-Tracking-SQLite-Datenbank.
# Fuehrt db_schema.sql aus (idempotent dank CREATE TABLE IF NOT EXISTS).
db_connect <- function(db_path = experiments_db_path) {
  con <- dbConnect(RSQLite::SQLite(), db_path)
  dbExecute(con, "PRAGMA foreign_keys = ON;")
  # WAL erlaubt gleichzeitige Leser/Schreiber besser als der Default-Modus,
  # busy_timeout laesst einen Writer auf einen kurz gesperrten Writer warten
  # statt sofort mit SQLITE_BUSY zu scheitern - relevant, wenn mehrere
  # Skripte parallel am Ende ihres Laufs in dieselbe DB loggen.
  dbExecute(con, "PRAGMA journal_mode = WAL;")
  dbExecute(con, "PRAGMA busy_timeout = 30000;")

  schema_sql <- paste(readLines(file.path(project_dir, "db_schema.sql"), warn = FALSE), collapse = "\n")
  statements <- Filter(function(s) nchar(s) > 0, trimws(strsplit(schema_sql, ";")[[1]]))
  for (stmt in statements) {
    dbExecute(con, stmt)
  }

  con
}

# Schaetzt grob die Laufzeit eines bevorstehenden CV-Laufs aus der zuletzt
# geloggten Holdout-Laufzeit desselben Algorithmus/Feature-Sets im selben
# Projekt - Faustregel: k-fache CV trainiert k Modelle auf einer zum
# Holdout-Trainingsanteil (validation_ratio) aehnlich grossen Trainingsmenge,
# also ungefaehr k x Holdout-Laufzeit. Nur eine grobe Vorab-Einschaetzung
# (in einem Testfall traf sie auf ~5s genau, Garantie ist das nicht) - soll
# VOR einem CV-/Tuning-Lauf mitgeteilt werden, nicht erst hinterher gemessen
# (siehe README, Abschnitt "Experiment-Tracking (SQLite)"/TARGETS.md-Backlog).
estimate_cv_runtime <- function(con, project_name, algorithm, folds, feature_set = "raw") {
  row <- dbGetQuery(
    con,
    "
    SELECT mr.mres_elapsed_seconds AS elapsed_seconds, r.run_started_at
    FROM metric_result mr
    JOIN model_config mc ON mc.mconf_id = mr.mres_mconf_id
    JOIN resampling rs ON rs.rsmp_id = mr.mres_rsmp_id
    JOIN run r ON r.run_id = mc.mconf_run_id
    JOIN workflow wf ON wf.wf_id = r.run_wf_id
    JOIN project p ON p.proj_id = wf.wf_proj_id
    WHERE p.proj_name = ? AND mc.mconf_algorithm = ? AND mc.mconf_feature_set = ?
      AND rs.rsmp_strategy = 'holdout' AND mr.mres_fold IS NULL
    ORDER BY r.run_started_at DESC
    LIMIT 1
    ",
    params = list(project_name, algorithm, feature_set)
  )

  if (nrow(row) == 0) {
    cat(
      "Keine geloggte Holdout-Laufzeit fuer Algorithmus '", algorithm,
      "' (feature_set='", feature_set, "') gefunden - keine Laufzeitschaetzung moeglich.\n",
      sep = ""
    )
    return(invisible(NA_real_))
  }

  holdout_seconds <- row$elapsed_seconds[1]
  estimate_seconds <- holdout_seconds * folds

  cat(
    "Laufzeitschaetzung fuer ", folds, "-fache CV (Algorithmus '", algorithm, "'): ~",
    round(estimate_seconds), "s (", round(estimate_seconds / 60, 1), " min), basierend auf letzter ",
    "Holdout-Laufzeit ", round(holdout_seconds, 1), "s vom ", row$run_started_at[1], ".\n",
    "Faustregel: k-fache CV ~ k x Holdout-Laufzeit (aehnlich grosse Trainingsmenge je Fold) - ",
    "grobe Schaetzung, keine Garantie.\n",
    sep = ""
  )

  invisible(estimate_seconds)
}

get_git_commit <- function() {
  result <- tryCatch(
    system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(e) NA_character_,
    warning = function(w) NA_character_
  )
  if (length(result) == 0 || !is.null(attr(result, "status"))) NA_character_ else result[1]
}

db_get_or_create_project <- function(con, name, description = NA_character_) {
  existing <- dbGetQuery(con, "SELECT proj_id FROM project WHERE proj_name = ?", params = list(name))
  if (nrow(existing) > 0) {
    return(existing$proj_id[1])
  }
  proj_id <- uuid::UUIDgenerate()
  dbExecute(
    con,
    "INSERT INTO project (proj_id, proj_name, proj_description) VALUES (?, ?, ?)",
    params = list(proj_id, name, description)
  )
  proj_id
}

db_get_or_create_workflow <- function(con, proj_id, type, name) {
  existing <- dbGetQuery(
    con,
    "SELECT wf_id FROM workflow WHERE wf_proj_id = ? AND wf_type = ? AND wf_name = ?",
    params = list(proj_id, type, name)
  )
  if (nrow(existing) > 0) {
    return(existing$wf_id[1])
  }
  wf_id <- uuid::UUIDgenerate()
  dbExecute(
    con,
    "INSERT INTO workflow (wf_id, wf_proj_id, wf_type, wf_name) VALUES (?, ?, ?, ?)",
    params = list(wf_id, proj_id, type, name)
  )
  wf_id
}

db_create_run <- function(con, wf_id, seed = NA_integer_, git_commit = get_git_commit(), notes = NA_character_) {
  run_id <- uuid::UUIDgenerate()
  dbExecute(
    con,
    "INSERT INTO run (run_id, run_wf_id, run_seed, run_git_commit, run_notes) VALUES (?, ?, ?, ?, ?)",
    params = list(run_id, wf_id, seed, git_commit, notes)
  )
  run_id
}

db_finish_run <- function(con, run_id) {
  dbExecute(con, "UPDATE run SET run_finished_at = datetime('now') WHERE run_id = ?", params = list(run_id))
  invisible(NULL)
}

# config: benannte Liste/Vektor der zur Laufzeit relevanten 000_config.R-Werte.
db_log_run_config <- function(con, run_id, config) {
  for (key in names(config)) {
    dbExecute(
      con,
      "INSERT INTO run_config (rconf_id, rconf_run_id, rconf_key, rconf_value) VALUES (?, ?, ?, ?)",
      params = list(uuid::UUIDgenerate(), run_id, key, as.character(config[[key]]))
    )
  }
  invisible(NULL)
}

# hyperparams: benannte Liste modellspezifischer Hyperparameter (optional).
# preprocessing: kurzes Label fuer die verwendete Preprocessing-Pipeline
# (z.B. "impute_median_mode", "impute_median_mode_empty_to_na", "onehot",
# "onehot_scale") - getrennt von feature_set (welche Spalten) und algorithm
# (welcher Learner).
db_create_model_config <- function(con, run_id, task_type, algorithm, feature_set = NA_character_,
                                    preprocessing = NA_character_, class_weight_power = NA_real_,
                                    task_id = NA_character_, hyperparams = list()) {
  mconf_id <- uuid::UUIDgenerate()
  dbExecute(
    con,
    paste(
      "INSERT INTO model_config",
      "(mconf_id, mconf_run_id, mconf_task_type, mconf_algorithm, mconf_feature_set,",
      " mconf_preprocessing, mconf_class_weight_power, mconf_task_id)",
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list(mconf_id, run_id, task_type, algorithm, feature_set, preprocessing, class_weight_power, task_id)
  )

  for (name in names(hyperparams)) {
    dbExecute(
      con,
      "INSERT INTO hyperparam (hparam_id, hparam_mconf_id, hparam_name, hparam_value) VALUES (?, ?, ?, ?)",
      params = list(uuid::UUIDgenerate(), mconf_id, name, as.character(hyperparams[[name]]))
    )
  }

  mconf_id
}

db_create_resampling <- function(con, run_id, strategy, folds = NA_integer_, ratio = NA_real_,
                                  seed = NA_integer_) {
  rsmp_id <- uuid::UUIDgenerate()
  dbExecute(
    con,
    "INSERT INTO resampling (rsmp_id, rsmp_run_id, rsmp_strategy, rsmp_folds, rsmp_ratio, rsmp_seed) VALUES (?, ?, ?, ?, ?, ?)",
    params = list(rsmp_id, run_id, strategy, folds, ratio, seed)
  )
  rsmp_id
}

# Loggt Einzelvorhersagen (row_id, Wahrheit, Vorhersage, volle Wahrscheinlich-
# keitsverteilung). Filtert NICHT selbst - der Aufrufer entscheidet, welche
# Zeilen "interessant" genug sind (typischerweise: falsch klassifiziert oder
# Konfidenz unter einem Schwellenwert), damit die Tabelle nicht durch
# routinemaessiges Loggen aller Zeilen aller Model-Configs unkontrolliert
# waechst.
# row_ids: Vektor der mlr3-row_ids. truth/response: Faktor-/Character-Vektoren
# gleicher Laenge. prob_matrix: Matrix/data.frame mit einer Spalte je Klasse
# (Spaltennamen = Klassenbezeichnungen), Zeilenreihenfolge wie row_ids.
# fold: einzelner Wert (NA bei Holdout) oder Vektor gleicher Laenge wie row_ids.
#
# Vergibt pred_seq manuell (statt SQLite per Autoincrement zu ueberlassen),
# damit die Werte sofort fuer die zugehoerigen prediction_prob-Zeilen bekannt
# sind (dbAppendTable() gibt keine generierten rowids zurueck). In einer
# Transaktion, damit "MAX(pred_seq) lesen" + "einfuegen" atomar bleibt, falls
# ein anderer Prozess gleichzeitig schreibt (siehe WAL/busy_timeout in
# db_connect()).
db_log_predictions <- function(con, mconf_id, rsmp_id, row_ids, truth, response, prob_matrix,
                                fold = NA_integer_) {
  n <- length(row_ids)
  fold_vec <- if (length(fold) == 1) rep(fold, n) else fold

  dbBegin(con)
  current_max <- dbGetQuery(con, "SELECT COALESCE(MAX(pred_seq), 0) AS m FROM prediction")$m
  pred_seqs <- current_max + seq_len(n)

  dbAppendTable(con, "prediction", data.frame(
    pred_seq = pred_seqs,
    pred_mconf_id = mconf_id,
    pred_rsmp_id = rsmp_id,
    pred_row_id = as.integer(row_ids),
    pred_fold = as.integer(fold_vec),
    pred_truth = as.character(truth),
    pred_response = as.character(response),
    stringsAsFactors = FALSE
  ))

  prob_df <- as.data.frame(prob_matrix)
  prob_long <- data.frame(
    pprob_pred_seq = rep(pred_seqs, times = ncol(prob_df)),
    pprob_class = rep(colnames(prob_df), each = nrow(prob_df)),
    pprob_value = unlist(prob_df, use.names = FALSE)
  )
  dbAppendTable(con, "prediction_prob", prob_long)
  dbCommit(con)

  invisible(pred_seqs)
}

db_log_metric_result <- function(con, mconf_id, rsmp_id, measure_name, value, fold = NA_integer_,
                                  elapsed_seconds = NA_real_) {
  dbExecute(
    con,
    paste(
      "INSERT INTO metric_result",
      "(mres_id, mres_mconf_id, mres_rsmp_id, mres_measure_name, mres_value, mres_fold, mres_elapsed_seconds)",
      "VALUES (?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list(uuid::UUIDgenerate(), mconf_id, rsmp_id, measure_name, value, fold, elapsed_seconds)
  )
  invisible(NULL)
}

# Hochgradige Bequemlichkeitsfunktion fuer den typischen Skript-Fall: nimmt
# ein komplettes run_timed_benchmark()-Ergebnis (mehrere Task/Learner-Zeilen),
# erzeugt EIN resampling fuer alle Zeilen (dieselbe Resampling-Strategie wird
# ja in einem Benchmark-Aufruf ueblicherweise fuer alle Modelle geteilt) und
# ruft fuer jede Ergebniszeile model_config_fn(row) auf, um die Metadaten
# (algorithm, feature_set, preprocessing, hyperparams, ...) zu bestimmen -
# loggt dann model_config + hyperparam + aggregierte/Pro-Fold-metric_result.
#
# model_config_fn: function(row) -> list(task_type=, algorithm=, feature_set=,
#   preprocessing=, class_weight_power=, task_id=, hyperparams=list())
db_log_timed_benchmark <- function(con, run_id, timed_benchmark, measure_names, model_config_fn,
                                    resampling_strategy, resampling_folds = NA_integer_,
                                    resampling_ratio = NA_real_, resampling_seed = NA_integer_) {
  rsmp_id <- db_create_resampling(
    con, run_id, resampling_strategy,
    folds = resampling_folds, ratio = resampling_ratio, seed = resampling_seed
  )

  results <- timed_benchmark$results
  for (i in seq_len(nrow(results))) {
    row <- results[i]
    mc <- model_config_fn(row)
    mconf_id <- db_create_model_config(
      con, run_id,
      task_type = mc$task_type, algorithm = mc$algorithm, feature_set = mc$feature_set,
      preprocessing = mc$preprocessing, class_weight_power = mc$class_weight_power,
      task_id = mc$task_id, hyperparams = if (is.null(mc$hyperparams)) list() else mc$hyperparams
    )
    db_log_benchmark_metrics(con, mconf_id, rsmp_id, row, timed_benchmark$scores, measure_names)
  }

  invisible(rsmp_id)
}

# Bequemlichkeitsfunktion fuer den typischen Fall: ein Ergebnis aus
# run_timed_benchmark()$results (aggregiert, eine Zeile) plus die
# dazugehoerigen Zeilen aus $scores (pro Fold, gleiche task_id/learner_id) in
# einem Aufruf loggen - aggregiert (mres_fold = NULL) UND pro Fold.
db_log_benchmark_metrics <- function(con, mconf_id, rsmp_id, results_row, scores, measure_names,
                                      elapsed_col = "elapsed_seconds") {
  fold_rows <- scores[scores$task_id == results_row$task_id[1] & scores$learner_id == results_row$learner_id[1], ]

  for (measure in measure_names) {
    db_log_metric_result(
      con, mconf_id, rsmp_id, measure, results_row[[measure]][1],
      fold = NA_integer_, elapsed_seconds = results_row[[elapsed_col]][1]
    )
    for (i in seq_len(nrow(fold_rows))) {
      db_log_metric_result(
        con, mconf_id, rsmp_id, measure, fold_rows[[measure]][i],
        fold = fold_rows$iteration[i], elapsed_seconds = fold_rows[[elapsed_col]][i]
      )
    }
  }
  invisible(NULL)
}

# Findet den Pfad der zuletzt gespeicherten Modell-Datei fuer einen
# Algorithmus (siehe 150_train_full_model.R, das den Pfad als
# "model_artifact_path"-Hyperparameter loggt). Ersetzt einen fixen
# Dateinamen: final_model_full_path() (000_config.R) haengt die run_id an,
# damit ein neuer Trainingslauf die vorherige Modell-Datei nicht
# kommentarlos ueberschreibt - diese Funktion ist das Gegenstueck, das aus
# der DB den zur run_id passenden Pfad zurueckholt. workflow_name grenzt auf
# das Skript ein, das den Pfad geloggt hat, damit ein gleichnamiger
# Algorithmus aus einem anderen Skript nicht versehentlich getroffen wird.
db_get_latest_model_artifact_path <- function(con, algorithm, workflow_name = "150_train_full_model.R") {
  result <- dbGetQuery(con, "
    SELECT h.hparam_value AS model_path
    FROM hyperparam h
    JOIN model_config mc ON mc.mconf_id = h.hparam_mconf_id
    JOIN run r ON r.run_id = mc.mconf_run_id
    JOIN workflow wf ON wf.wf_id = r.run_wf_id
    WHERE mc.mconf_algorithm = ? AND wf.wf_name = ? AND h.hparam_name = 'model_artifact_path'
    ORDER BY r.run_started_at DESC
    LIMIT 1
  ", params = list(algorithm, workflow_name))

  if (nrow(result) == 0) {
    return(NA_character_)
  }
  result$model_path[1]
}
