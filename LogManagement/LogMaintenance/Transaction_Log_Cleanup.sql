/*
=================================================================
Transaction Log Maintenance and Cleanup Script
=================================================================
Description: Comprehensive transaction log management and cleanup
Author: Jeremiah Ellington
Date: 2025-09-28
Features:
  - Log file size monitoring
  - Virtual log file (VLF) analysis
  - Log space usage reporting
  - Log shrink operations (when safe)
=================================================================
*/

SET NOCOUNT ON;

-- Configuration
DECLARE @DatabaseName NVARCHAR(128) = DB_NAME(); -- Current database
DECLARE @MaxLogSizeGB FLOAT = 10.0; -- Alert if log file exceeds this size
DECLARE @LogSpaceUsedThreshold FLOAT = 80.0; -- Alert if log space used > 80%
DECLARE @MaxVLFCount INT = 50; -- Alert if VLF count exceeds this
DECLARE @ShrinkLogFile BIT = 0; -- Set to 1 to allow log shrinking
DECLARE @TargetLogSizeMB INT = 1024; -- Target size after shrink (MB)

PRINT '=================================================';
PRINT 'Transaction Log Maintenance Report';
PRINT 'Database: ' + @DatabaseName;
PRINT 'Date: ' + CONVERT(NVARCHAR, GETDATE(), 120);
PRINT '=================================================';

-- 1. Log File Information
PRINT '';
PRINT '1. LOG FILE INFORMATION';
PRINT '------------------------';

