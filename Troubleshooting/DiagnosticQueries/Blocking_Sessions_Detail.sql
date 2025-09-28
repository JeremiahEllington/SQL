/*
============================================================
Blocking Sessions Detail
============================================================
Description: Identifies blocking chains with full statement text and wait details.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

;WITH Blocking AS (
    SELECT 
        r.session_id AS BlockedSessionID,
        r.blocking_session_id AS BlockingSessionID,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        DB_NAME(r.database_id) AS DatabaseName,
        r.cpu_time,
        r.logical_reads,
        r.total_elapsed_time,
        s.login_name,
        s.host_name,
        s.program_name,
        SUBSTRING(t.text, (r.statement_start_offset/2)+1,
            ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset)/2)+1) AS RunningStatement
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.blocking_session_id <> 0
), Chain AS (
    SELECT *, 1 AS Level
    FROM Blocking
    WHERE BlockingSessionID NOT IN (SELECT BlockedSessionID FROM Blocking)
    UNION ALL
    SELECT b.*, c.Level + 1
    FROM Blocking b
    JOIN Chain c ON b.BlockingSessionID = c.BlockedSessionID
)
SELECT *
FROM Chain
ORDER BY Level, BlockingSessionID;

PRINT '\nRecommendations:';
PRINT '  - Identify top-level blockers (appear as BlockingSessionID but not BlockedSessionID)';
PRINT '  - Investigate queries holding locks for long periods';
PRINT '  - Consider using appropriate isolation levels or query tuning';