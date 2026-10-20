-- =============================================================================
-- nrg_stg_ddl.sql
-- Tabel staging (nrg_stg) untuk pipeline ETL NRG. Diisi t01-t05, dibaca t10-t22.
-- Aman dijalankan ulang: tabel staging di-DROP lalu dibuat ulang.
-- =============================================================================
SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS nrg_stg CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE nrg_stg;

DROP TABLE IF EXISTS stg_s1_item, stg_s1_pelanggan, stg_s1_produk, stg_s1_voucher,
  stg_s2_trx, stg_s2_store, stg_s2_member, stg_s2_produk,
  stg_s3_item, stg_s4_produk, stg_s5_kampanye;

-- S1: satu baris per order item + kolom header order + retur yang DISETUJUI (t01)
CREATE TABLE stg_s1_item (
  order_item_id  INT            NOT NULL,
  order_id       VARCHAR(20)    NOT NULL,
  line_no        SMALLINT       NOT NULL,
  customer_id    INT            NULL,
  order_ts       DATETIME       NULL,
  status         VARCHAR(20)    NULL,
  voucher_id     INT            NULL,
  sku            VARCHAR(40)    NOT NULL,
  qty            INT            NOT NULL,
  unit_price     DECIMAL(15,2)  NOT NULL,
  disc_amount    DECIMAL(15,2)  NOT NULL DEFAULT 0,
  qty_retur      INT            NOT NULL DEFAULT 0,
  refund_amount  DECIMAL(15,2)  NOT NULL DEFAULT 0,
  PRIMARY KEY (order_item_id),
  UNIQUE KEY uq_stg_s1_item (order_id, line_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S1: pelanggan + kota alamat is_primary + HP dinormalkan (t01)
CREATE TABLE stg_s1_pelanggan (
  customer_id   INT           NOT NULL,
  full_name     VARCHAR(120)  NULL,
  phone         VARCHAR(20)   NULL,
  no_hp_normal  VARCHAR(20)   NULL,
  gender        CHAR(1)       NULL,
  kota          VARCHAR(60)   NULL,
  PRIMARY KEY (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S1: katalog produk ECOM + kategori induk (t01)
CREATE TABLE stg_s1_produk (
  sku           VARCHAR(40)   NOT NULL,
  product_name  VARCHAR(150)  NULL,
  brand         VARCHAR(60)   NULL,
  kategori      VARCHAR(60)   NULL,
  sub_kategori  VARCHAR(60)   NULL,
  PRIMARY KEY (sku)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S1: voucher (t01)
CREATE TABLE stg_s1_voucher (
  voucher_id      INT            NOT NULL,
  promo_code      VARCHAR(30)    NULL,
  discount_type   VARCHAR(10)    NULL,
  discount_value  DECIMAL(10,2)  NULL,
  min_purchase    DECIMAL(15,2)  NULL,
  quota           INT            NULL,
  valid_from      DATE           NULL,
  valid_to        DATE           NULL,
  PRIMARY KEY (voucher_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S2: satu baris per trx_line + kolom header, termasuk VOID (dibuang di t21) (t02)
CREATE TABLE stg_s2_trx (
  trx_no           VARCHAR(30)    NOT NULL,
  line_seq         SMALLINT       NOT NULL,
  store_code       VARCHAR(10)    NULL,
  cashier_id       VARCHAR(10)    NULL,
  member_no        VARCHAR(10)    NULL,
  trx_date         DATE           NULL,
  payment_type     VARCHAR(10)    NULL,
  status           VARCHAR(10)    NULL,
  item_code        VARCHAR(20)    NULL,
  qty              INT            NULL,
  unit_price_excl  DECIMAL(15,2)  NULL,
  disc_pct         DECIMAL(5,2)   NULL,
  PRIMARY KEY (trx_no, line_seq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S2: master toko + kota baku (t02)
CREATE TABLE stg_s2_store (
  store_id     INT           NULL,
  store_code   VARCHAR(10)   NOT NULL,
  store_name   VARCHAR(100)  NULL,
  kota         VARCHAR(60)   NULL,
  provinsi     VARCHAR(60)   NULL,
  format_toko  VARCHAR(20)   NULL,
  opened_at    DATE          NULL,
  PRIMARY KEY (store_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S2: member + HP dinormalkan + kota baku (t02)
CREATE TABLE stg_s2_member (
  member_no     VARCHAR(10)   NOT NULL,
  member_name   VARCHAR(120)  NULL,
  hp            VARCHAR(20)   NULL,
  no_hp_normal  VARCHAR(20)   NULL,
  kota_asli     VARCHAR(60)   NULL,
  kota          VARCHAR(60)   NULL,
  join_date     DATE          NULL,
  PRIMARY KEY (member_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S2: master produk lokal toko (t02)
CREATE TABLE stg_s2_produk (
  item_code            VARCHAR(20)    NOT NULL,
  barcode              VARCHAR(20)    NULL,
  product_name         VARCHAR(150)   NULL,
  category_local       VARCHAR(60)    NULL,
  unit_price_excl_ppn  DECIMAL(15,2)  NULL,
  PRIMARY KEY (item_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S3: item marketplace setelah JSON diratakan dan duplikat API dibuang (t03)
CREATE TABLE stg_s3_item (
  invoice       VARCHAR(30)    NOT NULL,
  item_no       SMALLINT       NOT NULL,
  channel       VARCHAR(20)    NULL,
  paid_at_utc   DATETIME       NULL,
  waktu_wib     DATETIME       NULL,
  buyer_hash    VARCHAR(16)    NULL,
  buyer_city    VARCHAR(60)    NULL,
  seller_sku    VARCHAR(20)    NOT NULL,
  qty           INT            NULL,
  price         DECIMAL(15,2)  NULL,
  voucher       DECIMAL(15,2)  NULL,
  commission    DECIMAL(15,2)  NULL,
  service       DECIMAL(15,2)  NULL,
  diambil_pada  DATETIME       NULL,
  PRIMARY KEY (invoice, item_no),
  UNIQUE KEY uq_stg_s3_item (invoice, seller_sku)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S4: master produk ERP (semua versi harga pokok) + data pemasok (t04)
CREATE TABLE stg_s4_produk (
  material_no    VARCHAR(20)    NOT NULL,
  nama_produk    VARCHAR(150)   NULL,
  brand          VARCHAR(60)    NULL,
  kategori       VARCHAR(60)    NULL,
  sub_kategori   VARCHAR(60)    NULL,
  harga_pokok    DECIMAL(18,2)  NULL,
  supplier       VARCHAR(100)   NULL,
  supplier_id    VARCHAR(10)    NULL,
  kota_supplier  VARCHAR(60)    NULL,
  status         VARCHAR(10)    NULL,
  berlaku_sejak  DATE           NOT NULL,
  PRIMARY KEY (material_no, berlaku_sejak)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S5: kampanye yang lolos pembersihan dan validasi (t05)
CREATE TABLE stg_s5_kampanye (
  kode_promo            VARCHAR(30)    NOT NULL,
  nama_kampanye         VARCHAR(100)   NULL,
  jenis_promo           VARCHAR(30)    NULL,
  kanal                 VARCHAR(20)    NULL,
  tgl_mulai             DATE           NOT NULL,
  tgl_selesai           DATE           NULL,
  target_diskon_persen  DECIMAL(5,2)   NULL,
  pic                   VARCHAR(60)    NULL,
  PRIMARY KEY (kode_promo, tgl_mulai)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;