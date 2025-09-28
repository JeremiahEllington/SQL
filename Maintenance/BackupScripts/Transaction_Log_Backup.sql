/*
=================================================================
Transaction Log Backup Script
=================================================================
Description: Transaction log backup with error handling and cleanup
Author: Jeremiah Ellington
Date: 2025-09-28
Usage: Modify variables for your environment
Note: Only works with databases in FULL recovery model
=================================================================
*/

SET NOCOUNT ON;

-- Configuration Variables
DECLARE @DatabaseName NVARCHAR(128) = 'YourDatabaseName'; -- Change this
DECLARE @BackupPath NVARCHAR(500) = 'C:\Backups\Logs\'; -- Change this
DECLARE @RetentionHours INT = 48; -- Keep log backups for 48 hours
DECLARE @BackupFileName NVARCHAR(500);
DECLARE @BackupCommand NVARCHAR(MAX);
DECLARE @StartTime DATETIME2 = GETDATE();

-- Generate backup filename
SET @BackupFileName = @BackupPath + @DatabaseName + '_Log_' + 
    FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + '.trn';

-- Verify database exists and is in FULL recovery model
IF NOT EXISTS (
    SELECT name 
    FROM sys.databases 
    WHERE name = @DatabaseName 
    AND recovery_model_desc = 'FULL'
)
BEGIN
    PRINT 'ERROR: Database [' + @DatabaseName + '] does not exist or is not in FULL recovery model!';
    PRINT 'Current recovery model: ' + ISNULL((
        SELECT recovery_model_desc 
        FROM sys.databases 
        WHERE name = @DatabaseName
    ), 'Database not found');
    RETURN;
END

PRINT 'Starting Transaction Log Backup: ' + @DatabaseName;
PRINT 'Backup File: ' + @BackupFileName;

BEGIN TRY
    -- Backup transaction log
    SET @BackupCommand = 'BACKUP LOG [' + @DatabaseName + '] ' +
        'TO DISK = ''' + @BackupFileName + ''' ' +
        'WITH ' +
        'COMPRESSION, ' +
        'CHECKSUM, ' +
        'INIT, ' +
        'FORMAT, ' +
        'DESCRIPTION = ''Transaction log backup of ' + @DatabaseName + ' created on ' + 
        CONVERT(NVARCHAR, @StartTime, 120) + ''''
    
    EXEC sp_executesql @BackupCommand;
    
    PRINT 'Transaction log backup completed successfully.';
    PRINT 'Elapsed Time: ' + CONVERT(NVARCHAR, DATEDIFF(SECOND, @StartTime, GETDATE())) + ' seconds';
    
    -- Cleanup old log backup files
    PRINT 'Cleaning up old log backup files older than ' + CONVERT(NVARCHAR, @RetentionHours) + ' hours...';
    
    DECLARE @CleanupCommand NVARCHAR(1000);
    SET @CleanupCommand = 'FORFILES /P "' + @BackupPath + '" /M "' + @DatabaseName + '_Log_*.trn" ' +
        '/C "CMD /C IF @fdate LSS ' + CONVERT(NVARCHAR, GETDATE() - @RetentionHours/24.0, 112) + ' DEL @path" 2>NUL';
    
    EXEC xp_cmdshell @CleanupCommand, NO_OUTPUT;
    PRINT 'Cleanup completed.';
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Transaction log backup failed!';
    PRINT 'Error: ' + ERROR_MESSAGE();
    THROW;
END CATCH