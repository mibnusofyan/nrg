-- Cek isi nrg_ecom setelah memuat S1. Semua baris harus berstatus OK.
--   mysql -u root -h 127.0.0.1 -P 4306 nrg_ecom < 00_persiapan/03_cek_s1.sql

SELECT cek, jumlah, harapan, IF(jumlah = harapan, 'OK', 'CEK') AS status FROM (
    SELECT 'categories'                          AS cek, (SELECT COUNT(*) FROM categories)           AS jumlah, 12    AS harapan
    UNION ALL SELECT 'customers',                    (SELECT COUNT(*) FROM customers),                    600
    UNION ALL SELECT 'customer_addresses',           (SELECT COUNT(*) FROM customer_addresses),           744
    UNION ALL SELECT 'products',                     (SELECT COUNT(*) FROM products),                     61
    UNION ALL SELECT 'vouchers',                     (SELECT COUNT(*) FROM vouchers),                     16
    UNION ALL SELECT 'orders',                       (SELECT COUNT(*) FROM orders),                       3001
    UNION ALL SELECT 'order_items',                  (SELECT COUNT(*) FROM order_items),                  4540
    UNION ALL SELECT 'order_status_history',         (SELECT COUNT(*) FROM order_status_history),         14298
    UNION ALL SELECT 'payments',                     (SELECT COUNT(*) FROM payments),                     2806
    UNION ALL SELECT 'shipments',                    (SELECT COUNT(*) FROM shipments),                    2806
    UNION ALL SELECT 'order_returns',                (SELECT COUNT(*) FROM order_returns),                106
    -- Nilai kolom terakhir (rusak bila CRLF tidak ditangani)
    UNION ALL SELECT 'products aktif',               (SELECT COUNT(*) FROM products WHERE is_active = 1), 61
    UNION ALL SELECT 'alamat primer',                (SELECT COUNT(*) FROM customer_addresses WHERE is_primary = 1), 600
    UNION ALL SELECT 'delivered_at kosong (NULL)',   (SELECT COUNT(*) FROM shipments WHERE delivered_at IS NULL), 420
    UNION ALL SELECT 'order tanpa alamat kirim',     (SELECT COUNT(*) FROM orders WHERE shipping_address_id IS NULL), 1
    UNION ALL SELECT 'payments SUCCESS',             (SELECT COUNT(*) FROM payments WHERE status = 'SUCCESS'), 2806
    UNION ALL SELECT 'teks berisi karakter CR',      (SELECT COUNT(*) FROM categories WHERE category_name LIKE CONCAT('%', CHAR(13), '%'))
                                                   + (SELECT COUNT(*) FROM order_returns WHERE status LIKE CONCAT('%', CHAR(13), '%')), 0
    -- Nilai yang mudah rusak bila dimuat lewat pandas (load_all.py)
    UNION ALL SELECT 'HP diawali +62',               (SELECT COUNT(*) FROM customers WHERE phone LIKE '+62%'), 600
    UNION ALL SELECT 'kode pos diawali 0',           (SELECT COUNT(*) FROM customer_addresses WHERE postal_code LIKE '0%'), 87
    -- Fakta penting untuk ETL
    UNION ALL SELECT 'order bervoucher',             (SELECT COUNT(*) FROM orders WHERE voucher_id IS NOT NULL), 1071
    UNION ALL SELECT 'order DIBATALKAN',             (SELECT COUNT(*) FROM orders WHERE status = 'DIBATALKAN'), 194
    UNION ALL SELECT 'item ORD-9999 (SKU-NEWARR-001)', (SELECT COUNT(*) FROM order_items WHERE order_id = 'ORD-9999' AND sku = 'SKU-NEWARR-001'), 1
) t;
