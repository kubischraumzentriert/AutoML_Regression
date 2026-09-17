rm(list = ls())

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

# Konsolidiert die projekteigenen experiments.db-Dateien mehrerer
# abgeschlossener Kaggle-Projekte in die zentrale Template-Datenbank, damit
# sich spaeter projektuebergreifende Muster per SQL abfragen lassen (z.B.
# "wie oft hat Tuning den Default tatsaechlich geschlagen", "AUC- vs.
# BAcc-Projekte im Vergleich"), statt nur in README/TEMPLATE_FRICTION-Prosa.
#
# Bewusst NUR die aggregierten Tabellen (project/workflow/run/run_config/
# model_config/resampling/hyperparam/metric_result) - NICHT prediction/
# prediction_prob. Gruende:
# 1. Zeilenebene ist projektspezifisch (row_id/truth/response beziehen sich
#    auf unterschiedliche Datensaetze/Zielspalten) - projektuebergreifend
#    nicht sinnvoll vergleichbar, nur innerhalb EINES Projekts fuer
#    Fehleranalyse (147) relevant.
# 2. prediction/prediction_prob nutzen bewusst lokale INTEGER-Keys
#    (pred_seq/pprob_pred_seq) statt UUIDs (siehe db_schema.sql-Kommentar,
#    Platzgrund) - ein Merge muesste diese Keys umschreiben. Ohne echten
#    Nutzen (Punkt 1) lohnt sich dieser Aufwand nicht.
# Die projekteigenen experiments.db-Dateien bleiben unveraendert und
# behalten ihre vollstaendigen prediction-Daten fuer lokale Fehleranalyse.
#
# Alle uebrigen Tabellen referenzieren sich ausschliesslich ueber UUID-Text-
# Spalten (<praefix>_id) - ein einfaches INSERT SELECT reicht, keine
# Schluessel-Neuvergabe noetig (siehe db_schema.sql-Kopfkommentar).
#
# Idempotent: ein Projekt (per proj_name) wird nur gemergt, wenn es in der
# Ziel-DB noch nicht existiert - mehrfaches Ausfuehren ist gefahrlos.
#
# Quellen werden AUTOMATISCH unter den bekannten Projekt-Wurzeln gesucht
# (`R_Workspace`, `ML_Learning`), statt eine Liste manuell zu pflegen - eine
# hardcodierte Liste veraltet zuverlaessig. Die beiden Template-Repos selbst
# (deren EIGENE `_artifacts/experiments.db` das Merge-Ziel bzw. das Pendant
# fuer Klassifikation ist) werden ausgeschlossen, um kein Projekt versehentlich
# mit sich selbst oder dem falschen Template zu mergen.
#
# HINWEIS (2026-08-08): Diese Datei war bis hierher eine unangepasste Kopie
# der Klassifikations-Version - `target_db_path` zeigte faelschlich auf die
# Klassifikations-DB statt auf dieses Repo, korrigiert im selben Zug wie die
# Auto-Discovery-Uebernahme (siehe adr/001-local-project-db-central-merge.md).

target_db_path <- "C:/Users/HP/OneDrive/Dokumente/R_Workspace/MLR3_Regression/_artifacts/experiments.db"

project_roots <- c(
  "C:/Users/HP/OneDrive/Dokumente/R_Workspace",
  "C:/Users/HP/ML_Learning"
)
exclude_dirs <- c("MLR3_Classifikation", "MLR3_Regression")

discover_source_db_paths <- function(roots, exclude, target) {
  target_norm <- normalizePath(target, winslash = "/", mustWork = FALSE)
  found <- unlist(lapply(roots, function(root) {
    if (!dir.exists(root)) return(character(0))
    Sys.glob(file.path(root, "*", "_artifacts", "experiments.db"))
  }))
  found <- unique(normalizePath(found, winslash = "/", mustWork = FALSE))
  found <- found[found != target_norm]
  project_dir_name <- basename(dirname(dirname(found)))
  found <- found[!project_dir_name %in% exclude]
  project_dir_name <- basename(dirname(dirname(found)))
  setNames(found, project_dir_name)
}

source_db_paths <- discover_source_db_paths(project_roots, exclude_dirs, target_db_path)
cat("Gefundene Quell-DBs (", length(source_db_paths), "):\n", sep = "")
for (nm in names(source_db_paths)) cat("  -", nm, "->", source_db_paths[[nm]], "\n")
cat("\n")

# Tabellen in Fremdschluessel-Abhaengigkeitsreihenfolge (Eltern vor Kindern).
merge_tables <- c(
  "project", "workflow", "run", "run_config",
  "model_config", "resampling", "hyperparam", "metric_result"
)

if (!file.exists(target_db_path)) {
  stop("Ziel-DB nicht gefunden: ", target_db_path)
}

