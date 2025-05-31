import pandas as pd

df = pd.read_excel("Locations of all hospitals in Taiwan.ods", engine="odf")

cities = df
print(cities)
