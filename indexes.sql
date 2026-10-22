-- OPTIMISED: composite indexes matching the app's query patterns
USE appdb;
CREATE INDEX idx_orders_customer_created ON orders (customer_id, created_at);
CREATE INDEX idx_products_category_price ON products (category, price);
-- Verify with: EXPLAIN SELECT ... ; look for type=ref/range instead of ALL
