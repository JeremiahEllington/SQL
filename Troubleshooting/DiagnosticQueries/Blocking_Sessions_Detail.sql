/*
============================================================
Blocking Sessions Detail
============================================================
Description: Identifies blocking chains with full statement text and wait details.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

-- Disable extra "rows affected" messages for cleaner output
SET NOCOUNT ON;

;WITH Blocking AS (
    SELECT 
        r.session_id AS BlockedSessionID,        -- The session being blocked
        r.blocking_session_id AS BlockingSessionID,  -- The session causing the block
        r.wait_type,                             -- Type of wait (e.g., LCK_M_S)
        r.wait_time,                             -- Duration of the wait (ms)
        r.wait_resource,                         -- Resource being waited on (table, page, etc.)
        DB_NAME(r.database_id) AS DatabaseName,  -- Database context of the query
        r.cpu_time,                              -- CPU time used by the session
        r.logical_reads,                         -- Logical reads performed by the query
        r.total_elapsed_time,                    -- Total execution time (ms)
        s.login_name,                            -- Login name of the session
        s.host_name,                             -- Host machine where the session originated
        s.program_name,                          -- Application/program initiating the query
        -- Extract the exact SQL statement being executed, not the whole batch
        SUBSTRING(t.text, 
            (r.statement_start_offset/2)+1,
            ((CASE r.statement_end_offset 
                 WHEN -1 THEN DATALENGTH(t.text) 
                 ELSE r.statement_end_offset END - r.statement_start_offset)/2)+1
        ) AS RunningStatement
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions s 
        ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.blocking_session_id <> 0   -- Only sessions that are currently blocked
), Chain AS (
    -- Identify the root blockers (sessions blocking others but not blocked themselves)
    SELECT *, 1 AS Level
    FROM Blocking
    WHERE BlockingSessionID NOT IN (SELECT BlockedSessionID FROM Blocking)

    UNION ALL

    -- Recursively walk down the blocking chain, building hierarchy levels
    SELECT b.*, c.Level + 1
    FROM Blocking b
    JOIN Chain c ON b.BlockingSessionID = c.BlockedSessionID
)
-- Final output of the blocking hierarchy
SELECT *
FROM Chain
ORDER BY Level, BlockingSessionID;

-- Guidance for troubleshooting after reviewing output
PRINT '\nRecommendations:';
PRINT '  - Identify top-level blockers (appear as BlockingSessionID but not BlockedSessionID)';
PRINT '  - Investigate queries holding locks for long periods';
PRINT '  - Consider using appropriate isolation levels or query tuning';
