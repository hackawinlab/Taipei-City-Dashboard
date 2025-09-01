import csv
import requests
import time
import os

MAPBOX_API_KEY = "pk.eyJ1IjoieW9ydWtvdCIsImEiOiJjbTlwcWpweDgxNjdrMmtwcXRyMHFoZTc3In0.YRyOw_9O3B3KABWTeQUgWQ"
INPUT_FILE = "The Location of a hospital.csv"
OUTPUT_FILE = "converted.csv"
CACHE_FILE = "geocode_cache.csv"

SAVE_EVERY_N_ROWS = 5  # save every N rows so your progress doesn't vanish
MAX_RETRIES = 3

# 🗂️ Load address cache to avoid redundant lookups
def load_cache():
    cache = {}
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, newline='', encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) == 3:
                    cache[row[0]] = (row[1], row[2])
    return cache

def save_cache(cache):
    with open(CACHE_FILE, mode="w", newline='', encoding="utf-8") as f:
        writer = csv.writer(f)
        for address, (lat, lon) in cache.items():
            writer.writerow([address, lat, lon])

def geocode_address(address, cache):
    if address in cache:
        return cache[address]

    for attempt in range(MAX_RETRIES):
        try:
            url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{address}.json"
            params = {
                "access_token": MAPBOX_API_KEY,
                "limit": 1
            }
            response = requests.get(url, params=params)
            if response.status_code == 200:
                data = response.json()
                features = data.get("features")
                if features:
                    coords = features[0]["center"]
                    lat, lon = str(coords[1]), str(coords[0])
                    cache[address] = (lat, lon)
                    return lat, lon
                else:
                    print(f"⚠️ No result for: {address}")
                    break
            elif response.status_code == 429:
                wait = 2 ** attempt
                print(f"😤 Rate limited. Waiting {wait} seconds...")
                time.sleep(wait)
            else:
                print(f"💀 API error {response.status_code} for {address}")
                break
        except Exception as e:
            print(f"🔥 Exception during geocoding: {e}")
            time.sleep(2 ** attempt)

    return None, None

# 🚀 Process input
def process_csv():
    cache = load_cache()

    with open(INPUT_FILE, newline='', encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        rows = list(reader)

    output_rows = []
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, newline='', encoding="utf-8") as outfile:
            out_reader = csv.DictReader(outfile)
            output_rows = list(out_reader)

    processed_addresses = {row["地址"] for row in output_rows}
    new_rows = []

    for index, row in enumerate(rows):
        address = row["地址"]
        if address in processed_addresses:
            continue  # already done

        lat, lon = geocode_address(address, cache)
        row["latitude"] = lat if lat else ""
        row["longitude"] = lon if lon else ""
        new_rows.append(row)
        print(f"📍 {address} → lat: {lat}, lon: {lon}")

        if (index + 1) % SAVE_EVERY_N_ROWS == 0 or index == len(rows) - 1:
            output_rows.extend(new_rows)
            with open(OUTPUT_FILE, mode="w", newline='', encoding="utf-8") as f:
                fieldnames = list(row.keys())
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(output_rows)
            new_rows = []
            save_cache(cache)
            print("💾 Progress saved.")



    print("🎉 All done, nerd.")

if __name__ == "__main__":
    process_csv()

