/*
============================================================
Common Pattern: Pagination and Filtering
============================================================
Description: Demonstrates safe filtering, pagination, and ordering.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

DECLARE @PageNumber INT = 1;      -- 1-based
DECLARE @PageSize INT = 25;       -- Rows per page
DECLARE @SortColumn SYSNAME = 'OrderDate';
DECLARE @SortDirection NVARCHAR(4) = 'DESC'; -- ASC/DESC
DECLARE @CustomerID INT = NULL;   -- Optional filter
DECLARE @StartDate DATE = NULL;
DECLARE @EndDate DATE = NULL;

-- Basic validation
IF @PageNumber < 1 SET @PageNumber = 1;
IF @PageSize NOT BETWEEN 1 AND 500 SET @PageSize = 25;

-- Whitelist sort column to avoid SQL injection
IF @SortColumn NOT IN ('OrderDate','TotalAmount','OrderID') SET @SortColumn = 'OrderDate';
IF @SortDirection NOT IN ('ASC','DESC') SET @SortDirection = 'DESC';

DECLARE @SQL NVARCHAR(MAX) = N'
SELECT 
    o.OrderID,
    o.OrderDate,
    o.CustomerID,
    o.TotalAmount,
    ROW_NUMBER() OVER (ORDER BY ' + QUOTENAME(@SortColumn) + ' ' + @SortDirection + ') AS RowNum
FROM dbo.Orders o
WHERE 1=1' +
    CASE WHEN @CustomerID IS NOT NULL THEN ' AND o.CustomerID = @CustomerID' ELSE '' END +
    CASE WHEN @StartDate IS NOT NULL THEN ' AND o.OrderDate >= @StartDate' ELSE '' END +
    CASE WHEN @EndDate IS NOT NULL THEN ' AND o.OrderDate <= @EndDate' ELSE '' END +
'\n';

SET @SQL += N'SELECT * FROM (
' + @SQL + N'
) AS Ordered
WHERE RowNum BETWEEN ((' + CAST(@PageNumber AS NVARCHAR(10)) + ' - 1) * ' + CAST(@PageSize AS NVARCHAR(10)) + ' + 1)
    AND (' + CAST(@PageNumber AS NVARCHAR(10)) + ' * ' + CAST(@PageSize AS NVARCHAR(10)) + ')
ORDER BY RowNum;';

EXEC sp_executesql @SQL,
    N'@CustomerID INT, @StartDate DATE, @EndDate DATE',
    @CustomerID=@CustomerID,
    @StartDate=@StartDate,
    @EndDate=@EndDate;