CREATE TABLE medical_devices_stats (
  col TEXT,
  col_1 TEXT,
  電腦斷層掃描儀_Computerized_Tomography_Scanner_(CT) INT,
  磁振造影機__Magnetic_Resonance_Imaging__(MRI) INT,
  高能遠距放射_治療設備__High-energy_Teletherapy__Machine INT,
  近接式放射_治療設備_Radiation_Brachytherapy_Machine INT,
  單光子斷層掃描儀_Single-Photon_Emission_Computed_Tomography_Scanner_(SPECT) INT,
  正子斷層掃描儀__Positron_Emission__Tomography_Scanner_(PET) INT,
  高壓氧設備_Hyperbaric_Oxygen_Therapy_Device_(HBOT) INT,
  磁珠標記自動細胞分選儀_Clini-MACS INT,
  重粒子治療設備_Heavy_Charged_Particle_Therapy_Device INT,
  單機型質子機_Stand-alone_Proton_Therapy_System INT,
  多治療室質子機_Proton_Therapy_System_for_Multi-Treatment_Room INT,
  手術台_Operating__Table INT,
  產台__Obstetric__Delivery__Bed INT,
  牙醫_治療台_Dental__Unit INT,
  門診_診療室_Outpatient_Consultation_Room INT
);
INSERT INTO medical_devices_stats VALUES ('總       計', 'Total', 474, 295, 186, 39, 155, 64, 133, 1, 1, 1, 2, 2328, 351, 2859, 10211);
INSERT INTO medical_devices_stats VALUES ('新 北 市', 'New Taipei City', 44, 28, 22, 5, 20, 6, 10, 0, 0, 0, 0, 235, 32, 271, 985);
INSERT INTO medical_devices_stats VALUES ('臺 北 市', 'Taipei City', 75, 65, 40, 9, 40, 15, 20, 0, 1, 1, 0, 403, 45, 744, 2052);
