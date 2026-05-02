import time
import logging
import requests
import psycopg2
import psycopg2.extras
import os
from datetime import datetime, timezone, timedelta

TPE_TZ = timezone(timedelta(hours=8))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

URL = "https://apis.youbike.com.tw/json/station-yb2.json"
INTERVAL = 60  # seconds

CITY_MAP = {"5001": "台北市", "5002": "新北市"}

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "postgres-data"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
    "dbname": os.getenv("DB_NAME", "dashboard"),
}

DEFAULT_TABLE = "youbike_immediate"
HISTORY_TABLE = "youbike_immediate_history"

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS {table} (
    sno                  VARCHAR(20),
    city                 VARCHAR(10),
    sna                  VARCHAR(100),
    snaen                VARCHAR(200),
    sarea                VARCHAR(50),
    sareaen              VARCHAR(100),
    addr                 VARCHAR(200),
    adren                VARCHAR(200),
    status               SMALLINT,
    data_time            TIMESTAMPTZ,
    total_bikes          INTEGER,
    available_rent_bikes INTEGER,
    yb2_quantity         INTEGER,
    eyb_quantity         INTEGER,
    available_return_bikes INTEGER,
    longitude            NUMERIC(10, 6),
    latitude             NUMERIC(10, 6),
    wkb_geometry         GEOMETRY(Point, 4326)
);
"""

CREATE_HISTORY_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS {table} (
    id                   SERIAL PRIMARY KEY,
    sno                  VARCHAR(20),
    city                 VARCHAR(10),
    sna                  VARCHAR(100),
    snaen                VARCHAR(200),
    sarea                VARCHAR(50),
    sareaen              VARCHAR(100),
    addr                 VARCHAR(200),
    adren                VARCHAR(200),
    status               SMALLINT,
    data_time            TIMESTAMPTZ,
    total_bikes          INTEGER,
    available_rent_bikes INTEGER,
    yb2_quantity         INTEGER,
    eyb_quantity         INTEGER,
    available_return_bikes INTEGER,
    longitude            NUMERIC(10, 6),
    latitude             NUMERIC(10, 6),
    wkb_geometry         GEOMETRY(Point, 4326)
);
"""

INSERT_SQL = """
INSERT INTO {table} (
    sno, city, sna, snaen, sarea, sareaen, addr, adren,
    status, data_time, total_bikes,
    available_rent_bikes, yb2_quantity, eyb_quantity,
    available_return_bikes, longitude, latitude, wkb_geometry
) VALUES (
    %(sno)s, %(city)s, %(sna)s, %(snaen)s, %(sarea)s, %(sareaen)s,
    %(addr)s, %(adren)s, %(status)s, %(data_time)s, %(total_bikes)s,
    %(available_rent_bikes)s, %(yb2_quantity)s, %(eyb_quantity)s,
    %(available_return_bikes)s, %(longitude)s, %(latitude)s,
    ST_SetSRID(ST_MakePoint(%(longitude)s, %(latitude)s), 4326)
);
"""


HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "zh-TW,zh;q=0.9,en;q=0.8",
    "Referer": "https://www.youbike.com.tw/",
}


def fetch_data():
    resp = requests.get(URL, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    return resp.json()


def parse_tpe_time(s):
    if not s:
        return None
    return datetime.strptime(s, "%Y-%m-%d %H:%M:%S").replace(tzinfo=TPE_TZ)


def to_row(item):
    sno = item.get("station_no", "")
    detail = item.get("available_spaces_detail") or {}
    return {
        "sno": sno,
        "city": CITY_MAP.get(sno[:4], ""),
        "sna": item.get("name_tw", ""),
        "snaen": item.get("name_en", ""),
        "sarea": item.get("district_tw", ""),
        "sareaen": item.get("district_en", ""),
        "addr": item.get("address_tw", ""),
        "adren": item.get("address_en", ""),
        "status": int(item.get("status", 0)),
        "data_time": parse_tpe_time(item.get("updated_at")),
        "total_bikes": int(item.get("parking_spaces", 0)),
        "available_rent_bikes": int(item.get("available_spaces", 0)),
        "yb2_quantity": int(detail.get("yb2", 0)),
        "eyb_quantity": int(detail.get("eyb", 0)),
        "available_return_bikes": int(item.get("empty_spaces", 0)),
        "longitude": float(item.get("lng", 0)),
        "latitude": float(item.get("lat", 0)),
    }


def run_once(conn):
    raw = fetch_data()
    rows = [to_row(r) for r in raw if r.get("station_no", "")[:4] in CITY_MAP]

    with conn.cursor() as cur:
        cur.execute(CREATE_TABLE_SQL.format(table=DEFAULT_TABLE))
        cur.execute(CREATE_HISTORY_TABLE_SQL.format(table=HISTORY_TABLE))

        cur.execute(f"DELETE FROM {DEFAULT_TABLE};")
        psycopg2.extras.execute_batch(
            cur, INSERT_SQL.format(table=DEFAULT_TABLE), rows, page_size=500
        )
        psycopg2.extras.execute_batch(
            cur, INSERT_SQL.format(table=HISTORY_TABLE), rows, page_size=500
        )

    conn.commit()
    log.info("Updated %d stations (Taipei + New Taipei)", len(rows))


def main():
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = psycopg2.connect(**DB_CONFIG)
                log.info("Connected to database")

            run_once(conn)

        except psycopg2.OperationalError as e:
            log.error("DB connection error: %s — reconnecting next cycle", e)
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass
            conn = None

        except Exception as e:
            log.error("Error: %s", e)

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
