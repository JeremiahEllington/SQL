/*
============================================================
Deadlock Tracking Setup
============================================================
Description: Creates an Extended Events session to capture deadlock graphs.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

-- Check if the Extended Events session already exists
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'Track_Deadlocks')
BEGIN
    PRINT 'Dropping existing Extended Events session Track_Deadlocks...';
    -- Drop the session to ensure we start fresh
    DROP EVENT SESSION Track_Deadlocks ON SERVER;
END
GO

-- Create a new Extended Events session to capture deadlock events
CREATE EVENT SESSION Track_Deadlocks ON SERVER
ADD EVENT sqlserver.xml_deadlock_report  -- Capture full deadlock graphs in XML format
ADD TARGET package0.event_file (         -- Save captured data to an event file
    SET filename = N'deadlocks',         -- Base filename for the event files
        max_file_size = (5)              -- Roll over files after reaching 5 MB
)
-- Configure session options
WITH (
    MAX_DISPATCH_LATENCY = 5 SECONDS,    -- Flush events to file quickly (low latency)
    STARTUP_STATE = ON                   -- Ensure session auto-starts when SQL Server starts
);
GO

-- Start the new session immediately
ALTER EVENT SESSION Track_Deadlocks ON SERVER STATE = START;
GO

-- Output helper messages for the DBA
PRINT 'Deadlock tracking session created and started.';
PRINT 'Use the following to read deadlock reports:';
PRINT '  SELECT CAST(event_data AS XML)';
PRINT '  FROM sys.fn_xe_file_target_read_file(''deadlocks*.xel'', NULL, NULL, NULL);';
