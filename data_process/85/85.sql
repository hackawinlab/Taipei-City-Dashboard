CREATE TABLE hospital_service_volume (
  縣市別 County/City TEXT,
  col_1 TEXT,
  出院人次 Discharges INT,
  住院健檢人次 Inpatient Physicals INT,
  手術人次Operations INT,
  col_5 INT,
  col_6 INT,
  門診人次 Outpatient Visits INT,
  急診人次 Emergency Department Visits INT,
  門診體檢人次 Outpatient Physicals INT,
  接生人次        (含剖腹產人次) Deliveries (Including Caesarean Sections) INT,
  剖腹產人次 Caesarean Sections INT,
  洗腎人次 Hemodialysis INT
);
INSERT INTO hospital_service_volume VALUES ('新 北 市', 'New Taipei City', 319974, 7, 244491, 116404, 128087, 12656925, 883344, 421709, 7247, 2118, 684880);
INSERT INTO hospital_service_volume VALUES ('臺 北 市', 'Taipei City', 590892, 18885, 453956, 211687, 242269, 22898069, 973054, 769835, 12591, 4553, 726915);