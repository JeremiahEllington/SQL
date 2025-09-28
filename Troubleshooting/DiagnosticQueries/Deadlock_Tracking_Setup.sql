/*
============================================================
Deadlock Tracking Setup
============================================================
Description: Creates an Extended Events session to capture deadlock graphs.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'Track_Deadlocks')
BEGIN
    PRINT 'Dropping existing Extended Events session Track_Deadlocks...';
    DROP EVENT SESSION Track_Deadlocks ON SERVER;
END
GO

CREATE EVENT SESSION Track_Deadlocks ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file (SET filename = N'deadlocks', max_file_size=(5))
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS, STARTUP_STATE = ON);
GO

ALTER EVENT SESSION Track_Deadlocks ON SERVER STATE = START;
GO

PRINT 'Deadlock tracking session created and started.';
PRINT 'Use the following to read deadlock reports:';
PRINT '  SELECT CAST(event_data AS XML) FROM sys.fn_xe_file_target_read_file(''deadlocks*.xel'', NULL, NULL, NULL);';