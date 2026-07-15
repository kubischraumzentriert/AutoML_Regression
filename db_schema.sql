-- Experiment-Tracking-Schema (SQLite)
-- Siehe README.md/TARGETS.md fuer den Kontext. Namensmuster uebernommen aus
-- einem MES-Traceability-Projekt: jede Tabelle hat ein kurzes Praefix, eine
-- UUID als fachlicher Schluessel (`<praefix>_id`) und eine sequenzielle
-- Nummer (`<praefix>_seq`). Alle weiteren Spalten sind mit dem Praefix
-- versehen.
--
-- SQLite-Anpassungen gegenueber einem Postgres-Vorbild:
-- - Kein natives uuid/uuid_generate_v4(): `<praefix>_id` ist TEXT, die UUID
--   wird in R erzeugt (Paket `uuid`) und beim Insert mitgegeben.
-- - Kein natives serial4/AUTOINCREMENT auf einer Nicht-PK-Spalte: `<praefix>_seq`
--   ist hier selbst der SQLite-PRIMARY-KEY (Alias auf rowid), erzeugt beim
--   Insert automatisch eine fortlaufende Nummer, wenn NULL eingefuegt wird.
--   `<praefix>_id` bleibt der fachliche, eindeutige Schluessel fuer Fremd-
--   schluessel-Beziehungen (UNIQUE-Constraint statt PRIMARY KEY).
-- - Zeitstempel als TEXT (ISO8601, `datetime('now')`), da SQLite keinen
--   nativen Timestamp-Typ hat.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS project (
  proj_seq INTEGER PRIMARY KEY,
  proj_id TEXT NOT NULL UNIQUE,
  proj_name TEXT NOT NULL UNIQUE,
  proj_description TEXT,
  proj_created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS workflow (
  wf_seq INTEGER PRIMARY KEY,
  wf_id TEXT NOT NULL UNIQUE,
  wf_proj_id TEXT NOT NULL REFERENCES project (proj_id),
  wf_type TEXT NOT NULL CHECK (wf_type IN ('targets', 'script')),
  wf_name TEXT NOT NULL,
  wf_created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (wf_proj_id, wf_type, wf_name)
);

CREATE TABLE IF NOT EXISTS run (
  run_seq INTEGER PRIMARY KEY,
  run_id TEXT NOT NULL UNIQUE,
  run_wf_id TEXT NOT NULL REFERENCES workflow (wf_id),
  run_started_at TEXT NOT NULL DEFAULT (datetime('now')),
  run_finished_at TEXT,
  run_git_commit TEXT,
  run_seed INTEGER,
  run_notes TEXT
);

CREATE TABLE IF NOT EXISTS run_config (
  rconf_seq INTEGER PRIMARY KEY,
  rconf_id TEXT NOT NULL UNIQUE,
  rconf_run_id TEXT NOT NULL REFERENCES run (run_id),
  rconf_key TEXT NOT NULL,
  rconf_value TEXT
);

CREATE TABLE IF NOT EXISTS model_config (
  mconf_seq INTEGER PRIMARY KEY,
  mconf_id TEXT NOT NULL UNIQUE,
  mconf_run_id TEXT NOT NULL REFERENCES run (run_id),
  mconf_task_type TEXT NOT NULL,
  mconf_algorithm TEXT NOT NULL,
  mconf_feature_set TEXT,
  mconf_preprocessing TEXT,
  mconf_class_weight_power REAL,
  mconf_task_id TEXT,
  mconf_created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS resampling (
  rsmp_seq INTEGER PRIMARY KEY,
  rsmp_id TEXT NOT NULL UNIQUE,
  rsmp_run_id TEXT NOT NULL REFERENCES run (run_id),
  rsmp_strategy TEXT NOT NULL CHECK (rsmp_strategy IN ('cv', 'holdout', 'custom_split')),
  rsmp_folds INTEGER,
  rsmp_ratio REAL,
  rsmp_seed INTEGER
);

CREATE TABLE IF NOT EXISTS hyperparam (
  hparam_seq INTEGER PRIMARY KEY,
  hparam_id TEXT NOT NULL UNIQUE,
  hparam_mconf_id TEXT NOT NULL REFERENCES model_config (mconf_id),
  hparam_name TEXT NOT NULL,
  hparam_value TEXT
);

CREATE TABLE IF NOT EXISTS metric_result (
  mres_seq INTEGER PRIMARY KEY,
  mres_id TEXT NOT NULL UNIQUE,
  mres_mconf_id TEXT NOT NULL REFERENCES model_config (mconf_id),
  mres_rsmp_id TEXT NOT NULL REFERENCES resampling (rsmp_id),
  mres_measure_name TEXT NOT NULL,
  mres_value REAL NOT NULL,
  mres_fold INTEGER,
  mres_elapsed_seconds REAL
);

-- Zeilenebene fuer einzelne Vorhersagen - bewusst NICHT fuer jede Model-Config
-- befuellt (waere bei CV ueber alle Zeilen x alle Konfigurationen viel zu
-- gross), sondern nur fuer die "interessanten" Faelle: falsch klassifiziert
-- oder Konfidenz unter einem Schwellenwert (siehe 147_error_analysis_ranger.R,
-- error_analysis_uncertainty_threshold in 000_config.R). Aufrufende Skripte
-- entscheiden selbst, welche Zeilen sie uebergeben - db_log_predictions()
-- filtert nicht selbst.
-- Bewusste Abweichung von der sonstigen <praefix>_id/_seq-Konvention: Bei
-- potenziell vielen tausend Zeilen referenziert nichts von aussen eine
-- einzelne Vorhersage per fachlichem Schluessel (nur prediction_prob per
-- FK) - der SQLite-interne rowid (pred_seq) reicht als Schluessel, eine
-- UUID waere hier reiner Speicher-/Join-Overhead ohne Nutzen.
CREATE TABLE IF NOT EXISTS prediction (
  pred_seq INTEGER PRIMARY KEY,
  pred_mconf_id TEXT NOT NULL REFERENCES model_config (mconf_id),
  pred_rsmp_id TEXT NOT NULL REFERENCES resampling (rsmp_id),
  pred_row_id INTEGER NOT NULL,
  pred_fold INTEGER,
  pred_truth TEXT NOT NULL,
  pred_response TEXT NOT NULL
);

-- EAV statt fester Spalten pro Klasse, damit die Klassenzahl projekt-
-- unabhaengig bleibt. Referenziert prediction ueber pred_seq (INTEGER),
-- nicht ueber eine UUID - aus demselben Platzgrund wie oben.
CREATE TABLE IF NOT EXISTS prediction_prob (
  pprob_seq INTEGER PRIMARY KEY,
  pprob_pred_seq INTEGER NOT NULL REFERENCES prediction (pred_seq),
  pprob_class TEXT NOT NULL,
  pprob_value REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_workflow_proj ON workflow (wf_proj_id);
CREATE INDEX IF NOT EXISTS idx_run_wf ON run (run_wf_id);
CREATE INDEX IF NOT EXISTS idx_run_config_run ON run_config (rconf_run_id);
CREATE INDEX IF NOT EXISTS idx_model_config_run ON model_config (mconf_run_id);
CREATE INDEX IF NOT EXISTS idx_resampling_run ON resampling (rsmp_run_id);
CREATE INDEX IF NOT EXISTS idx_hyperparam_mconf ON hyperparam (hparam_mconf_id);
CREATE INDEX IF NOT EXISTS idx_metric_result_mconf ON metric_result (mres_mconf_id);
CREATE INDEX IF NOT EXISTS idx_metric_result_rsmp ON metric_result (mres_rsmp_id);
CREATE INDEX IF NOT EXISTS idx_prediction_mconf ON prediction (pred_mconf_id);
CREATE INDEX IF NOT EXISTS idx_prediction_rsmp ON prediction (pred_rsmp_id);
CREATE INDEX IF NOT EXISTS idx_prediction_row ON prediction (pred_row_id);
CREATE INDEX IF NOT EXISTS idx_prediction_prob_pred ON prediction_prob (pprob_pred_seq);

-- Views ----------------------------------------------------------------
-- v_model_results: eine Zeile je model_config mit aggregierten BAcc/MCC-
-- Werten (mres_fold IS NULL), Hyperparametern als lesbarer Text - der
-- "flache" Ersatz fuer die bisherigen CSV-Exporte, aber aus den
-- normalisierten Tabellen gespeist.
CREATE VIEW IF NOT EXISTS v_model_results AS
SELECT
  p.proj_name,
  wf.wf_name,
  r.run_id,
  r.run_started_at,
  r.run_git_commit,
  mc.mconf_id,
  mc.mconf_task_type,
  mc.mconf_algorithm,
  mc.mconf_feature_set,
  mc.mconf_preprocessing,
  mc.mconf_class_weight_power,
  mc.mconf_task_id,
  rs.rsmp_strategy,
  rs.rsmp_folds,
  rs.rsmp_ratio,
  MAX(CASE WHEN mr.mres_measure_name = 'classif.bacc' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS bacc,
  MAX(CASE WHEN mr.mres_measure_name = 'classif.mcc' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS mcc,
  MAX(mr.mres_elapsed_seconds) AS elapsed_seconds,
  (SELECT GROUP_CONCAT(h.hparam_name || '=' || h.hparam_value, ', ')
     FROM hyperparam h WHERE h.hparam_mconf_id = mc.mconf_id) AS hyperparams
FROM model_config mc
JOIN run r ON r.run_id = mc.mconf_run_id
JOIN workflow wf ON wf.wf_id = r.run_wf_id
JOIN project p ON p.proj_id = wf.wf_proj_id
JOIN metric_result mr ON mr.mres_mconf_id = mc.mconf_id
JOIN resampling rs ON rs.rsmp_id = mr.mres_rsmp_id
GROUP BY mc.mconf_id;

-- v_fold_detail: Einzelwerte je Fold (mres_fold IS NOT NULL) - fuer
-- Varianz-/Stabilitaetsanalysen zwischen den Folds.
CREATE VIEW IF NOT EXISTS v_fold_detail AS
SELECT
  p.proj_name,
  wf.wf_name,
  mc.mconf_id,
  mc.mconf_algorithm,
  mc.mconf_feature_set,
  mc.mconf_preprocessing,
  mc.mconf_class_weight_power,
  rs.rsmp_strategy,
  rs.rsmp_folds,
  mr.mres_measure_name,
  mr.mres_fold,
  mr.mres_value
FROM metric_result mr
JOIN model_config mc ON mc.mconf_id = mr.mres_mconf_id
JOIN resampling rs ON rs.rsmp_id = mr.mres_rsmp_id
JOIN run r ON r.run_id = mc.mconf_run_id
JOIN workflow wf ON wf.wf_id = r.run_wf_id
JOIN project p ON p.proj_id = wf.wf_proj_id
WHERE mr.mres_fold IS NOT NULL
ORDER BY mc.mconf_id, mr.mres_measure_name, mr.mres_fold;

-- v_run_summary: ein Rollup je run - wie viele model_configs, bester
-- BAcc/MCC-Wert (ueber alle model_configs des Runs hinweg).
CREATE VIEW IF NOT EXISTS v_run_summary AS
SELECT
  p.proj_name,
  wf.wf_name,
  r.run_id,
  r.run_started_at,
  r.run_finished_at,
  r.run_seed,
  r.run_git_commit,
  COUNT(DISTINCT mc.mconf_id) AS n_model_configs,
  MAX(CASE WHEN mr.mres_measure_name = 'classif.bacc' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS best_bacc,
  MAX(CASE WHEN mr.mres_measure_name = 'classif.mcc' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS best_mcc
FROM run r
JOIN workflow wf ON wf.wf_id = r.run_wf_id
JOIN project p ON p.proj_id = wf.wf_proj_id
LEFT JOIN model_config mc ON mc.mconf_run_id = r.run_id
LEFT JOIN metric_result mr ON mr.mres_mconf_id = mc.mconf_id
GROUP BY r.run_id;

-- v_best_per_algorithm: die bislang beste (hoechste BAcc) Konfiguration je
-- Algorithmus, ueber alle Runs/Projekte hinweg - direkt "was ist aktuell
-- unser bestes Modell je Algorithmus".
CREATE VIEW IF NOT EXISTS v_best_per_algorithm AS
SELECT * FROM (
  SELECT
    v.*,
    ROW_NUMBER() OVER (PARTITION BY mconf_algorithm ORDER BY bacc DESC) AS rn
  FROM v_model_results v
  WHERE bacc IS NOT NULL
)
WHERE rn = 1;

-- v_prediction_detail: eine Zeile je geloggter Einzelvorhersage (nur die
-- "interessanten" Faelle, siehe prediction-Tabelle) mit Modellkontext und
-- Wahrscheinlichkeit der vorhergesagten Klasse - der direkte Einstieg fuer
-- Fehler-/Unsicherheitsanalysen ueber SQL statt CSV.
CREATE VIEW IF NOT EXISTS v_prediction_detail AS
SELECT
  p.proj_name,
  wf.wf_name,
  mc.mconf_algorithm,
  mc.mconf_class_weight_power,
  pr.pred_row_id,
  pr.pred_fold,
  pr.pred_truth,
  pr.pred_response,
  (pr.pred_truth = pr.pred_response) AS correct,
  (SELECT pp.pprob_value FROM prediction_prob pp WHERE pp.pprob_pred_seq = pr.pred_seq AND pp.pprob_class = pr.pred_response) AS response_prob,
  (SELECT pp.pprob_value FROM prediction_prob pp WHERE pp.pprob_pred_seq = pr.pred_seq AND pp.pprob_class = pr.pred_truth) AS truth_prob
FROM prediction pr
JOIN model_config mc ON mc.mconf_id = pr.pred_mconf_id
JOIN run r ON r.run_id = mc.mconf_run_id
JOIN workflow wf ON wf.wf_id = r.run_wf_id
JOIN project p ON p.proj_id = wf.wf_proj_id;

-- Regressions-Views ergaenzen die bestehenden Klassifikations-Views, ohne
-- deren Schema zu veraendern. Kleinere RMSE-/MAE-Werte sind besser, groessere
-- R-Quadrat-Werte sind besser.
CREATE VIEW IF NOT EXISTS v_regr_model_results AS
SELECT
  p.proj_name,
  wf.wf_name,
  r.run_id,
  r.run_started_at,
  r.run_git_commit,
  mc.mconf_id,
  mc.mconf_algorithm,
  mc.mconf_feature_set,
  mc.mconf_preprocessing,
  mc.mconf_task_id,
  rs.rsmp_strategy,
  rs.rsmp_folds,
  rs.rsmp_ratio,
  MAX(CASE WHEN mr.mres_measure_name = 'regr.rmse' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS rmse,
  MAX(CASE WHEN mr.mres_measure_name = 'regr.mae' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS mae,
  MAX(CASE WHEN mr.mres_measure_name = 'regr.rsq' AND mr.mres_fold IS NULL THEN mr.mres_value END) AS rsq,
  MAX(mr.mres_elapsed_seconds) AS elapsed_seconds,
  (SELECT GROUP_CONCAT(h.hparam_name || '=' || h.hparam_value, ', ')
     FROM hyperparam h WHERE h.hparam_mconf_id = mc.mconf_id) AS hyperparams
FROM model_config mc
JOIN run r ON r.run_id = mc.mconf_run_id
JOIN workflow wf ON wf.wf_id = r.run_wf_id
JOIN project p ON p.proj_id = wf.wf_proj_id
JOIN metric_result mr ON mr.mres_mconf_id = mc.mconf_id
JOIN resampling rs ON rs.rsmp_id = mr.mres_rsmp_id
WHERE mc.mconf_task_type = 'regr'
GROUP BY mc.mconf_id;

CREATE VIEW IF NOT EXISTS v_regr_best_per_algorithm AS
SELECT * FROM (
  SELECT
    v.*,
    ROW_NUMBER() OVER (PARTITION BY mconf_algorithm ORDER BY rmse ASC) AS rn
  FROM v_regr_model_results v
  WHERE rmse IS NOT NULL
)
WHERE rn = 1;
