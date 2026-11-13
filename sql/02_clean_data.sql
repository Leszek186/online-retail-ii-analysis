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
