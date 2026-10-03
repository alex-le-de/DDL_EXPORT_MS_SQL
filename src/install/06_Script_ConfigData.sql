/*
    06_Script_ConfigData.sql
    ddl.usp_Script_ConfigData
        Exportiert die Inhalte der in ddl.ExportConfigTable eingetragenen
        Konfigurationstabellen einer Fach-DB als deterministische Skripte
        (DELETE + INSERT, sortiert nach Primaerschluessel bzw. OrderByColumns).
        Ergebnis -> Temp-Tabelle #Script des Aufrufers.

    Werte-Formatierung (unabhaengig von Sprache/Regionaleinstellungen):
      Zahlen         CAST / CONVERT(..., 2|3) (money, float mit Rundtrip-Genauigkeit)
      Datum/Zeit     ISO 8601 (Style 23/126)
      Text           N'...' einzeilig; CR/LF als NCHAR(13)/NCHAR(10)
      Binaer/CLR     0x... (hierarchyid, geometry, geography ueber varbinary)
    Nicht exportiert: berechnete Spalten, rowversion, GENERATED ALWAYS-Spalten.
*/
USE [$(AdminDb)];
GO

CREATE OR ALTER PROCEDURE ddl.usp_Script_ConfigData
    @RunId        int,
    @DatabaseName sysname,
    @FolderName   nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl      nchar(2)      = NCHAR(13) + NCHAR(10);
    DECLARE @sepVal  nvarchar(20)  = N' + N'', '' + ';   -- Trenner der Wert-Ausdruecke
    DECLARE @base    nvarchar(200) = N'Databases/' + ddl.fn_FileName(@FolderName) + N'/ConfigData/';
    DECLARE @exec    nvarchar(400) = QUOTENAME(@DatabaseName) + N'.sys.sp_executesql';
    DECLARE @maxRows bigint        = TRY_CAST((SELECT SettingValue FROM ddl.ExportSetting WHERE SettingKey = 'ConfigDataMaxRows') AS bigint);
    IF @maxRows IS NULL SET @maxRows = 10000;

    /* Ausdrucksvorlagen; ~ steht fuer ein Hochkomma, {c} fuer die Spalte */
    DECLARE @tplText nvarchar(max) = REPLACE(
        N'ISNULL(N~N~~~ + REPLACE(REPLACE(REPLACE(REPLACE({v}, N~~~~, N~~~~~~), NCHAR(13) + NCHAR(10), N~~~ + NCHAR(13) + NCHAR(10) + N~~~), NCHAR(13), N~~~ + NCHAR(13) + N~~~), NCHAR(10), N~~~ + NCHAR(10) + N~~~) + N~~~~, N~NULL~)',
        N'~', N'''');
    DECLARE @tplQuoted nvarchar(max) = REPLACE(N'ISNULL(N~~~~ + {v} + N~~~~, N~NULL~)', N'~', N'''');
    DECLARE @tplPlain  nvarchar(max) = REPLACE(N'ISNULL({v}, N~NULL~)', N'~', N'''');

    DECLARE @SchemaName sysname, @TableName sysname, @OrderBy nvarchar(1000),
            @Exclude nvarchar(1000), @Mask nvarchar(1000), @ObjectId int;

    DECLARE ct CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName, TableName, OrderByColumns, ExcludeColumns, MaskColumns
        FROM ddl.ExportConfigTable
        WHERE DatabaseName = @DatabaseName AND IsActive = 1
        ORDER BY SchemaName, TableName;
    OPEN ct;
    FETCH NEXT FROM ct INTO @SchemaName, @TableName, @OrderBy, @Exclude, @Mask;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @qname nvarchar(300) = ddl.fn_QName(@SchemaName, @TableName);
        SET @ObjectId = (SELECT ObjectId FROM cat.[Object]
                         WHERE DatabaseName = @DatabaseName AND ObjectType = 'U'
                           AND SchemaName = @SchemaName AND ObjectName = @TableName);

        IF @ObjectId IS NULL
        BEGIN
            DECLARE @msgNf nvarchar(4000) = N'Konfig-Tabelle ' + @qname + N' nicht gefunden - uebersprungen.';
            EXEC ddl.usp_Log @RunId, 'WARN', @msgNf, @DatabaseName;
            GOTO NextTable;
        END;

        /* Spalten und Wert-Ausdruecke */
        DECLARE @cols TABLE (ColumnId int PRIMARY KEY, ColumnName sysname, Expr nvarchar(max), IsIdentity bit, Orderable bit);
        DELETE FROM @cols;

        INSERT INTO @cols (ColumnId, ColumnName, Expr, IsIdentity, Orderable)
        SELECT c.ColumnId, c.ColumnName,
               CASE
                   WHEN m.Item IS NOT NULL THEN
                        CASE WHEN c.SystemTypeName IN (N'char', N'varchar', N'nchar', N'nvarchar', N'text', N'ntext', N'sysname')
                             THEN N'N''N''''***''''''' ELSE N'N''NULL''' END
                   WHEN c.SystemTypeName IN (N'bit', N'tinyint', N'smallint', N'int', N'bigint', N'decimal', N'numeric')
                        THEN REPLACE(@tplPlain,  N'{v}', N'CAST(' + QUOTENAME(c.ColumnName) + N' AS nvarchar(100))')
                   WHEN c.SystemTypeName IN (N'money', N'smallmoney')
                        THEN REPLACE(@tplPlain,  N'{v}', N'CONVERT(nvarchar(100), ' + QUOTENAME(c.ColumnName) + N', 2)')
                   WHEN c.SystemTypeName IN (N'float', N'real')
                        THEN REPLACE(@tplPlain,  N'{v}', N'CONVERT(nvarchar(100), ' + QUOTENAME(c.ColumnName) + N', 3)')
                   WHEN c.SystemTypeName = N'date'
                        THEN REPLACE(@tplQuoted, N'{v}', N'CONVERT(nvarchar(10), ' + QUOTENAME(c.ColumnName) + N', 23)')
                   WHEN c.SystemTypeName IN (N'datetime', N'smalldatetime', N'datetime2', N'datetimeoffset')
                        THEN REPLACE(@tplQuoted, N'{v}', N'CONVERT(nvarchar(40), ' + QUOTENAME(c.ColumnName) + N', 126)')
                   WHEN c.SystemTypeName = N'time'
                        THEN REPLACE(@tplQuoted, N'{v}', N'CONVERT(nvarchar(20), ' + QUOTENAME(c.ColumnName) + N')')
                   WHEN c.SystemTypeName = N'uniqueidentifier'
                        THEN REPLACE(@tplQuoted, N'{v}', N'CONVERT(nvarchar(36), ' + QUOTENAME(c.ColumnName) + N')')
                   WHEN c.SystemTypeName IN (N'binary', N'varbinary', N'image', N'hierarchyid', N'geometry', N'geography')
                        THEN REPLACE(@tplPlain,  N'{v}', N'CONVERT(nvarchar(max), CAST(' + QUOTENAME(c.ColumnName) + N' AS varbinary(max)), 1)')
                   WHEN c.SystemTypeName = N'sql_variant'
                        THEN REPLACE(@tplText,   N'{v}', N'CONVERT(nvarchar(4000), ' + QUOTENAME(c.ColumnName) + N')')
                   ELSE      REPLACE(@tplText,   N'{v}', N'CAST(' + QUOTENAME(c.ColumnName) + N' AS nvarchar(max))')
               END,
               c.IsIdentity,
               CASE WHEN c.SystemTypeName IN (N'text', N'ntext', N'image', N'xml', N'geometry', N'geography') THEN 0 ELSE 1 END
        FROM cat.[Column] c
        LEFT JOIN ddl.fn_SplitList(@Exclude) x ON x.Item = c.ColumnName
        LEFT JOIN ddl.fn_SplitList(@Mask)    m ON m.Item = c.ColumnName
        WHERE c.DatabaseName = @DatabaseName AND c.ObjectId = @ObjectId
          AND c.IsComputed = 0
          AND c.GeneratedAlwaysType = 0
          AND c.SystemTypeName NOT IN (N'timestamp', N'rowversion')
          AND x.Item IS NULL;

        /* Sortierung: OrderByColumns > Primaerschluessel > alle sortierbaren Spalten */
        DECLARE @order nvarchar(max) = NULL;
        IF @OrderBy IS NOT NULL
            SELECT @order = STRING_AGG(QUOTENAME(Item), N', ') WITHIN GROUP (ORDER BY Ordinal)
            FROM ddl.fn_SplitList(@OrderBy);
        IF @order IS NULL
            SELECT @order = STRING_AGG(QUOTENAME(ic.ColumnName) + CASE WHEN ic.IsDescending = 1 THEN N' DESC' ELSE N'' END, N', ')
                            WITHIN GROUP (ORDER BY ic.KeyOrdinal)
            FROM cat.[Index] i
            JOIN cat.IndexColumn ic ON ic.DatabaseName = i.DatabaseName AND ic.ObjectId = i.ObjectId AND ic.IndexId = i.IndexId
            WHERE i.DatabaseName = @DatabaseName AND i.ObjectId = @ObjectId AND i.IsPrimaryKey = 1 AND ic.KeyOrdinal > 0;
        IF @order IS NULL
        BEGIN
            SELECT @order = STRING_AGG(QUOTENAME(ColumnName), N', ') WITHIN GROUP (ORDER BY ColumnId)
            FROM @cols WHERE Orderable = 1;
            DECLARE @msgPk nvarchar(4000) = N'Konfig-Tabelle ' + @qname + N' hat keinen Primaerschluessel - Sortierung ueber alle Spalten.';
            EXEC ddl.usp_Log @RunId, 'WARN', @msgPk, @DatabaseName;
        END;

        DECLARE @colList nvarchar(max), @valExpr nvarchar(max), @hasIdentity bit;
        SELECT @colList     = STRING_AGG(CAST(QUOTENAME(ColumnName) AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY ColumnId),
               @valExpr     = STRING_AGG(CAST(Expr AS nvarchar(max)), @sepVal) WITHIN GROUP (ORDER BY ColumnId),
               @hasIdentity = MAX(CAST(IsIdentity AS int))
        FROM @cols;

        /* Zeilenzahl pruefen */
        DECLARE @rowCount bigint = 0;
        DECLARE @cntSql nvarchar(max) = N'SELECT @n = COUNT_BIG(*) FROM ' + @qname + N';';
        EXEC @exec @cntSql, N'@n bigint OUTPUT', @n = @rowCount OUTPUT;

        DECLARE @header nvarchar(max) =
            ddl.fn_Header(N'Konfigurationstabelle (Daten)', @qname)
            + N'-- Sortierung: ' + ISNULL(@order, N'-') + @nl
            + ISNULL(N'-- Ausgeschlossene Spalten: ' + NULLIF(@Exclude, N'') + @nl, N'')
            + ISNULL(N'-- Maskierte Spalten: ' + NULLIF(@Mask, N'') + @nl, N'')
            + N'-- Zeilen: ' + CAST(@rowCount AS nvarchar(20)) + @nl + @nl;

        DECLARE @content nvarchar(max);
        IF @rowCount > @maxRows
        BEGIN
            SET @content = @header + N'-- Export uebersprungen: mehr als ' + CAST(@maxRows AS nvarchar(20))
                         + N' Zeilen (Einstellung ConfigDataMaxRows).' + @nl;
            DECLARE @msgMax nvarchar(4000) = N'Konfig-Tabelle ' + @qname + N' hat ' + CAST(@rowCount AS nvarchar(20))
                                           + N' Zeilen (> ConfigDataMaxRows) - Daten nicht exportiert.';
            EXEC ddl.usp_Log @RunId, 'WARN', @msgMax, @DatabaseName;
        END
        ELSE
        BEGIN
            CREATE TABLE #Rows (RowNo bigint NOT NULL PRIMARY KEY, Line nvarchar(max) NOT NULL);
            DECLARE @dataSql nvarchar(max) =
                N'SELECT ROW_NUMBER() OVER (ORDER BY ' + @order + N'), '
                + N'N''INSERT INTO ' + REPLACE(@qname, N'''', N'''''') + N' (' + REPLACE(@colList, N'''', N'''''') + N') VALUES ('' + '
                + @valExpr + N' + N'');'' FROM ' + @qname + N';';
            INSERT INTO #Rows (RowNo, Line)
            EXEC @exec @dataSql;

            SET @content = @header
                + N'SET NOCOUNT ON;' + @nl
                + N'DELETE FROM ' + @qname + N';' + @nl
                + CASE WHEN @hasIdentity = 1 THEN N'SET IDENTITY_INSERT ' + @qname + N' ON;' + @nl ELSE N'' END
                + ISNULL((SELECT STRING_AGG(Line, @nl) WITHIN GROUP (ORDER BY RowNo) FROM #Rows) + @nl, N'')
                + CASE WHEN @hasIdentity = 1 THEN N'SET IDENTITY_INSERT ' + @qname + N' OFF;' + @nl ELSE N'' END
                + N'GO' + @nl;
            DROP TABLE #Rows;
        END;

        INSERT INTO #Script (RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content)
        VALUES (@base + ddl.fn_FileName(@SchemaName + N'.' + @TableName) + N'.sql',
                @DatabaseName, 'ConfigData', @SchemaName, @TableName, @content);

        NextTable:
        FETCH NEXT FROM ct INTO @SchemaName, @TableName, @OrderBy, @Exclude, @Mask;
    END;
    CLOSE ct;
    DEALLOCATE ct;
END;
GO
