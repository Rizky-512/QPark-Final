-- Opt-in research schema: apply separately, never via operational db reset/push.
-- No operational tables, functions, auth policies or application APIs are changed.
BEGIN;
CREATE SCHEMA IF NOT EXISTS qpark_ml;
REVOKE ALL ON SCHEMA qpark_ml FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS qpark_ml.simulation_runs (
  run_id text PRIMARY KEY,
  source_kind text NOT NULL DEFAULT 'simulation' CHECK (source_kind = 'simulation'),
  snapshot jsonb NOT NULL CHECK (snapshot->>'source_kind' = 'simulation'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS qpark_ml.simulation_sessions (
  run_id text NOT NULL REFERENCES qpark_ml.simulation_runs(run_id),
  visit_id text NOT NULL CHECK (visit_id LIKE 'SIM-%'),
  entered_at timestamptz NOT NULL,
  exited_at timestamptz CHECK (exited_at >= entered_at),
  source_kind text NOT NULL DEFAULT 'simulation' CHECK (source_kind = 'simulation'),
  PRIMARY KEY (run_id, visit_id)
);
ALTER TABLE qpark_ml.simulation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE qpark_ml.simulation_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA qpark_ml FROM PUBLIC, anon, authenticated;
COMMENT ON SCHEMA qpark_ml IS 'QPark research only. SIMULATED data, not operational transactions.';
COMMIT;
