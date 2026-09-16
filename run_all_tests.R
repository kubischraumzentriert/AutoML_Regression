# =====================================================================
# run_all_tests.R -- fuehrt alle test_*.R-Dateien im Repo-Root nacheinander
# aus (jede eigenstaendig lauffaellig, `rm(list = ls())`-isoliert, endet
# mit `quit(status = 1)` bei mindestens einem fehlgeschlagenen Check -
# siehe test_combined_task_helper.R fuer das Muster). Ersetzt das bisherige
# manuelle Einzelausfuehren vor jedem Commit durch einen einzigen Aufruf,
# der auch von CI genutzt werden kann (.github/workflows/ci-tests.yml).
#
# Jede Datei laeuft in einem eigenen `Rscript`-Unterprozess (nicht per
# `source()`), damit ein Fehler/Crash in einer Datei die anderen nicht
# verhindert und Seiteneffekte (rm(list=ls()), geladene Pakete) sauber
# isoliert bleiben.
# =====================================================================

test_files <- sort(list.files(".", pattern = "^test_.*\\.R$"))
if (length(test_files) == 0) {
  cat("Keine test_*.R-Dateien gefunden.\n")
  quit(status = 1)
}

rscript_bin <- file.path(R.home("bin"), "Rscript")
results <- data.frame(file = test_files, status = NA_character_, seconds = NA_real_)

for (i in seq_along(test_files)) {
  f <- test_files[i]
  cat(sprintf("\n=== %s ===\n", f))
  t0 <- Sys.time()
  res <- system2(rscript_bin, f, stdout = "", stderr = "")
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  results$status[i] <- if (res == 0) "OK" else "FEHLGESCHLAGEN"
  results$seconds[i] <- elapsed
}

cat("\n=== Zusammenfassung ===\n")
print(results, row.names = FALSE)

if (any(results$status != "OK")) {
  cat(sprintf("\n%d von %d Testdateien fehlgeschlagen.\n", sum(results$status != "OK"), nrow(results)))
  quit(status = 1)
}
cat(sprintf("\nAlle %d Testdateien OK (%.1fs gesamt).\n", nrow(results), sum(results$seconds)))
