/*
============================================================
Wait Stats Analysis
============================================================
Description: Provides insights into top SQL Server waits excluding benign waits.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

;WITH Waits AS (
    SELECT 
        wait_type,
        wait_time_ms / 1000.0 AS Wait_S,
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS Resource_S,
        signal_wait_time_ms / 1000.0 AS Signal_S,
        waiting_tasks_count AS WaitCount,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS Percentage,
        ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS RowNum
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        'BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','BROKER_TASK_STOP','BROKER_TO_FLUSH','BROKER_TRANSMITTER',
        'CHECKPOINT_QUEUE','CHKPT','CLR_AUTO_EVENT','CLR_MANUAL_EVENT','CLR_SEMAPHORE','CXCONSUMER',
        'DBMIRROR_DBM_EVENT','DBMIRROR_EVENTS_QUEUE','DBMIRRORING_CMD','DISPATCHER_QUEUE_SEMAPHORE','EXECSYNC',
        'FSAGENT','FT_IFTS_SCHEDULER_IDLE_WAIT','FT_IFTSHC_MUTEX','HADR_CLUSAPI_CALL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        'HADR_LOGCAPTURE_WAIT','HADR_NOTIFICATION_DEQUEUE','HADR_TIMER_TASK','HADR_WORK_QUEUE','KSOURCE_WAKEUP',
        'LAZYWRITER_SLEEP','LOGMGR_QUEUE','MISCELLANEOUS','ONDEMAND_TASK_QUEUE','PWAIT_ALL_COMPONENTS_INITIALIZED',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','QDS_SHUTDOWN_QUEUE',
        'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK','SLEEP_BPOOL_FLUSH',
        'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED',
        'SLEEP_MSDBSTARTUP','SLEEP_SYSTEMTASK','SLEEP_TASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
        'SOS_WORK_DISPATCHER','SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH','SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        'SQLTRACE_WAIT_ENTRIES','UCS_SESSION_REGISTRATION','VDI_CLIENT_OTHER','WAIT_FOR_RESULTS',
        'WAITFOR','WAITFOR_TASKSHUTDOWN','WAIT_XTP_RECOVERY','WAIT_XTP_HOST_WAIT','XE_DISPATCHER_JOIN',
        'XE_DISPATCHER_WAIT','XE_TIMER_EVENT'
    )
)
SELECT TOP 20
    W1.wait_type,
    CAST(W1.Wait_S AS DECIMAL(12,2)) AS Wait_Sec,
    CAST(W1.Resource_S AS DECIMAL(12,2)) AS Resource_Sec,
    CAST(W1.Signal_S AS DECIMAL(12,2)) AS Signal_Sec,
    W1.WaitCount,
    CAST(W1.Percentage AS DECIMAL(5,2)) AS Percentage,
    CAST((W1.Wait_S / W1.WaitCount) AS DECIMAL(12,4)) AS AvgWait_Sec,
    CAST((W1.Resource_S / W1.WaitCount) AS DECIMAL(12,4)) AS AvgRes_Sec,
    CAST((W1.Signal_S / W1.WaitCount) AS DECIMAL(12,4)) AS AvgSig_Sec
FROM Waits W1
ORDER BY W1.Wait_S DESC;

PRINT '\nInterpretation Tips:';
PRINT '  PAGEIOLATCH_*  -> Disk I/O bottlenecks';
PRINT '  CXPACKET       -> Parallelism (review DOP, Cost Threshold)';
PRINT '  LCK_*          -> Lock contention';
PRINT '  SOS_SCHEDULER  -> CPU pressure';
PRINT '  WRITELOG       -> Transaction log bottleneck';
PRINT '  ASYNC_NETWORK  -> Network / client consumption delay';
