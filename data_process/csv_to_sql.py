import csv

# 你要處理的 CSV 路徑
csv_file_path = 'The location of a hospital/The location of a hospital.csv'

# 輸出 SQL 的文字檔（可選）
output_file_path = 'The location of a hospital.sql'

rows = []

with open(csv_file_path, newline='', encoding='utf-8') as csvfile:
    reader = csv.reader(csvfile)
    header = next(reader)  # 跳過標題列

    for row in reader:
        # 把每個值加上單引號（如果是數字會保留原樣）
        processed = []
        for item in row:
            try:
                # 嘗試轉成數字（保留 int/float 形式）
                processed.append(str(float(item)) if '.' in item else str(int(item)))
            except ValueError:
                # 字串加單引號，並 escape 單引號，同時將雙引號轉成單引號
                safe = item.replace("'", "''").replace('"', "'")
                processed.append(f"'{safe}'")
        
        row_sql = f"({', '.join(processed)})"
        rows.append(row_sql)

# 合併為一整段 SQL VALUES
sql_values = ",\n".join(rows)

# 顯示在螢幕上
print(sql_values)

# 可選：寫入檔案
with open(output_file_path, 'w', encoding='utf-8') as f:
    f.write(sql_values)

print(f"\n✅ SQL VALUES written to {output_file_path}")
