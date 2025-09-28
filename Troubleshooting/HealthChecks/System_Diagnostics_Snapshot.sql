/*
============================================================
System Diagnostics Snapshot
============================================================
Description: Captures a broad system state snapshot for troubleshooting.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

PRINT '=== SERVER VERSION ===';
SELECT @@SERVERNAME AS ServerName, @@VERSION AS VersionInfo;

PRINT '\n=== UPTIME (Days) ===';
SELECT DATEDIFF(DAY, sqlserver_start_time, SYSDATETIME()) AS UptimeDays
FROM sys.dm_os_sys_info;

PRINT '\n=== TOP CPU QUERIES (Last Hour) ===';
SELECT TOP 10
    qs.total_worker_time/1000 AS TotalCPU_ms,
    qs.execution_count,
    (qs.total_worker_time/qs.execution_count)/1000 AS AvgCPU_ms,
    qs.total_elapsed_time/1000 AS TotalElapsed_ms,
    DB_NAME(st.dbid) AS DatabaseName,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time >= DATEADD(HOUR, -1, SYSDATETIME())
ORDER BY TotalCPU_ms DESC;

PRINT '\n=== HIGH I/O FILES ===';
SELECT TOP 10
    DB_NAME(vfs.database_id) AS DatabaseName,
    mf.name AS LogicalName,
    mf.type_desc,
    vfs.num_of_reads,
    vfs.num_of_writes,
    (vfs.io_stall_read_ms + vfs.io_stall_write_ms) AS TotalStall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY TotalStall_ms DESC;

PRINT '\n=== MEMORY CLERKS (Top Consumers) ===';
SELECT TOP 10
    mc.type AS ClerkType,
    SUM(mc.pages_kb)/1024 AS MemoryMB
FROM sys.dm_os_memory_clerks mc
GROUP BY mc.type
ORDER BY MemoryMB DESC;

PRINT '\n=== ACTIVE TRANSACTIONS (Over 1 Minute) ===';
SELECT 
    at.transaction_id,
    at.transaction_begin_time,
    DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) AS DurationSeconds,
    s.session_id,
    s.login_name,
    DB_NAME(dt.database_id) AS DatabaseName
FROM sys.dm_tran_active_transactions at
JOIN sys.dm_tran_session_transactions st ON at.transaction_id = st.transaction_id
JOIN sys.dm_tran_database_transactions dt ON at.transaction_id = dt.transaction_id
JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
WHERE at.transaction_begin_time <= DATEADD(MINUTE, -1, SYSDATETIME())
ORDER BY DurationSeconds DESC;

PRINT '\n=== TEMPDB USAGE BY SESSION ===';
SELECT TOP 15
    s.session_id,
    s.login_name,
    (tu.user_objects_alloc_page_count - tu.user_objects_dealloc_page_count) * 8 / 1024 AS UserObjectsMB,
    (tu.internal_objects_alloc_page_count - tu.internal_objects_dealloc_page_count) * 8 / 1024 AS InternalObjectsMB
FROM sys.dm_db_session_space_usage tu
JOIN sys.dm_exec_sessions s ON tu.session_id = s.session_id
WHERE (tu.user_objects_alloc_page_count - tu.user_objects_dealloc_page_count) > 0
ORDER BY UserObjectsMB DESC;

PRINT '\n=== OPEN CURSORS (Top) ===';
SELECT TOP 10 * FROM sys.dm_exec_cursors(0) ORDER BY creation_time DESC;

PRINT '\n=== RECENT ERRORS (Severity >= 16) ===';
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;
CREATE TABLE #ErrorLog (LogDate DATETIME, ProcessInfo NVARCHAR(50), Text NVARCHAR(4000));
INSERT INTO #ErrorLog EXEC xp_readerrorlog 0, 1;
SELECT TOP 50 * FROM #ErrorLog WHERE Text LIKE 'Error:%' ORDER BY LogDate DESC;

PRINT '\nSnapshot complete.';