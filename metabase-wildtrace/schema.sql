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
CREATE OR REPLACE FUNCTION safe_number(value text) RETURNS double precision LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF value IS NULL OR value !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' THEN RETURN NULL; END IF;
 RETURN value::double precision;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;
CREATE OR REPLACE VIEW v_environment AS
SELECT DISTINCT r.day, r.fingerprint, r.payload,
 r.payload->>'temperature' AS temperature,
 r.payload->>'humidity' AS humidity,
 r.payload->>'luminosity' AS luminosity,
 r.payload->>'concentration_co2' AS concentration_co2,
 r.payload #>> '{timestamp}' AS timestamp,
 r.payload #>> '{local_timestamp}' AS local_timestamp,
 r.payload #>> '{timezone}' AS timezone,
 r.payload #>> '{formatted_ddmmyyyy}' AS formatted_ddmmyyyy,
 r.payload #>> '{gps_coordinates}' AS gps_coordinates,
 r.payload #>> '{city}' AS city,
 r.payload #>> '{country}' AS country,
 r.payload #>> '{formatted_address}' AS formatted_address,
 r.payload #>> '{aquatic_location}' AS aquatic_location,
 r.payload #>> '{latitude_source}' AS latitude_source,
 r.payload #>> '{longitude_source}' AS longitude_source,
 r.payload #>> '{temperature_source}' AS temperature_source,
 r.payload #>> '{humidity_source}' AS humidity_source,
 r.payload #>> '{luminosity_source}' AS luminosity_source,
 r.payload #>> '{concentration_co2_source}' AS concentration_co2_source,
 r.payload #>> '{altitude_source}' AS altitude_source,
 r.payload #>> '{climat}' AS climat,
 r.payload #>> '{hemisphere}' AS hemisphere,
 r.payload #>> '{season}' AS season,
 safe_number(r.payload #>> '{latitude}') AS latitude,
 safe_number(r.payload #>> '{longitude}') AS longitude,
 safe_number(r.payload #>> '{pressure}') AS pressure,
 safe_number(r.payload #>> '{white_luminosity}') AS white_luminosity,
 safe_number(r.payload #>> '{altitude}') AS altitude,
 safe_number(r.payload #>> '{distance_equator}') AS distance_equator,
 safe_number(r.payload #>> '{distance_equator_km}') AS distance_equator_km,
 safe_number(r.payload #>> '{distance_coastline}') AS distance_coastline,
 safe_number(r.payload #>> '{temperature}') AS temperature_value,
 safe_number(r.payload #>> '{humidity}') AS humidity_value,
 safe_number(r.payload #>> '{luminosity}') AS luminosity_value,
 safe_number(r.payload #>> '{concentration_co2}') AS concentration_co2_value,
 CASE r.payload->>'is_night' WHEN 'true' THEN true WHEN 'false' THEN false ELSE NULL END AS is_night,
 r.payload->'moods' AS moods,
 r.payload->'environments' AS environments,
 r.payload->'reconstruction' AS reconstruction,
 r.payload->'biological' AS biological,
 safe_number(r.payload #>> '{biological,sleep_duration_score}') AS biological_sleep_duration_score,
 safe_number(r.payload #>> '{biological,hrv_baseline_ms}') AS biological_hrv_baseline_ms,
 safe_number(r.payload #>> '{biological,hrv_baseline_days}') AS biological_hrv_baseline_days,
 safe_number(r.payload #>> '{biological,hrv_change_percent}') AS biological_hrv_change_percent,
 safe_number(r.payload #>> '{biological,stress_score}') AS biological_stress_score,
 r.payload #>> '{biological,date}' AS biological_date,
 r.payload #>> '{biological,source}' AS biological_source,
 r.payload #>> '{biological,sleep_score_source}' AS biological_sleep_score_source,
 r.payload #>> '{biological,stress_status}' AS biological_stress_status,
 r.payload #> '{biological,summary}' AS biological_summary
FROM records r JOIN objects o USING(bucket,name)
WHERE r.kind='context_environment' AND o.status='ok';
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
 safe_number(r.payload->'summary'->>'hrv_avg_ms') AS hrv_avg_ms,
 r.payload AS payload,
 r.payload->'city_country' AS city_country,
 r.payload->'location_metadata' AS location_metadata,
 r.payload #>> '{schema_version}' AS schema_version,
 r.payload #>> '{date}' AS date,
 r.payload #>> '{timezone}' AS timezone,
 r.payload #>> '{generated_at}' AS generated_at,
 r.payload #>> '{source_raw_file}' AS source_raw_file,
 COALESCE(NULLIF(r.payload #>> '{city_country,city}', ''), NULLIF(r.payload #>> '{city}', '')) AS city,
 COALESCE(NULLIF(r.payload #>> '{city_country,country}', ''), NULLIF(r.payload #>> '{country}', '')) AS country,
 COALESCE(NULLIF(r.payload #>> '{city_country,formatted_address}', ''), NULLIF(r.payload #>> '{formatted_address}', '')) AS formatted_address,
 COALESCE(NULLIF(r.payload #>> '{city_country,aquatic_location}', ''), NULLIF(r.payload #>> '{aquatic_location}', '')) AS aquatic_location,
 safe_number(r.payload #>> '{summary,heart_rate_avg}') AS heart_rate_avg,
 safe_number(r.payload #>> '{summary,heart_rate_min}') AS heart_rate_min,
 safe_number(r.payload #>> '{summary,heart_rate_max}') AS heart_rate_max,
 safe_number(r.payload #>> '{summary,oxygen_saturation_avg_percent}') AS oxygen_saturation_avg_percent,
 safe_number(r.payload #>> '{summary,respiratory_rate_avg}') AS respiratory_rate_avg,
 safe_number(r.payload #>> '{summary,steps_total}') AS steps_total,
 safe_number(r.payload #>> '{summary,active_energy_kcal}') AS active_energy_kcal,
 safe_number(r.payload #>> '{summary,basal_energy_kcal}') AS basal_energy_kcal,
 safe_number(r.payload #>> '{summary,distance_walking_running_meters}') AS distance_walking_running_meters,
 safe_number(r.payload #>> '{summary,sleep_duration_hours}') AS sleep_duration_hours,
 safe_number(r.payload #>> '{summary,workout_count}') AS workout_count,
 safe_number(r.payload #>> '{computed_metrics,sleep_duration_score}') AS sleep_duration_score,
 safe_number(r.payload #>> '{computed_metrics,hrv_baseline_ms}') AS hrv_baseline_ms,
 safe_number(r.payload #>> '{computed_metrics,hrv_baseline_days}') AS hrv_baseline_days,
 safe_number(r.payload #>> '{computed_metrics,hrv_change_percent}') AS hrv_change_percent,
 safe_number(r.payload #>> '{computed_metrics,stress_score}') AS stress_score,
 r.payload #>> '{computed_metrics,sleep_score_source}' AS sleep_score_source,
 r.payload #>> '{computed_metrics,stress_status}' AS stress_status,
 r.payload #>> '{location_metadata,captured_at}' AS location_captured_at,
 r.payload #>> '{location_metadata,source}' AS location_source,
 r.payload #>> '{location_metadata,method}' AS location_method,
 safe_number(r.payload #>> '{location_metadata,horizontal_accuracy_meters}') AS location_horizontal_accuracy_meters
FROM records r JOIN objects o USING(bucket,name) WHERE r.kind='biological' AND o.status='ok';
CREATE OR REPLACE VIEW v_import_errors AS SELECT bucket,name,kind,status,error,imported_at FROM objects WHERE status<>'ok';
CREATE OR REPLACE VIEW v_context_parts AS SELECT day,count(DISTINCT (bucket,name)) AS file_parts FROM records r JOIN objects o USING(bucket,name) WHERE r.kind='context_environment' AND o.status='ok' GROUP BY day;
