-- 01_load_data.sql
-- Creates the database and a staging table, loads the raw Online Retail II data
-- (two Excel sheets exported to one CSV, with an extra "sheet" column) and checks it.
-- Raw data is NOT stored in this repository, see data/README.md.

CREATE DATABASE OnlineRetail;
GO
USE OnlineRetail;
GO

CREATE TABLE dbo.stg_transactions (
    sheet        TINYINT,
    invoice      NVARCHAR(10),
    stock_code   NVARCHAR(20),
    description  NVARCHAR(100),
    quantity     INT,
    invoice_date DATETIME2(0),
    unit_price   DECIMAL(12,4),
    customer_id  INT NULL,
    country      NVARCHAR(50)
);
GO

BULK INSERT dbo.stg_transactions
FROM 'C:\data\online_retail_II.csv'          -- adjust to the location of your file
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, TABLOCK);
GO

-- Check: expected 1067371 | 525461 | 541910 | 243007 | 4382 | 53628 | 43
SELECT COUNT(*) AS rows_total,
       SUM(CASE WHEN sheet = 1 THEN 1 ELSE 0 END) AS sheet1,
       SUM(CASE WHEN sheet = 2 THEN 1 ELSE 0 END) AS sheet2,
       SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS no_customer,
       SUM(CASE WHEN description IS NULL THEN 1 ELSE 0 END) AS no_description,
       COUNT(DISTINCT invoice) AS invoices,
       COUNT(DISTINCT country) AS countries
FROM dbo.stg_transactions;
