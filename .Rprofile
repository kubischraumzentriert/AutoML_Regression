# mlr3extralearners liegt nicht auf CRAN, nur im mlr-org R-Universe -
# DESCRIPTIONs Additional_repositories-Feld wird von pak NICHT automatisch
# gelesen (bestaetigt: CI schlug trotz gesetztem Feld identisch fehl - siehe
# MLR3_Classifikation/.Rprofile fuer denselben, dort bereits geloesten Fund).
# pak liest stattdessen getOption("repos") - das hier setzt genau das, fuer
# lokale Rscript-Laeufe UND fuer r-lib/actions/setup-r-dependencies@v2 (das
# dieselbe R-Session im Repo-Root startet und damit dieses .Rprofile
# automatisch einliest).
.mlr3_ci_default_cran <- getOption("repos")["CRAN"]
if (is.null(.mlr3_ci_default_cran) || is.na(.mlr3_ci_default_cran)) {
  .mlr3_ci_default_cran <- "https://cloud.r-project.org"
}
options(repos = c(mlrorg = "https://mlr-org.r-universe.dev", CRAN = .mlr3_ci_default_cran))
rm(.mlr3_ci_default_cran)
