/*
=================================================================
Full Database Backup Script
=================================================================
Description: Comprehensive full database backup with error handling
Author: Jeremiah Ellington
Date: 2025-09-28
Usage: Modify @DatabaseName and @BackupPath variables
=================================================================
*/

SET NOCOUNT ON;

-- Configuration Variables
DECLARE @DatabaseName NVARCHAR(128) = 'YourDatabaseName'; -- Change this
DECLARE @BackupPath NVARCHAR(500) = 'C:\Backups\'; -- Change this
DECLARE @BackupFileName NVARCHAR(500);
DECLARE @BackupCommand NVARCHAR(MAX);
DECLARE @StartTime DATETIME2 = GETDATE();
DECLARE @EndTime DATETIME2;
DECLARE @ElapsedTime NVARCHAR(50);

-- Generate backup filename with timestamp
SET @BackupFileName = @BackupPath + @DatabaseName + '_Full_' + 
    FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + '.bak';

-- Verify database exists
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = @DatabaseName)
BEGIN
    PRINT 'ERROR: Database [' + @DatabaseName + '] does not exist!';
    RETURN;
END

-- Verify backup directory exists (basic check)
IF NOT EXISTS (SELECT * FROM sys.dm_os_file_exists(@BackupPath))
BEGIN
    PRINT 'ERROR: Backup directory does not exist: ' + @BackupPath;
    RETURN;
END

PRINT '=================================================';
PRINT 'Starting Full Backup Process';
PRINT 'Database: ' + @DatabaseName;
PRINT 'Backup File: ' + @BackupFileName;
PRINT 'Start Time: ' + CONVERT(NVARCHAR, @StartTime, 120);
PRINT '=================================================';

BEGIN TRY
    -- Build backup command
    SET @BackupCommand = 'BACKUP DATABASE [' + @DatabaseName + '] ' +
        'TO DISK = ''' + @BackupFileName + ''' ' +
        'WITH ' +
        'COMPRESSION, ' +
        'CHECKSUM, ' +
        'INIT, ' +
        'FORMAT, ' +
        'STATS = 5, ' +
        'DESCRIPTION = ''Full backup of ' + @DatabaseName + ' created on ' + 
        CONVERT(NVARCHAR, @StartTime, 120) + ''''
    
    -- Execute backup
    EXEC sp_executesql @BackupCommand;
    
    -- Calculate elapsed time
    SET @EndTime = GETDATE();
    SET @ElapsedTime = CONVERT(NVARCHAR, DATEDIFF(SECOND, @StartTime, @EndTime)) + ' seconds';
    
    PRINT '';
    PRINT 'SUCCESS: Backup completed successfully!';
    PRINT 'End Time: ' + CONVERT(NVARCHAR, @EndTime, 120);
    PRINT 'Elapsed Time: ' + @ElapsedTime;
    
    -- Verify backup
    PRINT 'Verifying backup integrity...';
    RESTORE VERIFYONLY FROM DISK = @BackupFileName WITH CHECKSUM;
    PRINT 'Backup verification completed successfully.';
    
    -- Get backup file size
    DECLARE @FileSize BIGINT;
    DECLARE @FileSizeMB NVARCHAR(20);
    
    EXEC master.dbo.xp_fileexist @BackupFileName;
    
    SELECT @FileSize = size_on_disk_bytes 
    FROM sys.dm_io_backup_tapes 
    WHERE physical_device_name = @BackupFileName;
    
    IF @FileSize IS NOT NULL
    BEGIN
        SET @FileSizeMB = CONVERT(NVARCHAR, @FileSize / 1024 / 1024) + ' MB';
        PRINT 'Backup File Size: ' + @FileSizeMB;
    END
    
END TRY
BEGIN CATCH
    PRINT '';
    PRINT 'ERROR: Backup failed!';
    PRINT 'Error Number: ' + CONVERT(NVARCHAR, ERROR_NUMBER());
    PRINT 'Error Message: ' + ERROR_MESSAGE();
    PRINT 'Error Line: ' + CONVERT(NVARCHAR, ERROR_LINE());
    
    -- Clean up failed backup file if it exists
    DECLARE @CleanupCommand NVARCHAR(500);
    SET @CleanupCommand = 'DEL "' + @BackupFileName + '"';
    
    BEGIN TRY
        EXEC xp_cmdshell @CleanupCommand, NO_OUTPUT;
        PRINT 'Failed backup file cleaned up.';
    END TRY
    BEGIN CATCH
        PRINT 'Warning: Could not clean up failed backup file.';
    END CATCH
    
    THROW;
END CATCH

PRINT '=================================================';
PRINT 'Backup Process Complete';
PRINT '=================================================';

-- Optional: Log backup information to a tracking table
-- Uncomment and modify as needed
/*
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'BackupLog')
BEGIN
    INSERT INTO BackupLog (DatabaseName, BackupType, BackupPath, StartTime, EndTime, Status)
    VALUES (@DatabaseName, 'Full', @BackupFileName, @StartTime, @EndTime, 'Success');
END
*/