USE OnlineRetail;
GO

-- 3a. Overlap between sheets
-- Row counts and date ranges per sheet (expected: 525461 and 541910 rows)
SELECT sheet,
       COUNT(*)          AS n_rows,
       MIN(invoice_date) AS first_date,
       MAX(invoice_date) AS last_date
FROM dbo.stg_transactions
GROUP BY sheet;

-- Rows in the overlapping period (expected: 22523 in both sheets)
SELECT COUNT(*) AS n_rows
FROM dbo.stg_transactions
WHERE sheet = 1 AND invoice_date >= '2010-12-01';

SELECT COUNT(*) AS n_rows
FROM dbo.stg_transactions
WHERE sheet = 2 AND invoice_date < '2010-12-10';

-- Are the overlapping rows identical? EXCEPT in both directions (expected: 0 rows each)
SELECT invoice, stock_code, description, quantity, invoice_date, unit_price, customer_id, country
FROM dbo.stg_transactions
WHERE sheet = 1 AND invoice_date >= '2010-12-01'
EXCEPT
SELECT invoice, stock_code, description, quantity, invoice_date, unit_price, customer_id, country
FROM dbo.stg_transactions
WHERE sheet = 2 AND invoice_date < '2010-12-10';

SELECT invoice, stock_code, description, quantity, invoice_date, unit_price, customer_id, country
FROM dbo.stg_transactions
WHERE sheet = 2 AND invoice_date < '2010-12-10'
EXCEPT
SELECT invoice, stock_code, description, quantity, invoice_date, unit_price, customer_id, country
FROM dbo.stg_transactions
WHERE sheet = 1 AND invoice_date >= '2010-12-01';


-- 3b. Remove the overlap (keep sheet 1, drop sheet 2 rows before 2010-12-10)
-- Raw table stays untouched; result goes to a new table (expected: 1044848 rows)
SELECT invoice, stock_code, description, quantity,
       invoice_date, unit_price, customer_id, country
INTO dbo.tx_no_overlap
FROM dbo.stg_transactions
WHERE NOT ( sheet = 2 AND invoice_date < '2010-12-10' );

-- Count exact duplicates (expected: 11812)
WITH numbered AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY invoice, stock_code, description, quantity,
                            invoice_date, unit_price, customer_id, country
               ORDER BY (SELECT NULL)
           ) AS rn
    FROM dbo.tx_no_overlap
)
SELECT COUNT(*) AS n_duplicates
FROM numbered
WHERE rn > 1;

-- Keep one copy of each duplicated row (expected: 1033036 rows)
WITH numbered AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY invoice, stock_code, description, quantity,
                            invoice_date, unit_price, customer_id, country
               ORDER BY (SELECT NULL)
           ) AS rn
    FROM dbo.tx_no_overlap
)
SELECT invoice, stock_code, description, quantity,
       invoice_date, unit_price, customer_id, country
INTO dbo.tx_dedup
FROM numbered
WHERE rn = 1;


-- 3c. Split cancellations (invoice starts with 'C') from sales
-- Count cancellations (expected: 19104)
SELECT COUNT(*) AS n_cancellations
FROM dbo.tx_dedup
WHERE invoice LIKE 'C%';

-- Sales: invoices that do not start with 'C' (expected: 1013932 rows)
SELECT invoice, stock_code, description, quantity,
       invoice_date, unit_price, customer_id, country
INTO dbo.tx_sales
FROM dbo.tx_dedup
WHERE invoice NOT LIKE 'C%';

-- Cancellations: invoices that start with 'C' (expected: 19104 rows)
SELECT invoice, stock_code, description, quantity,
       invoice_date, unit_price, customer_id, country
INTO dbo.tx_cancel
FROM dbo.tx_dedup
WHERE invoice LIKE 'C%';


-- 3d. Keep only products
-- A product stock code is 5 digits plus an optional 1-2 letters, e.g. 85123A.
-- Everything else is postage, fees, vouchers, manual or test entries.
-- Count non-product rows in sales (expected: 4790) and in cancellations (expected: 1190)
SELECT COUNT(*) AS n_non_product
FROM dbo.tx_sales
WHERE NOT ( stock_code LIKE '[0-9][0-9][0-9][0-9][0-9]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z][A-Za-z]' );

-- What are these codes? (POST, DOT, M, C2, ADJUST, BANK CHARGES, gift vouchers, ...)
SELECT stock_code, COUNT(*) AS n
FROM dbo.tx_sales
WHERE NOT ( stock_code LIKE '[0-9][0-9][0-9][0-9][0-9]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z][A-Za-z]' )
GROUP BY stock_code
ORDER BY n DESC;

-- Remove them (expected: 4790 rows from sales, 1190 from cancellations)
DELETE FROM dbo.tx_sales
WHERE NOT ( stock_code LIKE '[0-9][0-9][0-9][0-9][0-9]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z][A-Za-z]' );

DELETE FROM dbo.tx_cancel
WHERE NOT ( stock_code LIKE '[0-9][0-9][0-9][0-9][0-9]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z]'
         OR stock_code LIKE '[0-9][0-9][0-9][0-9][0-9][A-Za-z][A-Za-z]' );

-- Check (expected: tx_sales 1009142, tx_cancel 17914)
SELECT 'tx_sales' AS tabela, COUNT(*) AS n_rows FROM dbo.tx_sales
UNION ALL
SELECT 'tx_cancel', COUNT(*) FROM dbo.tx_cancel;



-- 3e. Remove zero/negative quantities and zero prices from sales
-- Free items, write-offs and stock adjustments are not real sales.
-- Count rows to remove (expected: 5928)
SELECT COUNT(*) AS n_to_remove
FROM dbo.tx_sales
WHERE quantity <= 0 OR unit_price <= 0;

DELETE
FROM dbo.tx_sales
WHERE quantity <= 0 OR unit_price <= 0;

-- Cancellations must have negative quantity and positive price (expected: 0 bad rows)
SELECT COUNT(*) AS n_bad
FROM dbo.tx_cancel
WHERE quantity >= 0 OR unit_price <= 0;

-- Final check (expected: tx_sales 1003214, tx_cancel 17914)
SELECT 'tx_sales' AS tabela, COUNT(*) AS n_rows FROM dbo.tx_sales
UNION ALL
SELECT 'tx_cancel', COUNT(*) FROM dbo.tx_cancel;


-- 3f. Views for the analysis layer
-- revenue = quantity * unit_price (negative for cancellations)
GO

CREATE VIEW dbo.v_sales AS
SELECT invoice, stock_code, description, quantity, unit_price,
       quantity * unit_price AS revenue,
       invoice_date, customer_id, country
FROM dbo.tx_sales;
GO

CREATE VIEW dbo.v_returns AS
SELECT invoice, stock_code, description, quantity, unit_price,
       quantity * unit_price AS revenue,
       invoice_date, customer_id, country
FROM dbo.tx_cancel;
GO

-- Check (expected: v_sales 1003214 rows / 19642692.15, v_returns 17914 rows / -716425.97)
SELECT 'v_sales' AS view_name, COUNT(*) AS n_rows, SUM(revenue) AS total_revenue FROM dbo.v_sales
UNION ALL
SELECT 'v_returns', COUNT(*), SUM(revenue) FROM dbo.v_returns;
