-- Creates the patientping database and the login pp_app.
-- Run once as sa, after loading .env (set -a; source .env; set +a):
-- sqlcmd -S localhost -U sa -C -b -i migrations/000_bootstrap.sql
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'patientping')
    CREATE DATABASE patientping;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'pp_app')
    CREATE LOGIN pp_app WITH PASSWORD = N'$(PP_DB_PASSWORD)';
GO

USE patientping;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'pp_app')
    CREATE USER pp_app FOR LOGIN pp_app;
GO

ALTER ROLE db_datareader ADD MEMBER pp_app;
ALTER ROLE db_datawriter ADD MEMBER pp_app;
GO
