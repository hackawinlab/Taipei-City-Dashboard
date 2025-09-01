import csv

# 讀檔案路徑（自己改）
input_file = "converted.csv"
output_file = "output_with_city.csv"

# 開始處理
with open(input_file, "r", encoding="utf-8") as f_in, open(output_file, "w", encoding="utf-8-sig", newline="") as f_out:
    reader = csv.DictReader(f_in)
    fieldnames = reader.fieldnames + ["city"]
    writer = csv.DictWriter(f_out, fieldnames=fieldnames)

    writer.writeheader()

    for row in reader:
        address = row["地址"].strip()
        if address.startswith("臺北市"):
            row["city"] = "臺北市"
        elif address.startswith("新北市"):
            row["city"] = "新北市"
        else:
            row["city"] = "未知"  # Hello？你地址是不是壞掉了啦🐤

        writer.writerow(row)

print("處理好了！你的檔案在：output_with_city.csv 😤")