SELECT 
    name AS LogFileName,
    physical_name AS PhysicalPath,
    CAST(size * 8.0 / 1024 AS DECIMAL(10,2)) AS CurrentSize_MB,
    CAST(size * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS CurrentSize_GB,
    CASE 
        WHEN max_size = -1 THEN 'Unlimited'
        WHEN max_size = 0 THEN 'No Growth'
        ELSE CAST(max_size * 8.0 / 1024 / 1024 AS NVARCHAR) + ' GB'
    END AS MaxSize,
    CASE 
        WHEN is_percent_growth = 1 THEN CAST(growth AS NVARCHAR) + '%'
        ELSE CAST(growth * 8 / 1024 AS NVARCHAR) + ' MB'
    END AS GrowthSetting
FROM sys.database_files
WHERE type_desc = 'LOG';

-- 2. Log Space Usage
PRINT '';
PRINT '2. LOG SPACE USAGE';
PRINT '-------------------';

DECLARE @LogSpaceUsed TABLE (
    DatabaseName NVARCHAR(128),
    LogSize_MB FLOAT,
    LogSpaceUsed_Percent FLOAT,
    Status INT
);

INSERT INTO @LogSpaceUsed
EXEC ('DBCC SQLPERF(LOGSPACE)');

SELECT 
    DatabaseName,
    CAST(LogSize_MB AS DECIMAL(10,2)) AS LogSize_MB,
    CAST(LogSize_MB / 1024 AS DECIMAL(10,2)) AS LogSize_GB,
    CAST(LogSpaceUsed_Percent AS DECIMAL(5,2)) AS LogSpaceUsed_Percent,
    CASE 
        WHEN LogSpaceUsed_Percent > @LogSpaceUsedThreshold THEN 'WARNING: High usage!'
        WHEN LogSize_MB / 1024 > @MaxLogSizeGB THEN 'WARNING: Large log file!'
        ELSE 'OK'
    END AS Status
FROM @LogSpaceUsed
WHERE DatabaseName = @DatabaseName;

-- 3. Virtual Log Files (VLF) Analysis
PRINT '';
PRINT '3. VIRTUAL LOG FILE (VLF) ANALYSIS';
PRINT '------------------------------------';

DECLARE @VLFInfo TABLE (
    RecoveryUnitId INT,
    FileId INT,
    FileSize BIGINT,
    StartOffset BIGINT,
    FSeqNo BIGINT,
    Status INT,
    Parity INT,
    CreateLSN NUMERIC(38,0)
);

INSERT INTO @VLFInfo
EXEC ('DBCC LOGINFO(''' + @DatabaseName + ''')');

DECLARE @VLFCount INT;
SELECT @VLFCount = COUNT(*) FROM @VLFInfo;

SELECT 
    @VLFCount AS TotalVLFs,
    COUNT(CASE WHEN Status = 2 THEN 1 END) AS ActiveVLFs,
    COUNT(CASE WHEN Status = 0 THEN 1 END) AS InactiveVLFs,
    CASE 
        WHEN @VLFCount > @MaxVLFCount THEN 'WARNING: Too many VLFs!'
        ELSE 'OK'
    END AS VLFStatus,
    'Consider log file management if VLF count is high' AS Recommendation
FROM @VLFInfo;

-- 4. Log Reuse Wait Description
PRINT '';
PRINT '4. LOG REUSE ANALYSIS';
PRINT '----------------------';

SELECT 
    name AS DatabaseName,
    log_reuse_wait_desc AS LogReuseWait,
    CASE log_reuse_wait_desc
        WHEN 'NOTHING' THEN 'Log can be reused (normal state)'
        WHEN 'CHECKPOINT' THEN 'Waiting for checkpoint to complete'
        WHEN 'LOG_BACKUP' THEN 'Waiting for log backup (Full/Bulk-Logged recovery)'
        WHEN 'ACTIVE_BACKUP_OR_RESTORE' THEN 'Backup or restore operation in progress'
        WHEN 'ACTIVE_TRANSACTION' THEN 'Long-running active transaction'
        WHEN 'DATABASE_MIRRORING' THEN 'Database mirroring is behind'
        WHEN 'REPLICATION' THEN 'Replication not caught up'
        WHEN 'DATABASE_SNAPSHOT_CREATION' THEN 'Database snapshot being created'
        WHEN 'LOG_SCAN' THEN 'Log scan operation in progress'
        WHEN 'AVAILABILITY_REPLICA' THEN 'Always On availability replica issue'
        WHEN 'OLDEST_PAGE' THEN 'Waiting for oldest page to be written'
        WHEN 'XTP_CHECKPOINT' THEN 'In-Memory OLTP checkpoint pending'
        ELSE 'Other/Unknown reason'
    END AS Description,
    recovery_model_desc AS RecoveryModel
FROM sys.databases
WHERE name = @DatabaseName;

-- 5. Recent Log Backups (if any)
PRINT '';
PRINT '5. RECENT LOG BACKUPS';
PRINT '----------------------';

SELECT TOP 5
    backup_start_date,
    backup_finish_date,
    DATEDIFF(SECOND, backup_start_date, backup_finish_date) AS Duration_Seconds,
    CAST(backup_size / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS BackupSize_MB,
    physical_device_name
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE database_name = @DatabaseName
    AND type = 'L' -- Log backups
ORDER BY backup_start_date DESC;

IF @@ROWCOUNT = 0
    PRINT 'No recent log backups found.';

-- 6. Log Growth Events (Recent)
PRINT '';
PRINT '6. RECENT LOG GROWTH EVENTS';
PRINT '-----------------------------';

-- Note: This requires default trace to be enabled
DECLARE @TraceFile NVARCHAR(500);
SELECT @TraceFile = REVERSE(SUBSTRING(REVERSE(path), CHARINDEX('\\', REVERSE(path)), LEN(path))) + 'log.trc'
FROM sys.traces
WHERE is_default = 1;

IF @TraceFile IS NOT NULL
BEGIN
    SELECT TOP 10
        StartTime,
        DatabaseName,
        FileName,
        CAST(IntegerData * 8.0 / 1024 AS DECIMAL(10,2)) AS GrowthSize_MB,
        Duration / 1000 AS Duration_Seconds
    FROM fn_trace_gettable(@TraceFile, DEFAULT)
    WHERE EventClass = 93 -- Data/Log File Auto Grow
        AND DatabaseName = @DatabaseName
        AND FileName LIKE '%.ldf'
        AND StartTime >= DATEADD(DAY, -7, GETDATE())
    ORDER BY StartTime DESC;
    
    IF @@ROWCOUNT = 0
        PRINT 'No recent log growth events found.';
END
ELSE
    PRINT 'Default trace not available for growth analysis.';

-- 7. Log Shrink Operation (if enabled)
IF @ShrinkLogFile = 1
BEGIN
    PRINT '';
    PRINT '7. LOG SHRINK OPERATION';
    PRINT '------------------------';
    
    -- Check if it's safe to shrink
    DECLARE @LogSpaceUsed_Current FLOAT;
    SELECT @LogSpaceUsed_Current = LogSpaceUsed_Percent
    FROM @LogSpaceUsed
    WHERE DatabaseName = @DatabaseName;
    
    IF @LogSpaceUsed_Current < 50 -- Only shrink if less than 50% used
    BEGIN
        BEGIN TRY
            PRINT 'Attempting to shrink log file to ' + CAST(@TargetLogSizeMB AS NVARCHAR) + ' MB...';
            
            DECLARE @LogFileName NVARCHAR(128);
            SELECT @LogFileName = name
            FROM sys.database_files
            WHERE type_desc = 'LOG';
            
            DBCC SHRINKFILE(@LogFileName, @TargetLogSizeMB);
            PRINT 'Log shrink operation completed.';
            
        END TRY
        BEGIN CATCH
            PRINT 'Error during log shrink: ' + ERROR_MESSAGE();
        END CATCH
    END
    ELSE
        PRINT 'Log shrink skipped - log space usage too high (' + CAST(@LogSpaceUsed_Current AS NVARCHAR) + '%)';
END

-- 8. Recommendations
PRINT '';
PRINT '8. RECOMMENDATIONS';
PRINT '-------------------';

DECLARE @LogSize_Current FLOAT, @LogUsed_Current FLOAT;
SELECT 
    @LogSize_Current = LogSize_MB,
    @LogUsed_Current = LogSpaceUsed_Percent
FROM @LogSpaceUsed
WHERE DatabaseName = @DatabaseName;

IF @LogUsed_Current > @LogSpaceUsedThreshold
    PRINT '• High log space usage detected - consider more frequent log backups';

IF @LogSize_Current / 1024 > @MaxLogSizeGB
    PRINT '• Large log file detected - monitor for unusual activity';

IF @VLFCount > @MaxVLFCount
    PRINT '• High VLF count detected - consider log file management';

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName AND log_reuse_wait_desc <> 'NOTHING')
    PRINT '• Log reuse is being prevented - check log_reuse_wait_desc';

PRINT '';
PRINT 'General Recommendations:';
PRINT '• Regular log backups (every 15-30 minutes in production)';
PRINT '• Monitor for long-running transactions';
PRINT '• Set appropriate initial log file size to prevent auto-growth';
PRINT '• Use fixed-size growth increments rather than percentage';

PRINT '';
PRINT '=================================================';
PRINT 'Transaction Log Maintenance Report Complete';
PRINT '=================================================';