-- =============================================================================
-- nrg_dw_ddl.sql
-- DDL data warehouse Nusantara Retail Group (NRG) - Tugas Kelompok 1 Data Warehouse
--
-- Isi    : star schema penjualan lintas kanal, yaitu 1 tabel fakta (fact_penjualan)
--          dan 5 dimensi (dim_tanggal, dim_produk, dim_pelanggan, dim_toko_kanal,
--          dim_kampanye), ditambah tabel pendukung map_produk dan err_kampanye.
-- Grain  : fact_penjualan = 1 baris per item transaksi
--          (S1 order_items, S2 trx_line, S3 items setelah dedup).
-- Aturan : semua nilai tanpa PPN, semua waktu dalam WIB,
--          margin kotor = penjualan bersih - HPP (S4) - fee komisi (S3, khusus marketplace).
-- Target : MySQL 8.0; sintaks yang sama juga jalan di MariaDB 10.4+ (XAMPP).
--
-- Cara menjalankan (boleh diulang kapan saja; tabel lama di-DROP lalu dibuat ulang):
--   mysql -u root -p < 02_ddl/nrg_dw_ddl.sql
-- atau dari job_00_main.kjb lewat job entry SQL dengan koneksi conn_dw.
-- Skrip hanya menghapus 8 tabel di bawah; tabel lain di nrg_dw (mis. staging) tidak disentuh.
--
-- Urutan isi:
--   0. Database nrg_dw
--   1. DROP tabel lama
--   2. Dimensi       : dim_tanggal, dim_produk (SCD2), dim_pelanggan, dim_toko_kanal, dim_kampanye
--   3. Pendukung     : map_produk, err_kampanye
--   4. Fakta         : fact_penjualan
--   5. Baris khusus  : 0 = Non-member / Tanpa kampanye, -1 = Tidak diketahui,
--                      -2 = Diskon non-kampanye
-- =============================================================================

SET NAMES utf8mb4;

-- -----------------------------------------------------------------------------
-- 0. Database target
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS nrg_dw
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE nrg_dw;

-- -----------------------------------------------------------------------------
-- 1. Hapus tabel lama agar skrip bisa dijalankan ulang.
--    Fakta dihapus lebih dulu karena memegang FK ke semua dimensi.
-- -----------------------------------------------------------------------------
SET @old_foreign_key_checks = @@FOREIGN_KEY_CHECKS;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS fact_penjualan;
DROP TABLE IF EXISTS dim_tanggal;
DROP TABLE IF EXISTS dim_produk;
DROP TABLE IF EXISTS dim_pelanggan;
DROP TABLE IF EXISTS dim_toko_kanal;
DROP TABLE IF EXISTS dim_kampanye;
DROP TABLE IF EXISTS map_produk;
DROP TABLE IF EXISTS err_kampanye;

SET FOREIGN_KEY_CHECKS = @old_foreign_key_checks;

