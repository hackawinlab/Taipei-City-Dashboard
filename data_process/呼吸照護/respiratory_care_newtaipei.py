import pandas as pd
import re

df = pd.read_csv('respiratory_care_newtaipei.csv')

# 1️清空tel (電話)

if 'twd97y' in df.columns:
    df['twd97y'] = ''
if 'twd97x' in df.columns:
    df['twd97x'] = ''
df = df.drop_duplicates()

df["hosp_addr"] = df["hosp_addr"].str.replace(r"(號).*", r"\1", regex=True)

df = df.dropna()

def clean_text(text):
    if isinstance(text, str):
        # 移除換行符號、逗號、空白
        text = re.sub(r'[\n\r\t,]', '', text)
        text = text.strip()
    return text

df = df.applymap(clean_text)

df.to_csv('respiratory_care_newtaipei_cleaned.csv', index=False, encoding='utf-8-sig')

print("清理完成！檔案儲存為 'respiratory_care_newtaipei_cleaned.csv'")
