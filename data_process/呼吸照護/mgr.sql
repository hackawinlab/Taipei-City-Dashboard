INSERT INTO public.component_charts (index, color, types, unit) VALUES ('breathing_hospital_location', '{#3E8DDD,#EF5B9C}', '{DistrictChart}', '?');
INSERT INTO public.component_maps (id, index, title, type, source, size, icon, paint, property) VALUES (105, 'breathing_hospital_location_tpe', '????????', 'symbol', 'geojson', null, 'lung', '{"circle-color":  "green", "circle-radius":  10}', '[{"key":"name","name":"??"},{"key":"address","name":"??"}]');
INSERT INTO public.component_maps (id, index, title, type, source, size, icon, paint, property) VALUES (104, 'breathing_hospital_location', '????????', 'symbol', 'geojson', null, 'lung', '{"circle-color":  "green", "circle-radius":  10}', '[{"key":"name","name":"??"},{"key":"address","name":"??"}]');

INSERT INTO public.components (id, index, name) VALUES (334, 'breathing_hospital_location', '呼吸照護醫療院所');
UPDATE public.dashboards
SET components = '{217,219,333,334}'
WHERE id = 359;

INSERT INTO public.query_charts (index, history_config, map_config_ids, map_filter, time_from, time_to, update_freq, update_freq_unit, source, short_desc, long_desc, use_case, links, contributors, created_at, updated_at, query_type, query_chart, query_history, city) VALUES ('breathing_hospital_location', null, '{105}', '{}', 'static', null, null, null, 'Me', 'Me', 'Me', 'Me', '{https://google.com}', '{doit,ntpc}', '2025-05-31 14:01:37.401000 +00:00', '2025-05-31 14:01:40.155000 +00:00', 'two_d', e'SELECT x_axis, SUM(data) AS data
FROM (
    SELECT district AS x_axis, COUNT(*) AS data
    FROM breathing_hospital_location
    WHERE city = \'臺北市\'
    GROUP BY district
) AS d
WHERE x_axis != \'\'
GROUP BY x_axis
ORDER BY data DESC;
', null, 'taipei');
INSERT INTO public.query_charts (index, history_config, map_config_ids, map_filter, time_from, time_to, update_freq, update_freq_unit, source, short_desc, long_desc, use_case, links, contributors, created_at, updated_at, query_type, query_chart, query_history, city) VALUES ('breathing_hospital_location', null, '{104}', '{}', 'static', null, null, null, 'Me', 'Me', 'Me', 'Me', '{https://google.com}', '{doit,ntpc}', '2025-05-31 14:01:37.401000 +00:00', '2025-05-31 14:01:40.155000 +00:00', 'two_d', e'SELECT x_axis, SUM(data) AS data
FROM (
    SELECT district AS x_axis, COUNT(*) AS data
    FROM breathing_hospital_location
    WHERE city = \'臺北市\'
    GROUP BY district

    UNION ALL

    SELECT district AS x_axis, COUNT(*) AS data
    FROM breathing_hospital_location
    WHERE city = \'新北市\'
    GROUP BY district
) AS d
WHERE x_axis != \'\'
GROUP BY x_axis
ORDER BY data DESC;
', null, 'metrotaipei');
