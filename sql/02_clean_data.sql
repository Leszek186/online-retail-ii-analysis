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
