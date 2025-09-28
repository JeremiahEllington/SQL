/*
============================================================
Top Resource Consuming Queries
============================================================
Description: Retrieves top queries by CPU, duration, logical reads, and executions.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

SELECT TOP 50
    DB_NAME(st.dbid) AS DatabaseName,
    qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
    qs.total_worker_time / qs.execution_count / 1000 AS AvgCPU_ms,
    qs.total_elapsed_time / qs.execution_count / 1000 AS AvgDuration_ms,
    qs.max_elapsed_time / 1000 AS MaxDuration_ms,
    qs.total_rows / NULLIF(qs.execution_count,0) AS AvgRows,
    qs.creation_time,
    qs.last_execution_time,
    SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
        ((CASE qs.statement_end_offset 
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset END - qs.statement_start_offset)/2) + 1) AS QueryText,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
OUTER APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qs.execution_count > 1
ORDER BY (qs.total_worker_time / qs.execution_count) DESC;

PRINT '\nRecommendations:';
PRINT '  Investigate queries with high AvgLogicalReads for indexing opportunities';
PRINT '  Long-running queries (high AvgDuration_ms) may need rewrites or statistics updates';
PRINT '  High CPU queries may benefit from index tuning or query refactoring';
