import csv
import requests
import time

MAPBOX_API_KEY = "your_mapbox_api_key_here"  # ← Replace with your actual key, genius

def geocode_address(address):
    url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{address}.json"
    params = {
        "access_token": "pk.eyJ1IjoieW9ydWtvdCIsImEiOiJjbTlwcWpweDgxNjdrMmtwcXRyMHFoZTc3In0.YRyOw_9O3B3KABWTeQUgWQ",
        "limit": 1
    }
    response = requests.get(url, params=params)
    if response.status_code == 200:
        data = response.json()
        features = data.get("features")
        if features:
            coords = features[0]["center"]
            return coords[1], coords[0]  # lat, lon
    return None, None

input_file = "The Location of a hospital.csv"
output_file = "converted.csv"

with open(input_file, newline='', encoding="utf-8") as csvfile:
    reader = csv.DictReader(csvfile)
    rows = list(reader)

# Add lat/lon and store updated rows
for row in rows:
    full_address = row["地址"]
    lat, lon = geocode_address(full_address)
    print(f"📍 {full_address} → lat: {lat}, lon: {lon}")
    row["latitude"] = lat
    row["longitude"] = lon
    time.sleep(0.5)  # 🐢 Don't slam Mapbox or you'll get rate-limited, you impatient koala

# Write new CSV
fieldnames = list(rows[0].keys())
with open(output_file, mode="w", newline='', encoding="utf-8") as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print("🐾 All done. Go pet yourself for surviving Python.")
