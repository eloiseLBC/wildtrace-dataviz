CREATE TABLE IF NOT EXISTS settings (id boolean PRIMARY KEY DEFAULT true CHECK(id), start_day date NOT NULL, report_timezone text NOT NULL);
CREATE TABLE IF NOT EXISTS sync_runs (id bigserial PRIMARY KEY, started_at timestamptz DEFAULT now(), finished_at timestamptz, status text DEFAULT 'running', imported int DEFAULT 0, errors int DEFAULT 0);
CREATE TABLE IF NOT EXISTS bucket_scans (run_id bigint REFERENCES sync_runs, bucket text, success boolean, PRIMARY KEY(run_id,bucket));
CREATE TABLE IF NOT EXISTS objects (bucket text, name text, etag text, kind text, status text, imported_at timestamptz, last_seen_run bigint, error text, PRIMARY KEY(bucket,name));
CREATE TABLE IF NOT EXISTS records (bucket text, name text, ordinal int, kind text, day date, fingerprint text, payload jsonb, PRIMARY KEY(bucket,name,ordinal), FOREIGN KEY(bucket,name) REFERENCES objects ON DELETE CASCADE);
CREATE INDEX IF NOT EXISTS records_day ON records(day,kind);
CREATE OR REPLACE VIEW v_coverage AS
WITH calendar AS (
 SELECT generate_series(s.start_day, (now() AT TIME ZONE s.report_timezone)::date, interval '1 day')::date AS day FROM settings s
), flags AS (
 SELECT r.day, bool_or(r.kind='pending') AS pending,
 bool_or(r.kind='computed') AS environmental_computed,
 bool_or(r.kind='biological') AS biological_present,
 bool_or(r.kind='context_environment') AS contextualized_present
 FROM records r JOIN objects o USING(bucket,name) WHERE o.status='ok' GROUP BY r.day
)
SELECT c.day, coalesce(f.pending,false) AS pending,
 coalesce(f.environmental_computed,false) AS environmental_computed,
 coalesce(f.biological_present,false) AS biological_present,
 coalesce(f.contextualized_present,false) AS contextualized_present,
 CASE WHEN contextualized_present THEN 'Contextualisation disponible'
 WHEN environmental_computed AND biological_present THEN 'Sources disponibles, sortie absente'
 WHEN environmental_computed THEN 'Environnement calculé, biologie absente'
 WHEN pending THEN 'Données en attente de calcul'
 WHEN biological_present THEN 'Biologie disponible, environnement absent'
 ELSE 'Aucune donnée importée' END AS observed_status,
 c.day=(now() AT TIME ZONE (SELECT report_timezone FROM settings))::date AS current_day
FROM calendar c LEFT JOIN flags f USING(day);
CREATE OR REPLACE VIEW v_environment AS
SELECT DISTINCT r.day, r.fingerprint, r.payload,
 r.payload->>'temperature' AS temperature,
 r.payload->>'humidity' AS humidity,
 r.payload->>'luminosity' AS luminosity,
 r.payload->>'concentration_co2' AS concentration_co2
FROM records r JOIN objects o USING(bucket,name)
WHERE r.kind='context_environment' AND o.status='ok';
CREATE OR REPLACE FUNCTION safe_number(value text) RETURNS double precision LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF value IS NULL OR value !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' THEN RETURN NULL; END IF;
 RETURN value::double precision;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;
CREATE OR REPLACE VIEW v_daily_environment AS
SELECT day, count(*) AS distinct_measurements,
 avg(safe_number(temperature)) AS temperature_avg,
 min(safe_number(temperature)) AS temperature_min,
 max(safe_number(temperature)) AS temperature_max,
 avg(safe_number(humidity)) AS humidity_avg,
 avg(safe_number(luminosity)) AS luminosity_avg,
 avg(safe_number(concentration_co2)) AS co2_avg,
 count(*) FILTER (WHERE safe_number(temperature) IS NULL) AS missing_or_invalid_temperature,
 count(*) FILTER (WHERE safe_number(humidity) IS NULL) AS missing_or_invalid_humidity,
 count(*) FILTER (WHERE safe_number(humidity)<0 OR safe_number(humidity)>100) AS humidity_out_of_bounds,
 count(*) FILTER (WHERE payload->'reconstruction' IS NOT NULL AND payload->'reconstruction' NOT IN ('null'::jsonb,'false'::jsonb)) AS reconstructed_measurements
FROM v_environment GROUP BY day;
CREATE OR REPLACE VIEW v_biological AS
SELECT r.day, r.bucket, r.name, r.payload->'summary' AS summary,
 r.payload->'computed_metrics' AS computed_metrics,
 safe_number(r.payload->'summary'->>'sleep_duration_hours') AS sleep_hours,
 safe_number(r.payload->'summary'->>'hrv_avg_ms') AS hrv_avg_ms
FROM records r JOIN objects o USING(bucket,name) WHERE r.kind='biological' AND o.status='ok';
CREATE OR REPLACE VIEW v_import_errors AS SELECT bucket,name,kind,status,error,imported_at FROM objects WHERE status<>'ok';
CREATE OR REPLACE VIEW v_context_parts AS SELECT day,count(DISTINCT (bucket,name)) AS file_parts FROM records r JOIN objects o USING(bucket,name) WHERE r.kind='context_environment' AND o.status='ok' GROUP BY day;
