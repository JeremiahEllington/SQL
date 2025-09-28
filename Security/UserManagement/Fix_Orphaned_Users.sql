/*
============================================================
Fix Orphaned Users Script
============================================================
Description: Maps database users to corresponding server logins or creates missing logins.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

DECLARE @AutoCreateMissingLogins BIT = 0; -- Set to 1 to auto-create missing SQL logins
DECLARE @DefaultPassword NVARCHAR(100) = 'TempP@ssw0rd!'; -- Used if auto-creating SQL logins

PRINT 'Analyzing orphaned users...';

DECLARE @OrphanedUsers TABLE (
    UserName SYSNAME,
    UserSID VARBINARY(85)
);

INSERT INTO @OrphanedUsers (UserName, UserSID)
SELECT 
    dp.name,
    dp.sid
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type IN ('S','U','G')
  AND dp.authentication_type <> 2 -- Skip contained
  AND dp.sid IS NOT NULL
  AND sp.sid IS NULL
  AND dp.name NOT IN ('dbo');

IF NOT EXISTS (SELECT 1 FROM @OrphanedUsers)
BEGIN
    PRINT 'No orphaned users found.';
    RETURN;
END

SELECT * FROM @OrphanedUsers;

DECLARE @UserName SYSNAME, @UserSID VARBINARY(85);
DECLARE cur CURSOR FOR SELECT UserName, UserSID FROM @OrphanedUsers;
OPEN cur;
FETCH NEXT FROM cur INTO @UserName, @UserSID;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Processing orphaned user: ' + @UserName;
    
    -- Try to find a matching login by name
    IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @UserName)
    BEGIN
        DECLARE @FixCmd NVARCHAR(400) = 'ALTER USER [' + @UserName + '] WITH LOGIN = [' + @UserName + ']';
        BEGIN TRY
            EXEC (@FixCmd);
            PRINT 'Mapped user to existing login: ' + @UserName;
        END TRY
        BEGIN CATCH
            PRINT 'Error mapping user ' + @UserName + ': ' + ERROR_MESSAGE();
        END CATCH
    END
    ELSE IF @AutoCreateMissingLogins = 1
    BEGIN
        BEGIN TRY
            DECLARE @CreateLoginCmd NVARCHAR(500) = 'CREATE LOGIN [' + @UserName + '] WITH PASSWORD = ''' + @DefaultPassword + ''', CHECK_POLICY = ON';
            EXEC (@CreateLoginCmd);
            PRINT 'Created SQL login: ' + @UserName;
            
            DECLARE @MapCmd NVARCHAR(400) = 'ALTER USER [' + @UserName + '] WITH LOGIN = [' + @UserName + ']';
            EXEC (@MapCmd);
            PRINT 'Mapped user to newly created login: ' + @UserName;
        END TRY
        BEGIN CATCH
            PRINT 'Error creating/mapping login for ' + @UserName + ': ' + ERROR_MESSAGE();
        END CATCH
    END
    ELSE
        PRINT 'No matching login and AutoCreate disabled for user: ' + @UserName;
    
    FETCH NEXT FROM cur INTO @UserName, @UserSID;
END

CLOSE cur;
DEALLOCATE cur;

PRINT 'Orphaned user processing complete.';