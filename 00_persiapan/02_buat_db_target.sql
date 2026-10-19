-- Membuat database target data warehouse dan staging (utf8mb4).
-- Aman dijalankan ulang: tidak menghapus tabel atau data yang sudah ada.
--   mysql -u root -h 127.0.0.1 -P 4306 < 00_persiapan/02_buat_db_target.sql

CREATE DATABASE IF NOT EXISTS nrg_stg CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS nrg_dw  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Bila database sudah ada dengan charset lain (default server bisa latin1), samakan default-nya.
ALTER DATABASE nrg_stg CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE nrg_dw  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

SELECT schema_name AS db, default_character_set_name AS charset, default_collation_name AS collation
FROM information_schema.schemata
WHERE schema_name IN ('nrg_ecom', 'nrg_stg', 'nrg_dw')
ORDER BY schema_name;
