-- Fill missing (city, hour, quarter) slots in hackathon.youbike_snapshots.
-- For each absent slot, copy all stations from a random existing snapshot of
-- the same city, stamped at the target slot timestamp on 2026-05-01 (Asia/Taipei).
-- Idempotent: uses ON CONFLICT (station_uid, snapshot_at) DO NOTHING.

DO $$
DECLARE
    rec    RECORD;
    src_ts timestamptz;
    tgt_ts timestamptz;
BEGIN
    FOR rec IN
        WITH all_slots AS (
            SELECT h.h, q.q
            FROM generate_series(0, 23) AS h(h)
            CROSS JOIN generate_series(0, 3) AS q(q)
        ),
        present AS (
            SELECT
                city,
                EXTRACT(hour FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int AS h,
                (EXTRACT(minute FROM snapshot_at AT TIME ZONE 'Asia/Taipei') / 15)::int AS q
            FROM youbike_snapshots
            GROUP BY 1, 2, 3
        ),
        cities AS (
            SELECT DISTINCT city FROM youbike_snapshots
        )
        SELECT c.city, a.h, a.q
        FROM cities c
        CROSS JOIN all_slots a
        LEFT JOIN present p
          ON p.city = c.city AND p.h = a.h AND p.q = a.q
        WHERE p.h IS NULL
        ORDER BY c.city, a.h, a.q
    LOOP
        SELECT snapshot_at INTO src_ts
        FROM (
            SELECT DISTINCT snapshot_at
            FROM youbike_snapshots
            WHERE city = rec.city
        ) s
        ORDER BY random()
        LIMIT 1;

        tgt_ts := ('2026-05-01 '
                   || lpad(rec.h::text, 2, '0') || ':'
                   || lpad((rec.q * 15)::text, 2, '0')
                   || ':00 +08:00')::timestamptz;

        INSERT INTO youbike_snapshots
            (station_uid, station_name, lat, lon, city,
             available_bikes, electric_bikes, total_docks, snapshot_at)
        SELECT station_uid, station_name, lat, lon, city,
               available_bikes, electric_bikes, total_docks, tgt_ts
        FROM youbike_snapshots
        WHERE city = rec.city AND snapshot_at = src_ts
        ON CONFLICT (station_uid, snapshot_at) DO NOTHING;
    END LOOP;
END $$;
