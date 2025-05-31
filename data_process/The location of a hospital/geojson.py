import csv
import json

def csv_to_geojson(csv_file_path, geojson_file_path):
    features = []

    with open(csv_file_path, newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            if row["city"] == "新北市":
                continue
            lat = float(row["latitude"])
            lng = float(row["longitude"])
            feature = {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [lng, lat]
                },
                "properties": {
                    "name": row["\ufeffname"],
                    "address": row["地址"]
                }
            }
            features.append(feature)

    geojson = {
        "type": "FeatureCollection",
        "features": features
    }

    with open(geojson_file_path, 'w', encoding='utf-8') as f:
        json.dump(geojson, f, ensure_ascii=False, indent=2)

# Example usage
csv_to_geojson('output_with_city.csv', 'outgeo ttp.geojson')
