/*
============================================================
Database Permissions Audit
============================================================
Description: Lists database principals, roles, and explicit permissions.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

SET NOCOUNT ON;

PRINT '=== Database Principals (Users/Roles) ===';
SELECT 
    principal_id,
    name AS PrincipalName,
    type_desc AS PrincipalType,
    authentication_type_desc,
    create_date,
    default_schema_name
FROM sys.database_principals
WHERE type NOT IN ('A','G','R','X') -- Filter out system
ORDER BY name;

PRINT '\n=== Role Memberships ===';
SELECT 
    r.name AS RoleName,
    m.name AS MemberName
FROM sys.database_role_members drm
JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON drm.member_principal_id = m.principal_id
ORDER BY r.name, m.name;

PRINT '\n=== Explicit Object Permissions ===';
SELECT 
    pr.name AS PrincipalName,
    pr.type_desc AS PrincipalType,
    perm.class_desc,
    OBJECT_SCHEMA_NAME(perm.major_id) AS SchemaName,
    OBJECT_NAME(perm.major_id) AS ObjectName,
    perm.permission_name,
    perm.state_desc AS PermissionState
FROM sys.database_permissions perm
JOIN sys.database_principals pr ON perm.grantee_principal_id = pr.principal_id
WHERE pr.type NOT IN ('A','G','R','X')
ORDER BY PrincipalName, ObjectName, permission_name;

PRINT '\n=== Orphaned Users (No Matching Login) ===';
SELECT 
    dp.name AS OrphanedUser
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type IN ('S','U','G')
  AND dp.sid IS NOT NULL
  AND sp.sid IS NULL;

PRINT '\n=== Recommendations ===';
PRINT '  - Review users with excessive explicit permissions';
PRINT '  - Prefer role-based access over direct grants';
PRINT '  - Fix orphaned users if application access issues arise';