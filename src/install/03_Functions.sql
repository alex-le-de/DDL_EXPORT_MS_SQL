/*
    03_Functions.sql
    Hilfsfunktionen fuer das Scripting.
*/
USE [$(AdminDb)];
GO

/* Datentyp im DDL-Format, z. B. [nvarchar](50), [decimal](18,2), [dbo].[MeinTyp] */
CREATE OR ALTER FUNCTION ddl.fn_DataType
(
    @TypeName          sysname,
    @TypeSchemaName    sysname,
    @IsUserDefinedType bit,
    @MaxLength         smallint,
    @Precision         tinyint,
    @Scale             tinyint
)
RETURNS nvarchar(300)
WITH SCHEMABINDING
AS
BEGIN
    IF @IsUserDefinedType = 1
        RETURN QUOTENAME(@TypeSchemaName) + N'.' + QUOTENAME(@TypeName);

    RETURN QUOTENAME(@TypeName) +
        CASE
            WHEN @TypeName IN (N'varchar', N'char', N'varbinary', N'binary')
                THEN N'(' + CASE WHEN @MaxLength = -1 THEN N'max' ELSE CAST(@MaxLength AS nvarchar(10)) END + N')'
            WHEN @TypeName IN (N'nvarchar', N'nchar')
                THEN N'(' + CASE WHEN @MaxLength = -1 THEN N'max' ELSE CAST(@MaxLength / 2 AS nvarchar(10)) END + N')'
            WHEN @TypeName IN (N'decimal', N'numeric')
                THEN N'(' + CAST(@Precision AS nvarchar(3)) + N',' + CAST(@Scale AS nvarchar(3)) + N')'
            WHEN @TypeName IN (N'datetime2', N'time', N'datetimeoffset')
                THEN N'(' + CAST(@Scale AS nvarchar(3)) + N')'
            WHEN @TypeName = N'float' AND @Precision <> 53
                THEN N'(' + CAST(@Precision AS nvarchar(3)) + N')'
            ELSE N''
        END;
END;
GO

/* Zweiteiliger Name [schema].[objekt] */
CREATE OR ALTER FUNCTION ddl.fn_QName (@SchemaName sysname, @ObjectName sysname)
RETURNS nvarchar(300)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN @SchemaName IS NULL THEN N'' ELSE QUOTENAME(@SchemaName) + N'.' END + QUOTENAME(@ObjectName);
END;
GO

/* Dateiname: im Dateisystem ungueltige Zeichen durch '_' ersetzen */
CREATE OR ALTER FUNCTION ddl.fn_FileName (@Name nvarchar(400))
RETURNS nvarchar(400)
WITH SCHEMABINDING
AS
BEGIN
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           @Name, N'\', N'_'), N'/', N'_'), N':', N'_'), N'*', N'_'), N'?', N'_'),
           N'"', N'_'), N'<', N'_'), N'>', N'_'), N'|', N'_');
END;
GO

/* N'...'-Literal (Hochkommas verdoppelt). NULL bleibt NULL (fuer optionale Parameter per ISNULL weglassen). */
CREATE OR ALTER FUNCTION ddl.fn_Literal (@Value nvarchar(max))
RETURNS nvarchar(max)
WITH SCHEMABINDING
AS
BEGIN
    IF @Value IS NULL RETURN NULL;
    RETURN N'N''' + REPLACE(@Value, N'''', N'''''') + N'''';
END;
GO

/* Kopfzeilen jeder exportierten Datei (bewusst ohne Zeitstempel -> stabiler Git-Diff) */
CREATE OR ALTER FUNCTION ddl.fn_Header (@ObjectType nvarchar(50), @Name nvarchar(400))
RETURNS nvarchar(1000)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @nl nchar(2) = NCHAR(13) + NCHAR(10);
    RETURN N'-- Objekt: ' + @Name + @nl
         + N'-- Typ:    ' + @ObjectType + @nl
         + N'-- Erzeugt durch DDL_EXPORT_MS_SQL (ohne Zeitstempel, deterministisch).' + @nl + @nl;
END;
GO

/*
    Exportziele der aktiven Datenbanken: <Ordner>/<Umgebung>/
    Ordner = FolderName oder DatabaseName, Umgebung = Environment der DB oder Standard.
*/
CREATE OR ALTER FUNCTION ddl.fn_ExportTarget (@DefaultEnvironment varchar(20))
RETURNS TABLE
AS
RETURN
    SELECT d.DatabaseName,
           Environment = ISNULL(NULLIF(d.Environment, ''), @DefaultEnvironment),
           BasePath    = ddl.fn_FileName(ISNULL(NULLIF(d.FolderName, N''), d.DatabaseName)) + N'/'
                       + ddl.fn_FileName(ISNULL(NULLIF(d.Environment, ''), @DefaultEnvironment)) + N'/'
    FROM ddl.ExportDatabase d
    WHERE d.IsActive = 1;
GO

/* Kommagetrennte Liste -> Tabelle mit Reihenfolge (getrimmt, ohne Leereintraege, ohne [ ]) */
CREATE OR ALTER FUNCTION ddl.fn_SplitList (@List nvarchar(4000))
RETURNS TABLE
AS
RETURN
    SELECT Ordinal = CAST([key] AS int) + 1,
           Item    = LTRIM(RTRIM(REPLACE(REPLACE(value, N'[', N''), N']', N'')))
    FROM OPENJSON(N'["' + REPLACE(STRING_ESCAPE(ISNULL(@List, N''), 'json'), N',', N'","') + N'"]')
    WHERE LTRIM(RTRIM(value)) <> N'';
GO

/* Fuehrende/abschliessende Leerzeichen, Tabs und Zeilenumbrueche entfernen */
CREATE OR ALTER FUNCTION ddl.fn_TrimWs (@Value nvarchar(max))
RETURNS nvarchar(max)
WITH SCHEMABINDING
AS
BEGIN
    RETURN TRIM(NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) FROM @Value);
END;
GO

/*
    N'...'-Literal fuer mehrzeiligen Text (z. B. Job-Step-Kommandos).
    Enthaelt der Text eine Zeile, die nur aus GO besteht, wuerde ein mehrzeiliges
    Literal das Batch-Trennzeichen ausloesen. Dann werden Zeilenumbrueche als
    NCHAR(13)/NCHAR(10) ausgeschrieben und das Literal bleibt einzeilig.
*/
CREATE OR ALTER FUNCTION ddl.fn_LiteralSafe (@Value nvarchar(max))
RETURNS nvarchar(max)
WITH SCHEMABINDING
AS
BEGIN
    IF @Value IS NULL RETURN N'NULL';
    DECLARE @lf nchar(1) = NCHAR(10);
    DECLARE @probe nvarchar(max) =
        @lf + REPLACE(REPLACE(REPLACE(@Value, NCHAR(13) + NCHAR(10), @lf), NCHAR(13), @lf), NCHAR(9), N' ') + @lf;
    IF @probe NOT LIKE N'%' + @lf + N'GO' + @lf + N'%'
       AND @probe NOT LIKE N'%' + @lf + N'GO %'
       AND @probe NOT LIKE N'%' + @lf + N' GO%'
        RETURN N'N''' + REPLACE(@Value, N'''', N'''''') + N'''';
    RETURN N'N''' + REPLACE(REPLACE(REPLACE(REPLACE(@Value, N'''', N''''''),
                    NCHAR(13) + NCHAR(10), N''' + NCHAR(13) + NCHAR(10) + N'''),
                    NCHAR(13), N''' + NCHAR(13) + N'''),
                    NCHAR(10), N''' + NCHAR(10) + N''') + N'''';
END;
GO
