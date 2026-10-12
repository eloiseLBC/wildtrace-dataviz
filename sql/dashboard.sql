-- Chaque requête devient une question Metabase à enregistrer.
-- 1. Nombre de jours contextualisés (nombre, hors journée en cours)
SELECT count(*) AS jours_contextualises FROM v_coverage WHERE contextualized_present AND NOT current_day;
-- 2. Nombre de jours environnementaux calculés (nombre)
SELECT count(*) AS jours_calcules FROM v_coverage WHERE environmental_computed AND NOT current_day;
-- 3. Dates sans contextualisation (table)
SELECT * FROM v_coverage WHERE NOT contextualized_present AND NOT current_day ORDER BY day;
-- 4. Calendrier de couverture (table avec couleurs conditionnelles)
SELECT * FROM v_coverage ORDER BY day DESC;
-- 5. Evolution environnementale (courbes, axe X = day)
SELECT * FROM v_daily_environment ORDER BY day;
-- 6. Qualité (table)
SELECT day,distinct_measurements,missing_or_invalid_temperature,missing_or_invalid_humidity,humidity_out_of_bounds,reconstructed_measurements FROM v_daily_environment ORDER BY day DESC;
-- 7. Erreurs et objets disparus (table)
SELECT * FROM v_import_errors;
-- 8. Historique des synchronisations (table)
SELECT * FROM sync_runs ORDER BY started_at DESC LIMIT 100;
-- 9. Fraîcheur de la synchronisation (table)
SELECT max(finished_at) AS derniere_sync_reussie FROM sync_runs WHERE status='success';
-- 10. Biologie (courbes)
SELECT day,sleep_hours,hrv_avg_ms FROM v_biological ORDER BY day;
-- 11. Plusieurs parties contextualisées par date (table)
SELECT * FROM v_context_parts WHERE file_parts>1 ORDER BY day;
-- 12. État des lectures des buckets (table)
SELECT * FROM bucket_scans WHERE run_id=(SELECT max(id) FROM sync_runs);
