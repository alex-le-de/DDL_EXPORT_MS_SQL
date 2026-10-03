/*
    01_Database.sql
    Legt die Admin-Datenbank an (idempotent).
    SQLCMD-Variable: $(AdminDb)
*/
USE [master];
GO
IF DB_ID(N'$(AdminDb)') IS NULL
BEGIN
    DECLARE @sql nvarchar(max) = N'CREATE DATABASE ' + QUOTENAME(N'$(AdminDb)') + N';';
    EXEC (@sql);
    PRINT N'Datenbank $(AdminDb) angelegt.';
END
ELSE
    PRINT N'Datenbank $(AdminDb) existiert bereits.';
GO
ALTER DATABASE [$(AdminDb)] SET RECOVERY SIMPLE;
GO
USE [$(AdminDb)];
GO
IF SCHEMA_ID(N'ddl') IS NULL EXEC (N'CREATE SCHEMA [ddl] AUTHORIZATION [dbo];');
GO
IF SCHEMA_ID(N'cat') IS NULL EXEC (N'CREATE SCHEMA [cat] AUTHORIZATION [dbo];');
GO