# Backup der Ziel-DB, bevor irgendetwas geschrieben wird.
backup_path <- sub(
  "\\.db$",
  paste0("_backup_", format(Sys.time(), "%Y%m%dT%H%M%S"), ".db"),
  target_db_path
)
file.copy(target_db_path, backup_path)
cat("Backup der Ziel-DB angelegt:", backup_path, "\n\n")

con <- dbConnect(RSQLite::SQLite(), target_db_path)
dbExecute(con, "PRAGMA foreign_keys = ON;")

existing_projects <- dbGetQuery(con, "SELECT proj_name FROM project")$proj_name

for (project_label in names(source_db_paths)) {
  source_path <- source_db_paths[[project_label]]

  cat("=== ", project_label, " ===\n", sep = "")

  if (!file.exists(source_path)) {
    cat("  Quelle fehlt, uebersprungen:", source_path, "\n\n")
    next
  }

  source_proj_name <- {
    src_con <- dbConnect(RSQLite::SQLite(), source_path)
    proj_name <- dbGetQuery(src_con, "SELECT proj_name FROM project")$proj_name
    dbDisconnect(src_con)
    proj_name
  }

  if (length(source_proj_name) == 0) {
    cat("  Keine project-Zeile in der Quelle gefunden, uebersprungen.\n\n")
    next
  }

  # Eine Quell-DB kann mehrere proj_name-Zeilen enthalten (z.B. `tweet` mit
  # separaten Poisson-/Tweedie-Projekten in derselben Datei) - deshalb ueber
  # ALLE Namen pruefen, nicht nur den ersten.
  already_merged <- source_proj_name %in% existing_projects
  if (all(already_merged)) {
    cat("  Bereits vollstaendig gemergt (", paste(source_proj_name, collapse = ", "), "), uebersprungen.\n\n", sep = "")
    next
  }
  if (any(already_merged) && !all(already_merged)) {
    cat("  TEILWEISE bereits gemergt (", paste(source_proj_name[already_merged], collapse = ", "),
        ") - restliche Projekte (", paste(source_proj_name[!already_merged], collapse = ", "),
        ") NICHT automatisch gemergt, manuell pruefen.\n\n", sep = "")
    next
  }

  dbExecute(con, sprintf("ATTACH DATABASE '%s' AS src", source_path))

  dbBegin(con)
  tryCatch({
    for (tbl in merge_tables) {
      # Jede Tabelle hat eine lokale INTEGER-PRIMARY-KEY-Spalte (<praefix>_seq,
      # SQLite-rowid-Alias) - die NICHT mitkopiert werden darf (kollidiert
      # sonst mit bereits vorhandenen Zeilen in der Ziel-Tabelle). Alle
      # anderen Spalten haengen an UUID-Text-Schluesseln, die kollisionsfrei
      # sind. Spaltenliste dynamisch aus PRAGMA table_info ermitteln (pk=1
      # markiert die auszuschliessende Spalte) statt hart zu codieren.
      col_info <- dbGetQuery(con, sprintf("PRAGMA table_info(%s)", tbl))
      cols <- col_info$name[col_info$pk == 0]
      col_list <- paste(cols, collapse = ", ")

      n_before <- dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", tbl))$n
      dbExecute(con, sprintf("INSERT INTO %s (%s) SELECT %s FROM src.%s", tbl, col_list, col_list, tbl))
      n_after <- dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", tbl))$n
      cat(sprintf("  %-14s +%d Zeilen (%d -> %d)\n", tbl, n_after - n_before, n_before, n_after))
    }
    dbCommit(con)
    existing_projects <- c(existing_projects, source_proj_name)
    cat("  Gemergt: '", paste(source_proj_name, collapse = "', '"), "'\n\n", sep = "")
  }, error = function(e) {
    dbRollback(con)
    cat("  FEHLER, Merge fuer dieses Projekt zurueckgerollt:", conditionMessage(e), "\n\n")
  })

  dbExecute(con, "DETACH DATABASE src")
}

cat("=== Zusammenfassung Ziel-DB (", target_db_path, ") ===\n", sep = "")
summary_dt <- dbGetQuery(con, "
  SELECT p.proj_name, COUNT(DISTINCT mc.mconf_id) AS n_model_configs, COUNT(mr.mres_id) AS n_metric_results
  FROM project p
  LEFT JOIN workflow wf ON wf.wf_proj_id = p.proj_id
  LEFT JOIN run r ON r.run_wf_id = wf.wf_id
  LEFT JOIN model_config mc ON mc.mconf_run_id = r.run_id
  LEFT JOIN metric_result mr ON mr.mres_mconf_id = mc.mconf_id
  GROUP BY p.proj_name
  ORDER BY p.proj_name
")
print(summary_dt)

dbDisconnect(con)
