import pandas as pd
import re

df = pd.read_csv('respiratory_care_taipei.csv', index_col=False, encoding='utf-8-sig')


df = df.drop_duplicates()

if '地址' in df.columns:
    df['地址'] = df['地址'].astype(str).str.replace(r"(號).*", r"\1", regex=True)

df = df.dropna(how='all')

def clean_text(text):
    if isinstance(text, str):
        text = re.sub(r'[\s\n\r\t,]', '', text)
        text = text.strip()
    return text

df = df.applymap(clean_text)

df = df.loc[:, ~df.columns.str.contains('^Unnamed')]

df.to_csv('respiratory_care_taipei_cleaned.csv', index=False, encoding='utf-8-sig')
print("清理完成！檔案儲存為 'respiratory_care_taipei_cleaned.csv'")
