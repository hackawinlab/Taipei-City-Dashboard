-- YouBike hackathon mock data
-- Run against the hackathon DB (default: postgres-manager port 5432, dbname=hackathon)
--
-- Setup:
--   sudo docker exec postgres-manager psql -U postgres -c "CREATE DATABASE hackathon;"
--   sudo docker exec -i postgres-manager psql -U postgres -d hackathon < db-sample-data/youbike-hackathon-mock.sql
--
-- Backend env vars to add:
--   DB_HACKATHON_HOST=localhost DB_HACKATHON_PORT=5432
--   DB_HACKATHON_USER=postgres DB_HACKATHON_PASSWORD=postgres
--   DB_HACKATHON_DBNAME=hackathon

CREATE TABLE IF NOT EXISTS youbike_snapshots (
  id              BIGSERIAL PRIMARY KEY,
  station_uid     VARCHAR(50)       NOT NULL,
  station_name    VARCHAR(100)      NOT NULL,
  lat             DOUBLE PRECISION  NOT NULL,
  lon             DOUBLE PRECISION  NOT NULL,
  city            VARCHAR(20)       NOT NULL,
  available_bikes INT               NOT NULL DEFAULT 0,
  total_docks     INT               NOT NULL DEFAULT 0,
  snapshot_at     TIMESTAMPTZ       NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_youbike_hour ON youbike_snapshots
  (city, (EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')));

-- Taipei stations × 24 hourly snapshots
-- Availability pattern: low rush (7-9, 17-19), high overnight (0-5)
INSERT INTO youbike_snapshots (station_uid, station_name, lat, lon, city, available_bikes, total_docks, snapshot_at)
SELECT
  s.uid, s.name, s.lat, s.lon, 'Taipei',
  GREATEST(0, ROUND(s.docks *
    CASE
      WHEN h BETWEEN 0 AND 5   THEN 0.65 + random()*0.20
      WHEN h BETWEEN 6 AND 9   THEN 0.08 + random()*0.12
      WHEN h BETWEEN 10 AND 11 THEN 0.45 + random()*0.20
      WHEN h BETWEEN 12 AND 13 THEN 0.35 + random()*0.15
      WHEN h BETWEEN 14 AND 16 THEN 0.50 + random()*0.20
      WHEN h BETWEEN 17 AND 19 THEN 0.05 + random()*0.10
      WHEN h BETWEEN 20 AND 21 THEN 0.30 + random()*0.20
      ELSE                           0.55 + random()*0.20
    END
  )::int),
  s.docks,
  ('2026-05-01 00:00:00+08'::timestamptz + (h || ' hours')::interval)
FROM (VALUES
  ('TPE001','捷運市政府站(2號出口)', 25.0408, 121.5647, 18),
  ('TPE002','捷運台北車站(M8)',       25.0478, 121.5171, 24),
  ('TPE003','台北101/世貿站',         25.0338, 121.5641, 20),
  ('TPE004','捷運信義安和站(2號出口)',25.0333, 121.5535, 16),
  ('TPE005','捷運大安站(2號出口)',    25.0278, 121.5433, 22),
  ('TPE006','捷運中山站(2號出口)',    25.0527, 121.5197, 20),
  ('TPE007','師範大學附近',           25.0225, 121.5307, 14),
  ('TPE008','公館捷運站',             25.0143, 121.5339, 28),
  ('TPE009','捷運古亭站(7號出口)',    25.0207, 121.5202, 18),
  ('TPE010','捷運南京東路站',         25.0522, 121.5437, 20),
  ('TPE011','捷運忠孝復興站(3號出口)',25.0415, 121.5445, 16),
  ('TPE012','捷運東門站(5號出口)',    25.0341, 121.5253, 22),
  ('TPE013','北市府前廣場',           25.0457, 121.5168, 30),
  ('TPE014','建國南路',               25.0343, 121.5387, 18),
  ('TPE015','木柵路/和平東路口',      25.0135, 121.5645, 12)
) AS s(uid, name, lat, lon, docks)
CROSS JOIN generate_series(0, 23) AS h;

-- NewTaipei stations × 24 hourly snapshots
INSERT INTO youbike_snapshots (station_uid, station_name, lat, lon, city, available_bikes, total_docks, snapshot_at)
SELECT
  s.uid, s.name, s.lat, s.lon, 'NewTaipei',
  GREATEST(0, ROUND(s.docks *
    CASE
      WHEN h BETWEEN 0 AND 5   THEN 0.60 + random()*0.25
      WHEN h BETWEEN 6 AND 9   THEN 0.10 + random()*0.15
      WHEN h BETWEEN 10 AND 16 THEN 0.40 + random()*0.25
      WHEN h BETWEEN 17 AND 19 THEN 0.08 + random()*0.12
      ELSE                           0.50 + random()*0.25
    END
  )::int),
  s.docks,
  ('2026-05-01 00:00:00+08'::timestamptz + (h || ' hours')::interval)
FROM (VALUES
  ('NTP001','板橋車站(南)',   25.0147, 121.4627, 28),
  ('NTP002','新莊體育場',     25.0365, 121.4418, 20),
  ('NTP003','三重區公所',     25.0753, 121.4939, 16),
  ('NTP004','中和景平路',     24.9987, 121.5012, 18),
  ('NTP005','永和國小',       25.0090, 121.5130, 14),
  ('NTP006','新店捷運站',     24.9717, 121.5378, 22),
  ('NTP007','淡水捷運站',     25.1714, 121.4440, 20),
  ('NTP008','汐止火車站',     25.0644, 121.6588, 16)
) AS s(uid, name, lat, lon, docks)
CROSS JOIN generate_series(0, 23) AS h;

-- Make high-traffic stations empty at rush hours for realistic shortage/blacklist data
UPDATE youbike_snapshots SET available_bikes = 0
WHERE station_uid IN ('TPE002','TPE008','TPE013','NTP001')
  AND EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei') IN (7,8,9);

UPDATE youbike_snapshots SET available_bikes = 0
WHERE station_uid IN ('TPE002','TPE006','TPE010','NTP001','NTP007')
  AND EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei') IN (17,18,19);

UPDATE youbike_snapshots SET available_bikes = 1
WHERE station_uid IN ('TPE001','TPE004','TPE009','NTP003')
  AND EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei') IN (7,8,17,18);
