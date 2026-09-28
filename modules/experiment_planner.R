# =============================================================================
# experiment_planner.R -- Geplante-Experimente-Tabelle (PyExperimenter-
# inspiriert, siehe docs/research/JOSS_TECHNIQUE_WATCH.md, Kandidat 4).
# =============================================================================
# Anlass: PyExperimenter (Tornede et al. 2023, JOSS 10.21105/joss.05149)
# loest Definition/Ausfuehrung/Wiederaufnahme vieler geplanter Experiment-
# Varianten inkl. DB-Steuerung. Die Idee wurde am 2026-08-30 zurueckgestellt
# ("relevant, WENN der Benchmark auf 10-15+ Datensaetze waechst") - dieser
# Schwellenwert ist seit dem n=15-CC18-Benchmark erreicht.
#
# Vor dem Backport wurde geprueft, ob die konkrete Reibung ("vergessene/
# doppelte Laeufe") im Template ueberhaupt auftrat: die eigentliche n=6->
# 10->15-CC18-Erweiterung lief sauber (dedizierte Auswahlskripte, keine
# Duplikate). Ein ECHTER, verwandter Fund existiert aber:
# `PredictingElectricVehiclePurchases-s6e9` (2026-09-04, siehe BACKLOG.md)
# - nach der Umstellung von 10%-Subset auf volle Datenmenge wurde
# `090_ranger_tuning.R` nie erneut ausgefuehrt, waehrend `100_lightgbm_
# tuning.R` korrekt neu getunt wurde. Kein Duplikat-/Scheduling-Problem,
# sondern ein STILLER KONFIGURATIONSDRIFT zwischen parallelen Armen. Das
# Design hier zielt deshalb bewusst auf genau diesen Fehlertyp, nicht auf
# die volle PyExperimenter-Feature-Breite (Cluster-Verteilung, Retry-Logik
# etc. - dafuer besteht bislang keine Evidenz eines eigenen Bedarfs).
#
# `db_housekeeping.R` (P2.1) deckt einen ANDEREN, ebenfalls "was ist
# inkonsistent"-Aspekt ab (fehlende Merges/Duplikate/unvollstaendige Runs
# ueber viele PROJEKT-DBs hinweg, rueckblickend) - dieses Modul ist
# INNERHALB eines Projekts, vorausschauend ("was ist noch nicht/nicht mehr
# aktuell gelaufen") und traegt eine explizite Config-Hash-basierte
# Staleness-Erkennung, die db_housekeeping.R nicht hat.

suppressPackageStartupMessages({
  library(DBI)
  library(uuid)
})

#' Bequemlichkeits-Hash fuer eine Tuning-"Arm"-Konfiguration: hasht die
#' TATSAECHLICH verwendeten Task-Daten (faengt Aenderungen wie
#' subset_fraction/Feature-Engineering auf, unabhaengig davon WELCHER
#' Parameter sich geaendert hat - genau das war die Luecke im s6e9-Fund,
#' siehe Kopfkommentar) plus optionale weitere Werte (z.B. Tuning-Budget).
#'
#' @param task mlr3 Task (dessen `$data()` gehasht wird).
#' @param extra benannte Liste zusaetzlicher Werte (z.B. Budget-Parameter,
#'   Suchraum-Grenzen) - aendert sich einer davon, soll der Arm ebenfalls
#'   als veraltet gelten.
#' @return character(1) Hash.
experiment_config_hash <- function(task, extra = list()) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("experiment_config_hash() benoetigt das Paket digest.", call. = FALSE)
  }
  digest::digest(list(data = task$data(), extra = extra), algo = "xxhash64")
}