-- -----------------------------------------------------------------------------
-- 2a. dim_tanggal: 1 baris = 1 hari, 2022-01-01 s.d. 2023-12-31 (730 baris).
--     Dibangkitkan di Pentaho (t10_dim_tanggal.ktr: Generate rows, Add sequence,
--     Calculator). Tidak ada baris khusus karena semua sumber selalu bertanggal.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_tanggal (
  tanggal_key    INT          NOT NULL COMMENT 'Kunci tanggal format YYYYMMDD, mis. 20220331',
  tanggal        DATE         NOT NULL COMMENT 'Tanggal kalender WIB',
  nama_hari      VARCHAR(10)  NOT NULL COMMENT 'Senin, Selasa, ..., Minggu',
  bulan          TINYINT      NOT NULL COMMENT 'Nomor bulan 1-12',
  nama_bulan     VARCHAR(10)  NOT NULL COMMENT 'Januari, ..., Desember',
  kuartal        TINYINT      NOT NULL COMMENT 'Kuartal 1-4',
  tahun          SMALLINT     NOT NULL COMMENT 'Tahun, mis. 2022',
  tahun_kuartal  CHAR(7)      NOT NULL COMMENT 'Label tahun-kuartal, mis. 2022-Q1',
  PRIMARY KEY (tanggal_key),
  UNIQUE KEY uq_dim_tanggal_tanggal (tanggal),
  KEY idx_dim_tanggal_tahun_kuartal (tahun, kuartal),
  CONSTRAINT ck_dim_tanggal_bulan   CHECK (bulan BETWEEN 1 AND 12),
  CONSTRAINT ck_dim_tanggal_kuartal CHECK (kuartal BETWEEN 1 AND 4)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dimensi tanggal: 1 baris per hari, 2022-01-01 s.d. 2023-12-31, dibangkitkan t10_dim_tanggal';

-- -----------------------------------------------------------------------------
-- 2b. dim_produk (SCD Type 2): 1 baris = 1 versi harga pokok produk S4.
--     Sumber: S4 produk_master (60 produk dalam 79 versi) + supplier_master;
--     katalog S1 untuk baris inferred (late arriving: SKU-NEWARR-001 di ORD-9999).
--     Diisi t12_dim_produk.ktr dengan Dimension lookup/update:
--       key = material_no, field Type 2 (Insert) = harga_pokok dan status,
--       technical key = produk_key, version = versi,
--       date range = berlaku_mulai / berlaku_sampai, stream datefield = berlaku_sejak.
--     Catatan:
--       - berlaku_sampai versi lama = berlaku_mulai versi baru, jadi lookup HPP di
--         fakta memakai berlaku_mulai <= tanggal transaksi < berlaku_sampai.
--       - Kolom selain produk_key, versi, dan is_inferred sengaja boleh NULL karena
--         Dimension lookup/update menyisipkan baris "unknown" sendiri (key 0, atau 1
--         bila memakai auto increment) yang hanya mengisi kunci dan versi.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_produk (
  produk_key      INT            NOT NULL AUTO_INCREMENT COMMENT 'Kunci surrogate, 1 per versi; -1 = Tidak diketahui',
  material_no     VARCHAR(20)    NULL COMMENT 'Kunci natural S4 (P-1001); baris inferred memakai kode SKU sumber',
  nama_produk     VARCHAR(150)   NULL COMMENT 'Nama produk S4 (katalog S1 untuk baris inferred)',
  brand           VARCHAR(60)    NULL,
  kategori        VARCHAR(60)    NULL COMMENT 'Elektronik / Furnitur / Pakaian',
  sub_kategori    VARCHAR(60)    NULL COMMENT '9 sub-kategori, mis. Smartphone, Laptop, Atasan',
  supplier_id     VARCHAR(10)    NULL COMMENT 'SUP-001 dst., hasil lookup nama pemasok ke supplier_master',
  nama_supplier   VARCHAR(100)   NULL,
  kota_supplier   VARCHAR(60)    NULL,
  status          VARCHAR(10)    NULL COMMENT 'AKTIF / NONAKTIF (Type 2)',
  harga_pokok     DECIMAL(18,2)  NULL COMMENT 'HPP per unit tanpa PPN (Type 2); NULL untuk baris inferred',
  berlaku_mulai   DATETIME       NULL COMMENT 'Awal masa berlaku versi (dari berlaku_sejak S4)',
  berlaku_sampai  DATETIME       NULL COMMENT 'Akhir masa berlaku (eksklusif); versi terakhir 2199-12-31',
  versi           INT            NOT NULL DEFAULT 1 COMMENT 'Nomor versi per material_no',
  is_inferred     CHAR(1)        NOT NULL DEFAULT 'N' COMMENT 'Y = baris inferred (produk belum ada di S4)',
  PRIMARY KEY (produk_key),
  UNIQUE KEY uq_dim_produk_material_versi (material_no, versi),
  KEY idx_dim_produk_material_berlaku (material_no, berlaku_mulai, berlaku_sampai),
  KEY idx_dim_produk_kategori (kategori, sub_kategori),
  CONSTRAINT ck_dim_produk_is_inferred CHECK (is_inferred IN ('Y', 'N'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dimensi produk SCD Type 2: 1 baris per versi harga pokok S4, ditambah baris inferred';

-- -----------------------------------------------------------------------------
-- 2c. dim_pelanggan: 1 baris = 1 orang (pelanggan web dan/atau member toko)
--     atau 1 pembeli marketplace.
--     Sumber: S1 customers + alamat is_primary, S2 member, S3 buyer.
--     Pelanggan web dan member toko dengan no_hp_normal sama digabung menjadi satu
--     pelanggan_key (200 orang: customer_id 401-600 = M-0401 s.d. M-0600), sehingga
--     pertanyaan 2 cukup menghitung baris dengan is_pelanggan_web = 'Y' dan
--     is_member_toko = 'Y'. Pembeli marketplace hanya punya buyer_hash.
--     Diisi t14_dim_pelanggan.ktr.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_pelanggan (
  pelanggan_key     INT           NOT NULL AUTO_INCREMENT COMMENT 'Kunci surrogate; 0 = Non-member, -1 = Tidak diketahui',
  no_hp_normal      VARCHAR(20)   NULL COMMENT 'HP dinormalkan ke format 08xxxxxxxxxx (S1 phone, S2 hp)',
  nama              VARCHAR(120)  NULL COMMENT 'Nama S1 diutamakan; nama member S2 bila bukan pelanggan web',
  gender            CHAR(1)       NULL COMMENT 'L / P dari S1; NULL untuk member saja dan pembeli marketplace',
  kota              VARCHAR(60)   NULL COMMENT 'Kota baku: alamat is_primary S1, kota member S2 via ref_kota, kota invoice terakhir S3',
  customer_id_web   INT           NULL COMMENT 'customer_id S1',
  member_no         VARCHAR(10)   NULL COMMENT 'member_no S2 (M-0001 dst.)',
  buyer_hash        VARCHAR(16)   NULL COMMENT 'buyer.hash S3',
  is_pelanggan_web  CHAR(1)       NOT NULL DEFAULT 'N' COMMENT 'Y = punya akun situs web (S1)',
  is_member_toko    CHAR(1)       NOT NULL DEFAULT 'N' COMMENT 'Y = pemegang kartu member toko (S2)',
  jenis_pelanggan   VARCHAR(30)   NOT NULL COMMENT 'Web / Member Toko / Web + Member / Marketplace / Non-member / Tidak diketahui',
  PRIMARY KEY (pelanggan_key),
  UNIQUE KEY uq_dim_pelanggan_no_hp_normal (no_hp_normal),
  UNIQUE KEY uq_dim_pelanggan_customer_id_web (customer_id_web),
  UNIQUE KEY uq_dim_pelanggan_member_no (member_no),
  UNIQUE KEY uq_dim_pelanggan_buyer_hash (buyer_hash),
  KEY idx_dim_pelanggan_jenis (jenis_pelanggan),
  CONSTRAINT ck_dim_pelanggan_is_web    CHECK (is_pelanggan_web IN ('Y', 'N')),
  CONSTRAINT ck_dim_pelanggan_is_member CHECK (is_member_toko IN ('Y', 'N'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dimensi pelanggan: web + member digabung lewat HP normal; pembeli marketplace terpisah';

-- -----------------------------------------------------------------------------
-- 2d. dim_toko_kanal: 1 baris = 1 toko fisik atau 1 kanal online.
--     Sumber: S2 store_master (42 toko) + 3 baris kanal online dari Data grid
--     (Situs Web, Marketplace A, Marketplace B). Diisi t13_dim_toko_kanal.ktr.
--     kanal memakai nilai yang sama dengan kolom kanal S5 agar aturan atribusi
--     kampanye bisa langsung dibandingkan.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_toko_kanal (
  toko_kanal_key  INT           NOT NULL AUTO_INCREMENT COMMENT 'Kunci surrogate; -1 = Tidak diketahui',
  kanal           VARCHAR(20)   NOT NULL COMMENT 'Toko Fisik / Situs Web / Marketplace',
  sub_kanal       VARCHAR(20)   NOT NULL COMMENT 'Toko Fisik / Situs Web / Marketplace A / Marketplace B',
  kode_toko       VARCHAR(10)   NULL COMMENT 'store_code S2 (TS01-TS42); kanal online: WEB, MPL, MPB',
  nama_toko       VARCHAR(100)  NULL COMMENT 'Nama toko S2; kanal online diisi nama kanal',
  kota            VARCHAR(60)   NULL COMMENT 'Kota baku toko; NULL untuk kanal online',
  provinsi        VARCHAR(60)   NULL COMMENT 'Provinsi toko; NULL untuk kanal online',
  format_toko     VARCHAR(20)   NULL COMMENT 'Mall / Ruko / Standalone; NULL untuk kanal online',
  PRIMARY KEY (toko_kanal_key),
  UNIQUE KEY uq_dim_toko_kanal_kode_toko (kode_toko),
  KEY idx_dim_toko_kanal_kanal (kanal, sub_kanal)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dimensi toko dan kanal: 42 toko S2 + Situs Web, Marketplace A, Marketplace B';

-- -----------------------------------------------------------------------------
-- 2e. dim_kampanye: 1 baris = 1 kampanye (kode promo + periode).
--     Sumber: S5 kampanye_marketing setelah dibersihkan (15 kampanye valid) dan
--     S1 vouchers (voucher_id_web dicocokkan lewat kode + tanggal mulai).
--     Diisi t15_dim_kampanye.ktr. Baris khusus 0, -1, -2 sudah disisipkan skrip ini
--     (bagian 5), jadi t15 cukup memuat kampanye bersih.
--     Atribusi di fakta: S1 lewat voucher_id; S2 dan S3 lewat tanggal di dalam periode
--     kampanye kanalnya (atau Semua Kanal) dengan persen sama, kanal spesifik dulu,
--     lalu tgl_mulai terbaru; diskon tanpa kampanye cocok = -2.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_kampanye (
  kampanye_key          INT           NOT NULL AUTO_INCREMENT COMMENT 'Kunci surrogate; 0 = Tanpa kampanye, -1 = Tidak diketahui, -2 = Diskon non-kampanye',
  kode_promo            VARCHAR(30)   NOT NULL COMMENT 'Kode promo bersih (trim + upper)',
  nama_kampanye         VARCHAR(100)  NOT NULL COMMENT 'Nama kampanye (trim)',
  jenis_promo           VARCHAR(30)   NULL COMMENT 'Voucher / Cashback / Bundling',
  kanal_berlaku         VARCHAR(20)   NULL COMMENT 'Semua Kanal / Toko Fisik / Situs Web / Marketplace',
  tgl_mulai             DATE          NULL COMMENT 'Tanggal mulai kampanye',
  tgl_selesai           DATE          NULL COMMENT 'Tanggal selesai kampanye',
  target_diskon_persen  DECIMAL(5,2)  NULL COMMENT 'Persen diskon kampanye (5, 10, 15, 20)',
  voucher_id_web        INT           NULL COMMENT 'voucher_id S1 dengan kode dan tanggal mulai yang sama',
  PRIMARY KEY (kampanye_key),
  UNIQUE KEY uq_dim_kampanye_kode_mulai (kode_promo, tgl_mulai),
  UNIQUE KEY uq_dim_kampanye_voucher_id_web (voucher_id_web),
  KEY idx_dim_kampanye_periode (kanal_berlaku, tgl_mulai, tgl_selesai),
  CONSTRAINT ck_dim_kampanye_periode CHECK (tgl_selesai IS NULL OR tgl_mulai IS NULL OR tgl_selesai >= tgl_mulai)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dimensi kampanye: kampanye S5 bersih + voucher S1 + baris khusus 0, -1, -2';

-- -----------------------------------------------------------------------------
-- 3a. map_produk: peta kode produk tiap sumber ke material_no S4 (t11_map_produk.ktr).
--     S1: material_no = 'P-' + angka tengah sku (SKU-1001-996 -> P-1001)
--     S2: material_no = item_code (format sudah sama)
--     S3: material_no = 'P-' + empat digit akhir seller_sku (HMATAS1001 -> P-1001)
--     SKU yang tidak punya pasangan di S4 (SKU-NEWARR-001) disimpan dengan
--     material_no NULL dan ditangani sebagai produk inferred di t20.
-- -----------------------------------------------------------------------------
CREATE TABLE map_produk (
  sumber_sistem       CHAR(2)       NOT NULL COMMENT 'S1 / S2 / S3',
  kode_produk_sumber  VARCHAR(40)   NOT NULL COMMENT 'sku S1 / item_code S2 / seller_sku S3',
  material_no         VARCHAR(20)   NULL COMMENT 'material_no S4; NULL bila produk belum ada di S4',
  nama_produk_sumber  VARCHAR(150)  NULL COMMENT 'Nama produk di sistem sumber (S1, S2) untuk audit pemetaan',
  PRIMARY KEY (sumber_sistem, kode_produk_sumber),
  KEY idx_map_produk_material_no (material_no),
  CONSTRAINT ck_map_produk_sumber CHECK (sumber_sistem IN ('S1', 'S2', 'S3'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Peta SKU S1, item_code S2, seller_sku S3 ke material_no S4';

-- -----------------------------------------------------------------------------
-- 3b. err_kampanye: baris S5 yang gagal validasi (t05_stg_s5.ktr, Data validator
--     dengan error handling ke Table output). Kolom asli disimpan sebagai teks
--     apa adanya, tidak dikonversi; target: 1 baris GAJIAN25 dengan
--     target_diskon_persen = 'sepuluh'.
-- -----------------------------------------------------------------------------
CREATE TABLE err_kampanye (
  err_id                INT            NOT NULL AUTO_INCREMENT COMMENT 'Kunci teknis',
  kode_promo            VARCHAR(100)   NULL COMMENT 'Kolom asli S5',
  nama_kampanye         VARCHAR(200)   NULL COMMENT 'Kolom asli S5',
  jenis_promo           VARCHAR(100)   NULL COMMENT 'Kolom asli S5',
  kanal                 VARCHAR(100)   NULL COMMENT 'Kolom asli S5',
  tgl_mulai             VARCHAR(30)    NULL COMMENT 'Kolom asli S5 (teks DD-MM-YYYY)',
  tgl_selesai           VARCHAR(30)    NULL COMMENT 'Kolom asli S5 (teks DD-MM-YYYY)',
  target_diskon_persen  VARCHAR(50)    NULL COMMENT 'Kolom asli S5 (teks, mis. sepuluh)',
  pic                   VARCHAR(100)   NULL COMMENT 'Kolom asli S5',
  jumlah_error          INT            NULL COMMENT 'Nr of errors fieldname pada error handling Pentaho',
  deskripsi_error       VARCHAR(1000)  NULL COMMENT 'Error descriptions fieldname, mis. target_diskon_persen bukan angka',
  kolom_error           VARCHAR(255)   NULL COMMENT 'Error fields fieldname',
  kode_error            VARCHAR(255)   NULL COMMENT 'Error codes fieldname',
  waktu_load            DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Waktu baris error dicatat',
  PRIMARY KEY (err_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Baris kampanye S5 yang gagal validasi beserta alasannya';

-- -----------------------------------------------------------------------------
-- 4. fact_penjualan: 1 baris = 1 item transaksi dari tiga kanal.
--    Dimuat t20_fact_s1 (S1 selain DIBATALKAN), t21_fact_s2 (S2 selain VOID),
--    t22_fact_s3 (S3 setelah dedup). Kunci unik (sumber_sistem, no_transaksi,
--    no_baris) mencegah baris dobel saat rerun; hapus dulu baris sumbernya
--    (DELETE ... WHERE sumber_sistem = 'S1', dst.) atau TRUNCATE di awal job.
--    Semua measure tanpa PPN dalam DECIMAL(18,2). hpp_satuan, total_hpp, dan
--    margin_kotor boleh NULL untuk produk inferred (HPP belum ada di S4).
-- -----------------------------------------------------------------------------
CREATE TABLE fact_penjualan (
  penjualan_id      BIGINT         NOT NULL AUTO_INCREMENT COMMENT 'Kunci teknis baris fakta',
  tanggal_key       INT            NOT NULL COMMENT 'FK dim_tanggal: tanggal transaksi WIB',
  produk_key        INT            NOT NULL COMMENT 'FK dim_produk: versi harga pokok yang berlaku pada tanggal transaksi',
  pelanggan_key     INT            NOT NULL COMMENT 'FK dim_pelanggan: 0 = Non-member, -1 = Tidak diketahui',
  toko_kanal_key    INT            NOT NULL COMMENT 'FK dim_toko_kanal',
  kampanye_key      INT            NOT NULL COMMENT 'FK dim_kampanye: 0 = Tanpa kampanye, -1 = Tidak diketahui, -2 = Diskon non-kampanye',
  sumber_sistem     CHAR(2)        NOT NULL COMMENT 'Degenerate: S1 Situs Web / S2 Toko Fisik / S3 Marketplace',
  no_transaksi      VARCHAR(30)    NOT NULL COMMENT 'Degenerate: order_id S1 / trx_no S2 / invoice S3',
  no_baris          SMALLINT       NOT NULL COMMENT 'Degenerate: line_no S1 / line_seq S2 / urutan item S3',
  waktu_wib         DATETIME       NULL COMMENT 'Degenerate: waktu transaksi WIB; S2 hanya tanggal (jam 00:00:00)',
  qty               DECIMAL(18,2)  NOT NULL COMMENT 'Jumlah unit terjual',
  harga_satuan      DECIMAL(18,2)  NOT NULL COMMENT 'Harga per unit tanpa PPN',
  penjualan_kotor   DECIMAL(18,2)  NOT NULL COMMENT 'qty x harga_satuan',
  diskon            DECIMAL(18,2)  NOT NULL DEFAULT 0 COMMENT 'Diskon tanpa PPN',
  penjualan_bersih  DECIMAL(18,2)  NOT NULL COMMENT 'penjualan_kotor - diskon',
  hpp_satuan        DECIMAL(18,2)  NULL COMMENT 'harga_pokok versi berlaku (S4); NULL untuk produk inferred',
  total_hpp         DECIMAL(18,2)  NULL COMMENT 'qty x hpp_satuan',
  fee_marketplace   DECIMAL(18,2)  NOT NULL DEFAULT 0 COMMENT '(commission + service) S3 dialokasikan menurut porsi qty x price; 0 untuk S1 dan S2',
  margin_kotor      DECIMAL(18,2)  NULL COMMENT 'penjualan_bersih - total_hpp - fee_marketplace; NULL bila HPP belum ada',
  qty_retur         DECIMAL(18,2)  NOT NULL DEFAULT 0 COMMENT 'Qty diretur (S1 order_returns); 0 bila tidak ada retur',
  nilai_retur       DECIMAL(18,2)  NOT NULL DEFAULT 0 COMMENT 'refund_amount / 1,11; 0 bila tidak ada retur',
  PRIMARY KEY (penjualan_id),
  UNIQUE KEY uq_fact_penjualan_sumber_trx_baris (sumber_sistem, no_transaksi, no_baris),
  KEY idx_fact_penjualan_tanggal (tanggal_key),
  KEY idx_fact_penjualan_produk (produk_key),
  KEY idx_fact_penjualan_pelanggan (pelanggan_key),
  KEY idx_fact_penjualan_toko_kanal (toko_kanal_key),
  KEY idx_fact_penjualan_kampanye (kampanye_key),
  CONSTRAINT fk_fact_penjualan_tanggal    FOREIGN KEY (tanggal_key)    REFERENCES dim_tanggal (tanggal_key),
  CONSTRAINT fk_fact_penjualan_produk     FOREIGN KEY (produk_key)     REFERENCES dim_produk (produk_key),
  CONSTRAINT fk_fact_penjualan_pelanggan  FOREIGN KEY (pelanggan_key)  REFERENCES dim_pelanggan (pelanggan_key),
  CONSTRAINT fk_fact_penjualan_toko_kanal FOREIGN KEY (toko_kanal_key) REFERENCES dim_toko_kanal (toko_kanal_key),
  CONSTRAINT fk_fact_penjualan_kampanye   FOREIGN KEY (kampanye_key)   REFERENCES dim_kampanye (kampanye_key),
  CONSTRAINT ck_fact_penjualan_sumber     CHECK (sumber_sistem IN ('S1', 'S2', 'S3'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Fakta penjualan lintas kanal: 1 baris per item transaksi, nilai tanpa PPN, waktu WIB';

-- -----------------------------------------------------------------------------
-- 5. Baris khusus (kunci 0 dan negatif) agar fakta tidak pernah memakai kunci NULL.
--    Kunci 0 hanya bisa disisipkan ke kolom AUTO_INCREMENT bila sql_mode memuat
--    NO_AUTO_VALUE_ON_ZERO; mode itu dipasang sementara lalu dikembalikan.
--    Peringatan: jangan ALTER TABLE dim_pelanggan atau dim_kampanye tanpa
--    NO_AUTO_VALUE_ON_ZERO karena MySQL bisa menomori ulang baris berkunci 0;
--    cukup jalankan ulang skrip ini.
-- -----------------------------------------------------------------------------
SET @old_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = TRIM(BOTH ',' FROM CONCAT(@@SESSION.sql_mode, ',NO_AUTO_VALUE_ON_ZERO'));

INSERT INTO dim_pelanggan
  (pelanggan_key, no_hp_normal, nama, gender, kota, customer_id_web, member_no,
   buyer_hash, is_pelanggan_web, is_member_toko, jenis_pelanggan)
VALUES
  ( 0, NULL, 'Non-member',      NULL, NULL, NULL, NULL, NULL, 'N', 'N', 'Non-member'),
  (-1, NULL, 'Tidak diketahui', NULL, NULL, NULL, NULL, NULL, 'N', 'N', 'Tidak diketahui');

INSERT INTO dim_kampanye
  (kampanye_key, kode_promo, nama_kampanye, jenis_promo, kanal_berlaku,
   tgl_mulai, tgl_selesai, target_diskon_persen, voucher_id_web)
VALUES
  ( 0, 'TANPA-KAMPANYE',  'Tanpa kampanye',      NULL, NULL, NULL, NULL, NULL, NULL),
  (-1, 'TIDAK-DIKETAHUI', 'Tidak diketahui',     NULL, NULL, NULL, NULL, NULL, NULL),
  (-2, 'NON-KAMPANYE',    'Diskon non-kampanye', NULL, NULL, NULL, NULL, NULL, NULL);

INSERT INTO dim_produk
  (produk_key, material_no, nama_produk, brand, kategori, sub_kategori, supplier_id,
   nama_supplier, kota_supplier, status, harga_pokok, berlaku_mulai, berlaku_sampai,
   versi, is_inferred)
VALUES
  (-1, NULL, 'Tidak diketahui', 'Tidak diketahui', 'Tidak diketahui', 'Tidak diketahui',
   NULL, NULL, NULL, NULL, NULL, '1900-01-01 00:00:00', '2199-12-31 23:59:59', 1, 'N');

INSERT INTO dim_toko_kanal
  (toko_kanal_key, kanal, sub_kanal, kode_toko, nama_toko, kota, provinsi, format_toko)
VALUES
  (-1, 'Tidak diketahui', 'Tidak diketahui', NULL, 'Tidak diketahui', NULL, NULL, NULL);

SET SESSION sql_mode = @old_sql_mode;

-- -----------------------------------------------------------------------------
-- Cek cepat setelah skrip dijalankan:
--   SELECT 'dim_pelanggan' AS tabel, pelanggan_key AS kunci, nama AS keterangan FROM dim_pelanggan
--   UNION ALL SELECT 'dim_kampanye', kampanye_key, nama_kampanye FROM dim_kampanye
--   UNION ALL SELECT 'dim_produk', produk_key, nama_produk FROM dim_produk
--   UNION ALL SELECT 'dim_toko_kanal', toko_kanal_key, nama_toko FROM dim_toko_kanal;
--   -- hasil: 7 baris khusus (0 dan -1 pelanggan; 0, -1, -2 kampanye; -1 produk; -1 toko)
-- =============================================================================
