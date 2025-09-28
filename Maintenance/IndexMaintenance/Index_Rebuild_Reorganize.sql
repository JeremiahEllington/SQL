/*
=================================================================
Index Maintenance Script - Rebuild/Reorganize
=================================================================
Description: Intelligent index maintenance based on fragmentation
Author: Jeremiah Ellington
Date: 2025-09-28
Logic: 
  - Fragmentation > 30%: REBUILD
  - Fragmentation 10-30%: REORGANIZE  
  - Fragmentation < 10%: No action needed
=================================================================
*/

SET NOCOUNT ON;

-- Configuration
DECLARE @DatabaseName NVARCHAR(128) = DB_NAME(); -- Current database
DECLARE @FragmentationThreshold_Reorganize FLOAT = 10.0;
DECLARE @FragmentationThreshold_Rebuild FLOAT = 30.0;
DECLARE @MinPageCount INT = 1000; -- Only process indexes with at least 1000 pages
DECLARE @MaxDuration_Minutes INT = 60; -- Stop processing after 60 minutes
DECLARE @OnlineRebuild BIT = 1; -- Use ONLINE rebuilds if available
DECLARE @UpdateStatistics BIT = 1; -- Update statistics after maintenance

-- Variables
DECLARE @StartTime DATETIME2 = GETDATE();
DECLARE @CurrentTime DATETIME2;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @Message NVARCHAR(500);
DECLARE @ProcessedCount INT = 0;
DECLARE @SkippedCount INT = 0;

-- Temp table to store fragmentation info
IF OBJECT_ID('tempdb..#IndexFragmentation') IS NOT NULL
    DROP TABLE #IndexFragmentation;

CREATE TABLE #IndexFragmentation (
    SchemaName NVARCHAR(128),
    TableName NVARCHAR(128),
    IndexName NVARCHAR(128),
    IndexID INT,
    PartitionNumber INT,
    FragmentationPercent FLOAT,
    PageCount BIGINT,
    MaintenanceAction NVARCHAR(20)
);

PRINT '=================================================';
PRINT 'Index Maintenance Process Started';
PRINT 'Database: ' + @DatabaseName;
PRINT 'Start Time: ' + CONVERT(NVARCHAR, @StartTime, 120);
PRINT 'Reorganize Threshold: ' + CONVERT(NVARCHAR, @FragmentationThreshold_Reorganize) + '%';
PRINT 'Rebuild Threshold: ' + CONVERT(NVARCHAR, @FragmentationThreshold_Rebuild) + '%';
PRINT 'Minimum Page Count: ' + CONVERT(NVARCHAR, @MinPageCount);
PRINT '=================================================';

-- Get fragmentation information
PRINT 'Analyzing index fragmentation...';

INSERT INTO #IndexFragmentation
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    i.index_id AS IndexID,
    ps.partition_number AS PartitionNumber,
    ps.avg_fragmentation_in_percent AS FragmentationPercent,
    ps.page_count AS PageCount,
    CASE 
        WHEN ps.avg_fragmentation_in_percent >= @FragmentationThreshold_Rebuild THEN 'REBUILD'
        WHEN ps.avg_fragmentation_in_percent >= @FragmentationThreshold_Reorganize THEN 'REORGANIZE'
        ELSE 'NONE'
    END AS MaintenanceAction
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
INNER JOIN sys.tables t ON i.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE ps.page_count >= @MinPageCount
    AND i.is_disabled = 0
    AND i.is_hypothetical = 0
    AND ps.avg_fragmentation_in_percent >= @FragmentationThreshold_Reorganize
ORDER BY ps.avg_fragmentation_in_percent DESC;

-- Display summary
SELECT 
    MaintenanceAction,
    COUNT(*) AS IndexCount,
    AVG(FragmentationPercent) AS AvgFragmentation,
    MIN(FragmentationPercent) AS MinFragmentation,
    MAX(FragmentationPercent) AS MaxFragmentation
FROM #IndexFragmentation
GROUP BY MaintenanceAction
ORDER BY MaintenanceAction;

-- Process each index
DECLARE index_cursor CURSOR FOR
SELECT SchemaName, TableName, IndexName, IndexID, PartitionNumber, 
       FragmentationPercent, MaintenanceAction
FROM #IndexFragmentation
WHERE MaintenanceAction IN ('REBUILD', 'REORGANIZE')
ORDER BY FragmentationPercent DESC;

