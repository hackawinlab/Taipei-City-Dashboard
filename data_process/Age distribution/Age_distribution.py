import pandas as pd

def TP():
    df_TP = pd.read_csv('114-TP.csv')

    # 資料塞選
    age_columns = ["性別", "未滿1~4歲"] + [f"{i}~{i+4}歲" for i in range(5, 100, 5)] + ["100歲以上"]
    df_TP = df_TP[(df_TP["統計期"] == "114年 1月底") & (df_TP["性別"] != "總計")]
    df_TP = df_TP[age_columns].reset_index(drop=True)
    
    print(df_TP)
    
    # 年齡段重組成新北市格式
    new_age_labels = [
        "0~9歲", "10~19歲", "20~29歲", "30~39歲", "40~49歲",
        "50~59歲", "60~69歲", "70~79歲", "80~89歲", "90~99歲", "100歲以上"
    ]

    # 分段加總：每兩欄相加（男、女分別處理）
    male = df_TP[df_TP["性別"] == "男"].iloc[0, 1:].tolist()
    female = df_TP[df_TP["性別"] == "女"].iloc[0, 1:].tolist()

    # 手動合併為每10歲區間
    def group_age(data):
        grouped = [
            data[0] + data[1],  # 0~9
            data[2] + data[3],  # 10~19
            data[4] + data[5],  # 20~29
            data[6] + data[7],  # 30~39
            data[8] + data[9],  # 40~49
            data[10] + data[11],  # 50~59
            data[12] + data[13],  # 60~69
            data[14] + data[15],  # 70~79
            data[16] + data[17],  # 80~89
            data[18] + data[19],  # 90~99
            data[20]  # 100歲以上
        ]
        return grouped

    grouped_male = group_age(male)
    grouped_female = group_age(female)

    # 合併為 DataFrame
    df_result = pd.DataFrame({
        "年齡": new_age_labels,
        "男": grouped_male,
        "女": grouped_female
    })

    print(f"台北市：{df_result}")
    return df_result

def NTP():
    df_NTP = pd.read_csv('114-1-NTP.csv', encoding='big5', nrows=101)

    # 資料塞選
    df_NTP = df_NTP[["年齡", "男", "女"]]

    # 資料運算
    group = df_NTP.index // 10
    df_NTP = df_NTP.groupby(group).sum().reset_index(drop=True)
    df_NTP 
    df_NTP["年齡"] = [
        "0~9歲", "10~19歲", "20~29歲", "30~39歲", "40~49歲",
        "50~59歲", "60~69歲", "70~79歲", "80~89歲", "90~99歲",
        "100歲以上"
    ]
    print(f"新北市：{df_NTP}")
    return df_NTP

def combine_TP_NTP(df_TP, df_NTP):
    # 合併台北與新北資料，根據「年齡」欄位對齊
    df_merged = pd.merge(df_TP, df_NTP, on="年齡", suffixes=('_TP', '_NTP'))

    # 建立新表格，男 = 台北男 + 新北男，女 同理
    df_result = pd.DataFrame()
    df_result["年齡"] = df_merged["年齡"]
    df_result["男"] = df_merged["男_TP"] + df_merged["男_NTP"]
    df_result["女"] = df_merged["女_TP"] + df_merged["女_NTP"]

    return df_result

df_NTP = NTP()
df_TP = TP()
df = combine_TP_NTP(df_TP, df_NTP)

df_TP.to_csv("Age_distribution_TP.csv", index=False, encoding="utf-8-sig")
df.to_csv("Age_distribution.csv", index=False, encoding="utf-8-sig")