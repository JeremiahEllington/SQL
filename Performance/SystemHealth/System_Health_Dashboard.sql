/*
============================================================
System Health Dashboard
============================================================
Description: Consolidated health snapshot: CPU, Memory, IO, Blocking, Sessions
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

PRINT '=== CPU UTILIZATION (Last 5 minutes) ===';
SELECT TOP 30
    record_id,
    DATEADD(ms, [timestamp] - sys.ms_ticks, GETDATE()) AS EventTime,
    SQLProcessUtilization,
    SystemIdle,
    100 - SystemIdle - SQLProcessUtilization AS OtherProcessUtilization
FROM sys.dm_os_ring_buffers rb
CROSS JOIN sys.dm_os_sys_info sys
WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
  AND record_id % 2 = 0
ORDER BY record_id DESC;

PRINT '\n=== MEMORY STATUS ===';
SELECT 
    physical_memory_kb/1024 AS PhysicalMemory_MB,
    virtual_address_space_committed_kb/1024 AS VASCommitted_MB,
    virtual_address_space_available_kb/1024 AS VASAvailable_MB,
    committed_kb/1024 AS Committed_MB,
    committed_target_kb/1024 AS TargetCommitted_MB
FROM sys.dm_os_sys_memory;

PRINT '\n=== TOP WAIT STATS (Filtered) ===';
SELECT TOP 10
    wait_type,
    wait_time_ms/1000.0 AS Wait_Sec,
    (wait_time_ms - signal_wait_time_ms)/1000.0 AS Resource_Sec,
    signal_wait_time_ms/1000.0 AS Signal_Sec,
    waiting_tasks_count AS WaitCount
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE 'SLEEP%'
  AND wait_type NOT IN ('CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN','SQLTRACE_BUFFER_FLUSH','BROKER_EVENTHANDLER','BAD_PAGE_PROCESS','DBMIRROR_EVENTS_QUEUE','BROKER_RECEIVE_WAITFOR','ONDEMAND_TASK_QUEUE','DBMIRRORING_CMD','HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE','XTP_HOST_WAIT','SP_SERVER_DIAGNOSTICS_SLEEP')
ORDER BY wait_time_ms DESC;

PRINT '\n=== CURRENT BLOCKING SESSIONS ===';
SELECT 
    r.session_id AS BlockedSessionID,
    r.blocking_session_id AS BlockingSessionID,
    r.status,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    r.cpu_time,
    r.logical_reads,
    DB_NAME(r.database_id) AS DatabaseName,
    SUBSTRING(t.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset)/2)+1) AS RunningStatement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;

PRINT '\n=== TOP SESSIONS BY CPU (Active) ===';
SELECT TOP 10
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.cpu_time,
    r.total_elapsed_time,
    r.logical_reads,
    DB_NAME(r.database_id) AS DatabaseName,
    SUBSTRING(t.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset)/2)+1) AS StatementText
FROM sys.dm_exec_sessions s
JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
ORDER BY r.cpu_time DESC;

PRINT '\n=== IO HOTSPOTS (Files by Read/Write) ===';
SELECT TOP 10
    DB_NAME(vfs.database_id) AS DatabaseName,
    mf.name AS LogicalName,
    mf.type_desc AS FileType,
    vfs.num_of_reads,
    vfs.num_of_writes,
    (vfs.num_of_reads + vfs.num_of_writes) AS TotalIO,
    vfs.io_stall_read_ms,
    vfs.io_stall_write_ms,
    (vfs.io_stall_read_ms + vfs.io_stall_write_ms) AS TotalStall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY TotalIO DESC;

PRINT '\n=== RECENT ERROR LOG ENTRIES (Top 20) ===';
DECLARE @ErrorLog TABLE (LogDate DATETIME, ProcessInfo NVARCHAR(50), Text NVARCHAR(4000));
INSERT INTO @ErrorLog EXEC xp_readerrorlog 0, 1;
SELECT TOP 20 * FROM @ErrorLog ORDER BY LogDate DESC;

PRINT '\nDashboard complete.';