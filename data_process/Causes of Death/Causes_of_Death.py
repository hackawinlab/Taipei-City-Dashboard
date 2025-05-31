import pandas as pd

def NTP():
    # 讀取 .ods 檔案
    NTP = pd.read_csv('Causes_of_Death_NTP.csv')

    # 設定新欄位名稱
    NTP.columns = [
        '年', '總計男', '總計女',
        '癌症男', '癌症女',
        '心臟疾病男', '心臟疾病女',
        '腦血管疾病男', '腦血管疾病女',
        '糖尿病男', '糖尿病女',
        '肺炎男', '肺炎女',
        '腎炎_腎徵候群及腎性病變男', '腎炎_腎徵候群及腎性病變女',
        '自殺男', '自殺女',
        '事故傷害男', '事故傷害女',
        '慢性肝病及肝硬化男', '慢性肝病及肝硬化女',
        '高血壓性疾病男', '高血壓性疾病女',
        '其他男', '其他女'
    ]

    NTP['總計'] = NTP['總計男'] + NTP['總計女']
    NTP['癌症'] = NTP['癌症男'] + NTP['癌症女']
    NTP['心臟疾病'] = NTP['心臟疾病男'] + NTP['心臟疾病女']
    NTP['腦血管疾病'] = NTP['腦血管疾病男'] + NTP['腦血管疾病女']
    NTP['糖尿病'] = NTP['糖尿病男'] + NTP['糖尿病女']
    NTP['肺炎'] = NTP['肺炎男'] + NTP['肺炎女']
    NTP['腎病'] = NTP['腎炎_腎徵候群及腎性病變男'] + NTP['腎炎_腎徵候群及腎性病變女']
    NTP['自殺'] = NTP['自殺男'] + NTP['自殺女']
    NTP['事故傷害'] = NTP['事故傷害男'] + NTP['事故傷害女']
    NTP['肝病'] = NTP['慢性肝病及肝硬化男'] + NTP['慢性肝病及肝硬化女']
    NTP['高血壓'] = NTP['高血壓性疾病女'] + NTP['高血壓性疾病女']
    NTP['其他'] = NTP['其他男'] + NTP['其他女']

    # 要刪除的欄位清單
    columns_to_drop = [
        '總計男', '總計女',
        '癌症男', '癌症女',
        '心臟疾病男', '心臟疾病女',
        '腦血管疾病男', '腦血管疾病女',
        '糖尿病男', '糖尿病女',
        '肺炎男', '肺炎女',
        '腎炎_腎徵候群及腎性病變男', '腎炎_腎徵候群及腎性病變女',
        '自殺男', '自殺女',
        '事故傷害男', '事故傷害女',
        '慢性肝病及肝硬化男', '慢性肝病及肝硬化女',
        '高血壓性疾病男', '高血壓性疾病女',
        '其他男', '其他女'
    ]

    # 刪除這些欄位
    NTP = NTP.drop(columns=columns_to_drop)

    # 只保留前四個主要死因欄位（不含總和欄位）
    cols_to_keep = NTP.columns[:6]
    NTP = NTP[NTP['年'] > 2018]
    NTP = NTP[cols_to_keep]
    
    return NTP 

def TP():
    TP = pd.read_csv('Causes_of_Death_TP.csv')
    # 提取數字 → 轉為整數 → 加 1911 → 覆蓋原欄位
    TP['統計期'] = TP['統計期'].astype(str).str.extract(r'(\d+)').astype(int) + 1911
    TP = TP[['統計期', '死因別', '死亡人數/合計[人]']]
    TP = TP[TP['統計期'] > 2018]
    # 只保留指定死因
    TP['死因別'] = TP['死因別'].astype(str).str.strip()
    TP['死因別'] = TP['死因別'].str.replace(r'\s+', '', regex=True)  # 移除所有空白字元（含全形/換行）
    
    TP = TP[TP['死因別'].isin(['所有癌症死亡原因', '氣管、支氣管和肺癌',"肝和肝內膽管癌","女性乳房癌","胃癌"])]

    TP = TP.pivot(index='統計期', columns='死因別', values='死亡人數/合計[人]').reset_index()

    # 將欄位名稱改成中文格式（可選）
    TP = TP.rename(columns={'統計期': '年'})
    
    return TP
    
def combine_TP_NTP(df_TP, df_NTP):
    # 依據 '年' 欄位合併兩個資料框
    df_merged = pd.merge(df_NTP, df_TP, how='inner', left_on='年', right_on='年')
    df = pd.DataFrame()
    df["年"] = df_merged["年"]
    df["癌症"] = df_merged["癌症"] + df_merged["所有癌症死亡原因"]
    df["心臟疾病"] = df_merged["心臟疾病"]
    df["腦血管疾病"] = df_merged["腦血管疾病"]
    df["糖尿病"] = df_merged["糖尿病"]

    return df


df_NTP = NTP()
df_TP = TP()
df = combine_TP_NTP(df_TP, df_NTP)

# 如果需要另存新檔
# df_TP.to_csv('死亡人數—主要死因_更新後.csv', index=False, encoding='utf-8-sig')

print(f"台北市：\n{df_TP}")
print(f"新北市：\n{df_NTP}")
print(f"加總：\n{df}")

df_TP.to_csv("Causes_of_Death_Data_TP.csv", index=False, encoding="utf-8-sig")
df.to_csv("Causes_of_Data_Death.csv", index=False, encoding="utf-8-sig")