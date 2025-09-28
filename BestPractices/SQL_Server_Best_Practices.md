# SQL Server Best Practices Guide

This comprehensive guide covers essential best practices for SQL Server administration, development, and maintenance.

## Table of Contents
1. [Database Design](#database-design)
2. [Performance Optimization](#performance-optimization)
3. [Security](#security)
4. [Backup and Recovery](#backup-and-recovery)
5. [Maintenance](#maintenance)
6. [Query Development](#query-development)
7. [Indexing Strategy](#indexing-strategy)
8. [Memory Management](#memory-management)
9. [Storage Configuration](#storage-configuration)
10. [Monitoring and Alerting](#monitoring-and-alerting)

## Database Design

### Normalization
- **Follow normalization principles** but denormalize where performance requires it
- **Avoid over-normalization** that leads to excessive joins
- **Use appropriate data types** - smallest possible type for the data
- **Implement proper referential integrity** with foreign keys

### Naming Conventions
```sql
-- Table names: PascalCase, descriptive
CREATE TABLE CustomerOrders

-- Column names: PascalCase, avoid abbreviations
CREATE TABLE Customers (
    CustomerID int IDENTITY(1,1) PRIMARY KEY,
    FirstName nvarchar(50) NOT NULL,
    LastName nvarchar(50) NOT NULL,
    EmailAddress nvarchar(255) UNIQUE NOT NULL
);

-- Stored procedures: sp_PascalCase or usp_PascalCase
CREATE PROCEDURE usp_GetCustomerOrders

-- Functions: fn_PascalCase or ufn_PascalCase
CREATE FUNCTION fn_CalculateTax

-- Indexes: IX_TableName_ColumnName
CREATE INDEX IX_Customers_LastName ON Customers(LastName)
```

### Data Types Best Practices
- **Use appropriate string types**: `VARCHAR` for ASCII, `NVARCHAR` for Unicode
- **Avoid `NTEXT`, `TEXT`, `IMAGE`** - use `NVARCHAR(MAX)`, `VARCHAR(MAX)`, `VARBINARY(MAX)`
- **Use `DECIMAL/NUMERIC`** for precise financial calculations
- **Use `DATETIME2`** instead of `DATETIME` for better precision
- **Specify lengths** for character fields to prevent excessive storage

## Performance Optimization

### Query Performance
- **Use appropriate WHERE clauses** with selective conditions first
- **Avoid functions on columns** in WHERE clauses
- **Use EXISTS instead of IN** for subqueries when possible
- **Limit result sets** with TOP, OFFSET/FETCH
- **Use proper JOIN syntax** - explicit JOINs over implicit

```sql
-- Good: SARGable query
SELECT CustomerID, FirstName, LastName
FROM Customers
WHERE CustomerID = @CustomerID;

-- Bad: Non-SARGable query
SELECT CustomerID, FirstName, LastName
FROM Customers
WHERE UPPER(LastName) = 'SMITH';

-- Better: Case-insensitive collation or proper indexing
SELECT CustomerID, FirstName, LastName
FROM Customers
WHERE LastName = 'Smith' COLLATE SQL_Latin1_General_CP1_CI_AS;
```

### Set-Based Operations
- **Use set-based operations** instead of cursors and loops
- **Minimize row-by-row processing**
- **Use CTEs and window functions** for complex logic

```sql
-- Good: Set-based update
UPDATE Orders
SET TotalAmount = (
    SELECT SUM(Quantity * UnitPrice)
    FROM OrderDetails
    WHERE OrderDetails.OrderID = Orders.OrderID
);

-- Avoid: Cursor-based processing unless absolutely necessary
```

## Security

### Authentication and Authorization
- **Use Windows Authentication** when possible
- **Implement principle of least privilege**
- **Create specific database roles** for different access levels
- **Avoid using SA account** for applications
- **Use contained databases** for better security isolation

### Data Protection
```sql
-- Use parameterized queries to prevent SQL injection
DECLARE @CustomerID int = 123;
SELECT * FROM Customers WHERE CustomerID = @CustomerID;

-- Implement data encryption for sensitive data
CREATE TABLE Customers (
    CustomerID int PRIMARY KEY,
    SSN varbinary(128) -- Encrypted
);

-- Use Always Encrypted for highly sensitive data
-- Use TDE (Transparent Data Encryption) for data at rest
```

### Auditing
- **Enable SQL Server Audit** for compliance requirements
- **Monitor failed login attempts**
- **Track schema changes**
- **Log data access patterns**

## Backup and Recovery

### Backup Strategy
```sql
-- Full backup weekly
BACKUP DATABASE [MyDatabase]
TO DISK = 'C:\Backups\MyDatabase_Full.bak'
WITH COMPRESSION, CHECKSUM;

-- Differential backup daily
BACKUP DATABASE [MyDatabase]
TO DISK = 'C:\Backups\MyDatabase_Diff.bak'
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM;

-- Transaction log backup every 15 minutes
BACKUP LOG [MyDatabase]
TO DISK = 'C:\Backups\MyDatabase_Log.trn'
WITH COMPRESSION, CHECKSUM;
```

### Recovery Best Practices
- **Test restore procedures regularly**
- **Document recovery procedures**
- **Verify backup integrity** with RESTORE VERIFYONLY
- **Use CHECKSUM** option for backup verification
- **Store backups offsite** or in different storage

## Maintenance

### Regular Maintenance Tasks
```sql
-- Index maintenance (weekly)
ALTER INDEX ALL ON [TableName] REBUILD
WITH (FILLFACTOR = 90, ONLINE = ON);

-- Update statistics (weekly)
UPDATE STATISTICS [TableName] WITH FULLSCAN;

-- Check database integrity (weekly)
DBCC CHECKDB('[DatabaseName]') WITH NO_INFOMSGS;
```

### Automated Maintenance
- **Use SQL Server Agent jobs** for scheduled tasks
- **Implement maintenance plans** for routine operations
- **Monitor job failures** and set up alerts
- **Keep maintenance windows** during low-activity periods

## Query Development

### Best Practices
```sql
-- Use explicit column lists
SELECT CustomerID, FirstName, LastName, EmailAddress
FROM Customers;

-- Avoid SELECT *
-- SELECT * FROM Customers; -- Avoid this

-- Use appropriate transaction isolation levels
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Handle errors properly
BEGIN TRY
    BEGIN TRANSACTION;
    
    -- Your SQL operations here
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    THROW; -- Re-throw the error
END CATCH;
```

### Stored Procedures
```sql
CREATE PROCEDURE usp_GetCustomerOrders
    @CustomerID int,
    @StartDate datetime2 = NULL,
    @EndDate datetime2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Input validation
    IF @CustomerID IS NULL OR @CustomerID <= 0
    BEGIN
        RAISERROR('Invalid CustomerID provided', 16, 1);
        RETURN;
    END
    
    -- Main query
    SELECT 
        o.OrderID,
        o.OrderDate,
        o.TotalAmount
    FROM Orders o
    WHERE o.CustomerID = @CustomerID
        AND (@StartDate IS NULL OR o.OrderDate >= @StartDate)
        AND (@EndDate IS NULL OR o.OrderDate <= @EndDate)
    ORDER BY o.OrderDate DESC;
END;
```

## Indexing Strategy

### Index Design
```sql
-- Clustered index on primary key (usually)
CREATE CLUSTERED INDEX IX_Orders_OrderID ON Orders(OrderID);

-- Non-clustered indexes for frequent WHERE clauses
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID 
ON Orders(CustomerID)
INCLUDE (OrderDate, TotalAmount);

-- Composite indexes - most selective column first
CREATE NONCLUSTERED INDEX IX_Orders_Status_Date 
ON Orders(OrderStatus, OrderDate);
```

### Index Maintenance
- **Monitor index usage** with DMVs
- **Remove unused indexes**
- **Consider index consolidation**
- **Use proper fill factor** (85-95% typically)

## Memory Management

### Configuration
```sql
-- Set maximum server memory (leave memory for OS)
EXEC sp_configure 'max server memory (MB)', 12288; -- 12GB
RECONFIGURE;

-- Monitor memory usage
SELECT 
    counter_name,
    cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name = 'SQLServer:Memory Manager';
```

### Buffer Pool Management
- **Monitor buffer cache hit ratio** (should be >95%)
- **Identify memory pressure** with DMVs
- **Use Resource Governor** for workload management

## Storage Configuration

### File Management
```sql
-- Separate data and log files on different drives
CREATE DATABASE [MyDatabase]
ON (
    NAME = 'MyDatabase_Data',
    FILENAME = 'D:\Data\MyDatabase_Data.mdf',
    SIZE = 1024MB,
    FILEGROWTH = 256MB
)
LOG ON (
    NAME = 'MyDatabase_Log',
    FILENAME = 'L:\Logs\MyDatabase_Log.ldf',
    SIZE = 256MB,
    FILEGROWTH = 64MB
);
```

### Best Practices
- **Use multiple data files** for large databases
- **Set appropriate initial sizes** and growth increments
- **Avoid auto-shrink**
- **Monitor disk space** regularly
- **Use SSDs** for high-performance workloads

## Monitoring and Alerting

### Key Metrics to Monitor
```sql
-- Query to check blocking
SELECT 
    blocking_session_id,
    session_id,
    wait_type,
    wait_time,
    wait_resource
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0;

-- Monitor long-running queries
SELECT 
    r.session_id,
    r.start_time,
    r.total_elapsed_time,
    t.text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.total_elapsed_time > 30000; -- 30 seconds
```

### Alerts to Configure
- **Failed backups**
- **Long-running queries**
- **Blocking processes**
- **Database space usage**
- **Failed SQL Agent jobs**
- **Security breaches**

## Additional Resources

### Performance Monitoring Queries
- Check `Troubleshooting/DiagnosticQueries/` folder for specific diagnostic scripts
- Use `Performance/MonitoringScripts/` for ongoing monitoring

### Maintenance Scripts
- See `Maintenance/` folder for automated maintenance procedures
- Review `LogManagement/` for transaction log management

---

**Note**: Always test these practices in a development environment before applying to production systems. Adjust recommendations based on your specific workload and requirements.

**Last Updated**: September 28, 2025