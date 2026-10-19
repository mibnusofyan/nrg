-- Jalankan setelah S1_ecom_db_schema_mysql.sql, dari folder yang berisi
-- output/S1_ECOM_DB/*.csv. LOAD DATA LOCAL INFILE butuh flag khusus:
--
--   mysql --local-infile=1 -u root -p nrg_ecom < sql/S1_ecom_db_schema_mysql.sql
--   mysql --local-infile=1 -u root -p nrg_ecom < sql/S1_ecom_db_load_mysql.sql
--
-- Jika muncul error "Loading local data is disabled", jalankan dulu di
-- server: SET GLOBAL local_infile = 1;  (butuh hak akses admin, sekali saja)
--
-- Semua path di bawah relatif terhadap direktori tempat Anda menjalankan
-- perintah mysql (root folder paket data).

SET FOREIGN_KEY_CHECKS = 0;   -- supaya urutan load antar tabel lebih fleksibel

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/categories.csv'
INTO TABLE categories
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(category_id, @parent, category_name)
SET parent_category_id = NULLIF(@parent, '');

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/products.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, sku, category_id, product_name, brand, base_price, @active)
SET is_active = IF(@active = 'True', 1, 0);

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, full_name, email, phone, gender, birth_date, registered_at);

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/customer_addresses.csv'
INTO TABLE customer_addresses
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(address_id, customer_id, label, address_line, city, province, postal_code, @primary)
SET is_primary = IF(@primary = 'True', 1, 0);

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/vouchers.csv'
INTO TABLE vouchers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(voucher_id, promo_code, discount_type, discount_value, min_purchase, quota, valid_from, valid_to);

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_ts, status, @voucher, payment_method, shipping_fee, @addr)
SET voucher_id = NULLIF(@voucher, ''),
    shipping_address_id = NULLIF(@addr, '');

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_item_id, order_id, line_no, @prod, sku, qty, unit_price, disc_amount)
SET product_id = NULLIF(@prod, '');

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/order_status_history.csv'
INTO TABLE order_status_history
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(history_id, order_id, status, changed_at);

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/payments.csv'
INTO TABLE payments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(payment_id, order_id, provider, amount, paid_at, status);

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/shipments.csv'
INTO TABLE shipments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(shipment_id, order_id, courier, tracking_no, shipped_at, @delivered)
SET delivered_at = NULLIF(@delivered, '');

LOAD DATA LOCAL INFILE 'S1_ECOM_DB/order_returns.csv'
INTO TABLE order_returns
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 LINES
(return_id, order_item_id, qty, reason, refund_amount, status, requested_at);

SET FOREIGN_KEY_CHECKS = 1;
