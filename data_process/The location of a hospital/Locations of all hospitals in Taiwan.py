import pandas as pd

# 讀取 .ods 檔案
df = pd.read_excel('Locations of all hospitals in Taiwan.ods', engine='odf')

# 資料塞選
df = df[["機構名稱", "縣市區名", "地址","電話"]]
df["地址"] = df["地址"].str.replace(r"(號).*", r"\1", regex=True)

print(df)
# # 資料塞選
# df = df[["機構名稱", "縣市區名", "地址" , ""]]
# df["地址"] = df["地址"].str.replace(r"(號).*", r"\1", regex=True)

# print(df)

# df_TP= df[df["縣市區名"].str[:3].isin(["臺北市"])]
# df = df[df["縣市區名"].str[:3].isin(["臺北市", "新北市"])]

# df["縣市區名"] = df["縣市區名"].str[3:]
# df_TP["縣市區名"] = df_TP["縣市區名"].str[3:]

# df.to_csv("The Location of a hospital.csv", index=False, encoding="utf-8-sig")
# df_TP.to_csv("The Location of a hospital(TP).csv", index=False, encoding="utf-8-sig")