DECLARE @SchemaName NVARCHAR(128), @TableName NVARCHAR(128), @IndexName NVARCHAR(128);
DECLARE @IndexID INT, @PartitionNumber INT, @FragmentationPercent FLOAT, @MaintenanceAction NVARCHAR(20);

OPEN index_cursor;
FETCH NEXT FROM index_cursor INTO @SchemaName, @TableName, @IndexName, @IndexID, @PartitionNumber, @FragmentationPercent, @MaintenanceAction;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @CurrentTime = GETDATE();
    
    -- Check if we've exceeded our time limit
    IF DATEDIFF(MINUTE, @StartTime, @CurrentTime) >= @MaxDuration_Minutes
    BEGIN
        PRINT 'Time limit reached (' + CONVERT(NVARCHAR, @MaxDuration_Minutes) + ' minutes). Stopping maintenance.';
        BREAK;
    END
    
    BEGIN TRY
        -- Build maintenance command
        IF @MaintenanceAction = 'REBUILD'
        BEGIN
            SET @SQL = 'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REBUILD';
            
            -- Add partition specification if needed
            IF @PartitionNumber > 1
                SET @SQL = @SQL + ' PARTITION = ' + CONVERT(NVARCHAR, @PartitionNumber);
            
            -- Add ONLINE option if supported and requested
            IF @OnlineRebuild = 1
                SET @SQL = @SQL + ' WITH (ONLINE = ON, MAXDOP = 0)';
            ELSE
                SET @SQL = @SQL + ' WITH (MAXDOP = 0)';
        END
        ELSE IF @MaintenanceAction = 'REORGANIZE'
        BEGIN
            SET @SQL = 'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REORGANIZE';
            
            -- Add partition specification if needed
            IF @PartitionNumber > 1
                SET @SQL = @SQL + ' PARTITION = ' + CONVERT(NVARCHAR, @PartitionNumber);
        END
        
        -- Execute maintenance
        SET @Message = @MaintenanceAction + ' - [' + @SchemaName + '].[' + @TableName + '].[' + @IndexName + '] (' + 
                      FORMAT(@FragmentationPercent, 'N2') + '% fragmented)';
        PRINT @Message;
        
        EXEC sp_executesql @SQL;
        
        SET @ProcessedCount = @ProcessedCount + 1;
        
    END TRY
    BEGIN CATCH
        PRINT 'ERROR processing [' + @SchemaName + '].[' + @TableName + '].[' + @IndexName + ']: ' + ERROR_MESSAGE();
        SET @SkippedCount = @SkippedCount + 1;
    END CATCH
    
    FETCH NEXT FROM index_cursor INTO @SchemaName, @TableName, @IndexName, @IndexID, @PartitionNumber, @FragmentationPercent, @MaintenanceAction;
END

CLOSE index_cursor;
DEALLOCATE index_cursor;

-- Update statistics if requested
IF @UpdateStatistics = 1
BEGIN
    PRINT 'Updating statistics for processed tables...';
    
    DECLARE stats_cursor CURSOR FOR
    SELECT DISTINCT '[' + SchemaName + '].[' + TableName + ']' as FullTableName
    FROM #IndexFragmentation
    WHERE MaintenanceAction IN ('REBUILD', 'REORGANIZE');
    
    DECLARE @FullTableName NVARCHAR(256);
    
    OPEN stats_cursor;
    FETCH NEXT FROM stats_cursor INTO @FullTableName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @SQL = 'UPDATE STATISTICS ' + @FullTableName + ' WITH FULLSCAN';
            EXEC sp_executesql @SQL;
            PRINT 'Updated statistics: ' + @FullTableName;
        END TRY
        BEGIN CATCH
            PRINT 'ERROR updating statistics for ' + @FullTableName + ': ' + ERROR_MESSAGE();
        END CATCH
        
        FETCH NEXT FROM stats_cursor INTO @FullTableName;
    END
    
    CLOSE stats_cursor;
    DEALLOCATE stats_cursor;
END

-- Final summary
PRINT '';
PRINT '=================================================';
PRINT 'Index Maintenance Complete';
PRINT 'Processed Indexes: ' + CONVERT(NVARCHAR, @ProcessedCount);
PRINT 'Skipped (Errors): ' + CONVERT(NVARCHAR, @SkippedCount);
PRINT 'Total Duration: ' + CONVERT(NVARCHAR, DATEDIFF(MINUTE, @StartTime, GETDATE())) + ' minutes';
PRINT '=================================================';

-- Cleanup
DROP TABLE #IndexFragmentation;