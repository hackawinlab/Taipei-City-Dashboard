-- Minimal patch to add the 'taipei' / 'metrotaipei' public groups and
-- the two 'map-layers-*' dashboards that host the YouBike time-series
-- map component. Other public dashboards (long-term care, transport)
-- are intentionally omitted — this branch only needs YouBike-related
-- surfaces.
-- Idempotent: ON CONFLICT DO NOTHING + sequence reseed.

-- 1. Public groups (id 2, 3)
INSERT INTO groups (id, name, is_personal, create_by) VALUES
  (2, 'taipei', false, NULL),
  (3, 'metrotaipei', false, NULL)
ON CONFLICT (id) DO NOTHING;

SELECT setval('groups_id_seq', GREATEST((SELECT MAX(id) FROM groups), 3));

-- 2. Public dashboards: only the two map-layers shells.
INSERT INTO dashboards (id, index, name, components, icon, updated_at, created_at) VALUES
  (106, 'map-layers-taipei',      '圖資資訊', '{217}', 'public', '2025-03-12 01:59:00+00', '2024-03-21 10:04:24+00'),
  (359, 'map-layers-metrotaipei', '圖資資訊', '{217}', 'public', '2024-05-16 03:56:12+00', '2024-03-21 10:04:24+00')
ON CONFLICT (id) DO NOTHING;

SELECT setval('dashboards_id_seq', GREATEST((SELECT MAX(id) FROM dashboards), 359));

-- 3. dashboard ↔ group links
INSERT INTO dashboard_groups (dashboard_id, group_id) VALUES
  (106, 2),
  (359, 3)
ON CONFLICT (dashboard_id, group_id) DO NOTHING;

-- 4. Add youbike_timemap to the map-layers dashboards so that the
--    YouBike 一日可用率動態地圖 shows up under 圖資資訊 in both groups.
UPDATE dashboards
   SET components = ARRAY(
         SELECT DISTINCT x FROM unnest(
           components || ARRAY[(SELECT id FROM components WHERE index = 'youbike_timemap')]
         ) AS t(x)
         WHERE x IS NOT NULL
       )
 WHERE index IN ('map-layers-taipei', 'map-layers-metrotaipei')
   AND EXISTS (SELECT 1 FROM components WHERE index = 'youbike_timemap');
