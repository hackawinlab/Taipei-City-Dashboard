import pandas as pd

# 讀取 .ods 檔案
df = pd.read_csv('AED20250531.csv')

# 資料塞選
df = df[["場所名稱", "場所縣市","場所區域","場所地址","地點LAT","地點LNG"]]
df["場所地址"] = df["場所地址"].str.replace(r"(號).*", r"\1", regex=True)

df_TP= df[df["場所縣市"].isin(["臺北市"])]
df = df[df["場所縣市"].isin(["臺北市", "新北市"])]

print(f"台北市\n{df_TP}")
print(f"台北市、新北市\n{df}")

df.to_csv("The Location of a hospital.csv", index=False, encoding="utf-8-sig")
df_TP.to_csv("The Location of a hospital(TP).csv", index=False, encoding="utf-8-sig")