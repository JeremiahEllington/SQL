/*
============================================================
Create Login and Database User Script
============================================================
Description: Safely creates a SQL/Login and corresponding database user with role assignments.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

-- Parameters
DECLARE @LoginName SYSNAME = 'AppUserLogin'; -- Change
DECLARE @Password NVARCHAR(200) = 'Str0ngP@ssw0rd!'; -- Change (if SQL auth)
DECLARE @UseWindows BIT = 0; -- 1 = Windows login, 0 = SQL Login
DECLARE @DefaultDB SYSNAME = 'master';
DECLARE @DatabaseName SYSNAME = DB_NAME();
DECLARE @DbUserName SYSNAME = 'AppUser';
DECLARE @Roles TABLE (RoleName SYSNAME);

-- Add roles to assign (modify as needed)
INSERT INTO @Roles (RoleName) VALUES ('db_datareader'), ('db_datawriter');
-- Optionally: ('db_ddladmin'), ('db_executor') if custom, etc.

PRINT 'Creating login and user if not exists...';

-- 1. Create Login (Server level)
IF @UseWindows = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @LoginName)
    BEGIN
        DECLARE @CreateWinLogin NVARCHAR(MAX) = 'CREATE LOGIN [' + @LoginName + '] FROM WINDOWS WITH DEFAULT_DATABASE=[' + @DefaultDB + ']';
        EXEC (@CreateWinLogin);
        PRINT 'Windows login created: ' + @LoginName;
    END
    ELSE
        PRINT 'Windows login already exists: ' + @LoginName;
END
ELSE
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = @LoginName)
    BEGIN
        DECLARE @CreateSqlLogin NVARCHAR(MAX) = 'CREATE LOGIN [' + @LoginName + '] WITH PASSWORD = ''' + @Password + ''', CHECK_POLICY = ON, DEFAULT_DATABASE = [' + @DefaultDB + ']';
        EXEC (@CreateSqlLogin);
        PRINT 'SQL login created: ' + @LoginName;
    END
    ELSE
        PRINT 'SQL login already exists: ' + @LoginName;
END

-- 2. Create Database User
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @DbUserName)
BEGIN
    DECLARE @CreateUser NVARCHAR(MAX) = 'CREATE USER [' + @DbUserName + '] FOR LOGIN [' + @LoginName + ']';
    EXEC (@CreateUser);
    PRINT 'Database user created: ' + @DbUserName;
END
ELSE
    PRINT 'Database user already exists: ' + @DbUserName;

-- 3. Assign Roles
DECLARE @Role SYSNAME;
DECLARE role_cursor CURSOR FOR SELECT RoleName FROM @Roles;
OPEN role_cursor;
FETCH NEXT FROM role_cursor INTO @Role;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_role_members rm INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id INNER JOIN sys.database_principals u ON rm.member_principal_id = u.principal_id WHERE r.name = @Role AND u.name = @DbUserName)
    BEGIN
        DECLARE @AddRole NVARCHAR(400) = 'EXEC sp_addrolemember @rolename = N''' + @Role + ''', @membername = N''' + @DbUserName + '''';
        EXEC (@AddRole);
        PRINT 'Added user ' + @DbUserName + ' to role ' + @Role;
    END
    ELSE
        PRINT 'User already in role: ' + @Role;
    
    FETCH NEXT FROM role_cursor INTO @Role;
END
CLOSE role_cursor;
DEALLOCATE role_cursor;

PRINT 'Login and user provisioning complete.';