# 00_persiapan — Tahap 1

Urutan menyiapkan laptop setiap anggota. Ganti `4306` dengan port MySQL/MariaDB masing-masing (XAMPP biasanya `3306`).

1. Dari folder `Data`, buat skema S1 lalu muat CSV-nya:

   ```bash
   mysql -u root -p -h 127.0.0.1 -P 4306 --local-infile=1 < S1_ecom_db_schema_mysql.sql
   mysql -u root -p -h 127.0.0.1 -P 4306 --local-infile=1 nrg_ecom < ../00_persiapan/01_muat_s1.sql
   ```

   Jangan pakai `Data/S1_ecom_db_load_mysql.sql` bawaan. CSV S1 berakhiran CRLF, sedangkan skrip itu memakai `'\n'`, sehingga `is_active`, `is_primary`, `delivered_at`, dan `payments.status` rusak.

2. Dari folder proyek, buat database target dan cek isi S1 (semua baris harus `OK`):

   ```bash
   mysql -u root -p -h 127.0.0.1 -P 4306 < 00_persiapan/02_buat_db_target.sql
   mysql -u root -p -h 127.0.0.1 -P 4306 nrg_ecom < 00_persiapan/03_cek_s1.sql
   ```

3. Tutup Spoon. Salin isi `kettle.properties.contoh` ke `%USERPROFILE%\.kettle\kettle.properties` dan sesuaikan nilainya. Salin `shared.xml.contoh` menjadi `%USERPROFILE%\.kettle\shared.xml` (gabungkan manual bila sudah punya koneksi bersama lain).

4. Jalankan `03_etl/t00_cek_koneksi.ktr` di Spoon. Hasil yang benar: `conn_ecom` = 3001 order, `conn_stg` = nrg_stg, `conn_dw` = nrg_dw, dan 42 berkas trx_header.

Koneksi `conn_ecom`, `conn_stg`, dan `conn_dw` mengambil host, port, user, dan password dari variabel `NRG_DB_*`, jadi berkas `.ktr` yang sama bisa dijalankan di laptop siapa pun.
