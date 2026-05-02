-- "共享單車" dashboard tab
-- Adds one dashboard per city (taipei + metrotaipei) so the sidebar shows
-- a "共享單車" tab under each city section.
-- Idempotent: safe to re-run.

-- 1. Dashboards (one per city, both named "共享單車")
--    Components: youbike_timemap(1), youbike_availability(60), bike_network(213), bike_map(217)
INSERT INTO dashboards (index, name, components, icon, updated_at, created_at)
VALUES
  ('youbike-analysis-taipei',      '共享單車', '{1,60,217,213}', 'pedal_bike', NOW(), NOW()),
  ('youbike-analysis-metrotaipei', '共享單車', '{1,60,217,213}', 'pedal_bike', NOW(), NOW())
ON CONFLICT (index) DO UPDATE
  SET name = EXCLUDED.name,
      components = EXCLUDED.components,
      icon = EXCLUDED.icon,
      updated_at = NOW();

-- 2. Wire each dashboard into its city group
INSERT INTO dashboard_groups (dashboard_id, group_id)
SELECT d.id, g.id
FROM dashboards d
JOIN groups g ON
  (d.index = 'youbike-analysis-taipei'      AND g.name = 'taipei') OR
  (d.index = 'youbike-analysis-metrotaipei' AND g.name = 'metrotaipei')
ON CONFLICT (dashboard_id, group_id) DO NOTHING;