#' Plant ein Experiment oder aktualisiert einen bestehenden Plan-Eintrag.
#'
#' Eindeutigkeit ueber (proj_id, label) - ein zweiter Aufruf mit demselben
#' Label ist ein UPDATE, kein Duplikat. Zentrale Logik: wenn der zuletzt als
#' 'done' geloggte Eintrag einen ANDEREN `config_hash` hatte als jetzt
#' uebergeben, wird der Eintrag auf 'stale' gesetzt statt sang- und
#' klanglos als weiterhin gueltig zu gelten - genau der Mechanismus, der
#' den s6e9-Reibungsfall (siehe Kopfkommentar) erkannt haette.
#'
#' @param con offene DB-Verbindung (db_connect()).
#' @param proj_id project.proj_id (z.B. aus db_get_or_create_project()).
#' @param label eindeutiger, menschenlesbarer Bezeichner des geplanten
#'   Schritts (z.B. "090_ranger_tuning @ subset_fraction=1.0").
#' @param script optional: Skriptdateiname.
#' @param config_hash optional: Hash der fuer dieses Label relevanten
#'   Konfiguration (Datensatz/Feature-Set/Parameter) - Aufrufer entscheidet
#'   selbst, was hineingehasht wird (z.B. `digest::digest(list(...))`).
#' @param priority "low"/"medium"/"high" (Default "medium").
#' @param seed optional: geplanter Seed.
#' @param notes optional: Freitext.
#' @return `pexp_id` (unsichtbar).
db_plan_experiment <- function(con, proj_id, label, script = NA_character_,
                                config_hash = NA_character_, priority = "medium",
                                seed = NA_integer_, notes = NA_character_) {
  if (!priority %in% c("low", "medium", "high")) {
    stop("priority muss 'low', 'medium' oder 'high' sein.", call. = FALSE)
  }

  existing <- DBI::dbGetQuery(
    con,
    "SELECT pexp_id, pexp_status, pexp_config_hash FROM planned_experiment WHERE pexp_proj_id = ? AND pexp_label = ?",
    params = list(proj_id, label)
  )

  if (nrow(existing) == 0) {
    pexp_id <- uuid::UUIDgenerate()
    DBI::dbExecute(
      con,
      paste(
        "INSERT INTO planned_experiment",
        "(pexp_id, pexp_proj_id, pexp_label, pexp_script, pexp_config_hash,",
        " pexp_priority, pexp_seed, pexp_notes)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = list(pexp_id, proj_id, label, script, config_hash, priority, seed, notes)
    )
    return(invisible(pexp_id))
  }

  pexp_id <- existing$pexp_id[1]
  became_stale <- identical(existing$pexp_status[1], "done") &&
    !is.na(config_hash) && !is.na(existing$pexp_config_hash[1]) &&
    !identical(existing$pexp_config_hash[1], config_hash)

  new_status <- if (became_stale) "stale" else existing$pexp_status[1]

  DBI::dbExecute(
    con,
    paste(
      "UPDATE planned_experiment SET pexp_script = ?, pexp_config_hash = ?,",
      "pexp_priority = ?, pexp_seed = ?, pexp_notes = ?, pexp_status = ?,",
      "pexp_updated_at = datetime('now') WHERE pexp_id = ?"
    ),
    params = list(script, config_hash, priority, seed, notes, new_status, pexp_id)
  )

  if (became_stale) {
    cat(sprintf(
      "HINWEIS: '%s' war 'done', Config-Hash hat sich geaendert - auf 'stale' gesetzt (Rerun noetig).\n",
      label
    ))
  }

  invisible(pexp_id)
}

#' Setzt einen geplanten Eintrag auf 'running'.
db_start_experiment <- function(con, pexp_id) {
  DBI::dbExecute(
    con,
    "UPDATE planned_experiment SET pexp_status = 'running', pexp_updated_at = datetime('now') WHERE pexp_id = ?",
    params = list(pexp_id)
  )
  invisible(NULL)
}

#' Markiert einen geplanten Eintrag als abgeschlossen und verknuepft den
#' tatsaechlichen `run.run_id`.
db_complete_experiment <- function(con, pexp_id, run_id) {
  DBI::dbExecute(
    con,
    paste(
      "UPDATE planned_experiment SET pexp_status = 'done', pexp_run_id = ?,",
      "pexp_updated_at = datetime('now') WHERE pexp_id = ?"
    ),
    params = list(run_id, pexp_id)
  )
  invisible(NULL)
}

#' Markiert einen geplanten Eintrag als fehlgeschlagen oder uebersprungen.
#' @param status "failed" oder "skipped".
db_close_experiment <- function(con, pexp_id, status = c("failed", "skipped"), notes = NA_character_) {
  status <- match.arg(status)
  DBI::dbExecute(
    con,
    paste(
      "UPDATE planned_experiment SET pexp_status = ?, pexp_notes = COALESCE(?, pexp_notes),",
      "pexp_updated_at = datetime('now') WHERE pexp_id = ?"
    ),
    params = list(status, notes, pexp_id)
  )
  invisible(NULL)
}

#' Konsolen-Report + Rueckgabe: alle nicht abgeschlossenen Eintraege
#' ('planned'/'stale'/'running'), nach Prioritaet sortiert - der direkte
#' "was ist noch offen?"-Einstieg. Nutzt `v_planned_experiments`
#' (db_schema.sql), damit Sortierung/Projektname nicht doppelt in R und SQL
#' gepflegt werden muss.
#' @param proj_name optional: nur ein Projekt (sonst alle).
report_planned_experiments <- function(con, proj_name = NULL) {
  query <- "SELECT * FROM v_planned_experiments WHERE pexp_status IN ('planned', 'stale', 'running')"
  pending <- if (!is.null(proj_name)) {
    DBI::dbGetQuery(con, paste(query, "AND proj_name = ?"), params = list(proj_name))
  } else {
    DBI::dbGetQuery(con, query)
  }

  cat("\n=== Offene geplante Experimente (", nrow(pending), ") ===\n", sep = "")
  if (nrow(pending) == 0) {
    cat("Keine offenen Eintraege.\n")
  } else {
    stale <- pending[pending$pexp_status == "stale", , drop = FALSE]
    if (nrow(stale) > 0) {
      cat(sprintf(
        "ACHTUNG: %d Eintrag/Eintraege 'stale' (Config hat sich seit dem letzten Lauf geaendert):\n",
        nrow(stale)
      ))
      for (i in seq_len(nrow(stale))) {
        cat(sprintf("  - [%s] %s (Skript: %s)\n", stale$proj_name[i], stale$pexp_label[i],
                     ifelse(is.na(stale$pexp_script[i]), "?", stale$pexp_script[i])))
      }
    }
    print(pending[, c("proj_name", "pexp_label", "pexp_priority", "pexp_status", "pexp_script")])
  }

  invisible(pending)
}
