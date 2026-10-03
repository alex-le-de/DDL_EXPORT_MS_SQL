/*
    05_Script_Objects.sql
    ddl.usp_Script_Objects
        Erzeugt aus den Staging-Tabellen cat.* die DDL-Skripte einer Fach-DB und
        schreibt sie in die vom Aufrufer angelegte Temp-Tabelle #Script.

    Aufbau jeder Datei:  Kopf (ohne Zeitstempel) + Anweisungen, jeweils mit GO.
    Reihenfolge und Formatierung sind deterministisch (stabiler Git-Diff).
*/
USE [$(AdminDb)];
GO

CREATE OR ALTER PROCEDURE ddl.usp_Script_Objects
    @RunId        int,
    @DatabaseName sysname,
    @FolderName   nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl   nchar(2)      = NCHAR(13) + NCHAR(10);
    DECLARE @sepColumn nchar(3) = N',' + NCHAR(13) + NCHAR(10);   -- STRING_AGG verlangt Literal/Variable als Trenner
    DECLARE @base nvarchar(200) = N'Databases/' + ddl.fn_FileName(@FolderName) + N'/';

    /* Dateien und ihre Anweisungen */
    CREATE TABLE #File
    (
        RelativePath nvarchar(400) NOT NULL PRIMARY KEY,
        ObjectType   varchar(30)   NOT NULL,
        TypeLabel    nvarchar(50)  NOT NULL,
        SchemaName   sysname       NULL,
        ObjectName   nvarchar(256) NOT NULL,
        ObjectId     int           NULL
    );
    CREATE TABLE #Stmt
    (
        RelativePath nvarchar(400) NOT NULL,
        Section      int           NOT NULL,
        SortKey      nvarchar(400) NOT NULL,
        Stmt         nvarchar(max) NOT NULL
    );

    /* ------------------------------------------------------------------
       Bausteine: Spaltenzeilen und Tabellen-Constraints (Tabellen + Tabellentypen)
       ------------------------------------------------------------------ */
    CREATE TABLE #TabObj (ObjectId int NOT NULL PRIMARY KEY, IsTableType bit NOT NULL);
    INSERT INTO #TabObj (ObjectId, IsTableType)
    SELECT ObjectId, 0 FROM cat.[Object] WHERE DatabaseName = @DatabaseName AND ObjectType = 'U'
    UNION
    SELECT TableObjectId, 1 FROM cat.[Type] WHERE DatabaseName = @DatabaseName AND IsTableType = 1;

    CREATE TABLE #Def (ObjectId int NOT NULL, Sort1 int NOT NULL, Sort2 int NOT NULL, SortName sysname NOT NULL, Line nvarchar(max) NOT NULL);

    -- Spalten
    INSERT INTO #Def (ObjectId, Sort1, Sort2, SortName, Line)
    SELECT c.ObjectId, 1, c.ColumnId, N'',
           QUOTENAME(c.ColumnName) + N' ' +
           CASE WHEN c.IsComputed = 1 THEN
                N'AS ' + c.ComputedDefinition
                + CASE WHEN c.IsPersisted = 1 THEN N' PERSISTED' + CASE WHEN c.IsNullable = 0 THEN N' NOT NULL' ELSE N'' END ELSE N'' END
           ELSE
                ddl.fn_DataType(c.TypeName, c.TypeSchemaName, c.IsUserDefinedType, c.MaxLength, c.[Precision], c.Scale)
                + CASE WHEN c.IsSparse = 1 THEN N' SPARSE' ELSE N'' END
                + CASE c.GeneratedAlwaysType WHEN 1 THEN N' GENERATED ALWAYS AS ROW START'
                                             WHEN 2 THEN N' GENERATED ALWAYS AS ROW END' ELSE N'' END
                + CASE WHEN c.IsHidden = 1 THEN N' HIDDEN' ELSE N'' END
                + CASE WHEN c.IsIdentity = 1 THEN N' IDENTITY(' + c.SeedValue + N',' + c.IncrementValue + N')' ELSE N'' END
                + CASE WHEN c.IsRowGuidCol = 1 THEN N' ROWGUIDCOL' ELSE N'' END
                + CASE WHEN c.IsNullable = 1 THEN N' NULL' ELSE N' NOT NULL' END
                + CASE WHEN c.DefaultDefinition IS NULL THEN N''
                       ELSE CASE WHEN c.DefaultIsSystemNamed = 1 THEN N'' ELSE N' CONSTRAINT ' + QUOTENAME(c.DefaultName) END
                            + N' DEFAULT ' + c.DefaultDefinition END
           END
    FROM cat.[Column] c
    JOIN #TabObj t ON t.ObjectId = c.ObjectId
    WHERE c.DatabaseName = @DatabaseName;

    -- PERIOD FOR SYSTEM_TIME (system-versionierte Tabellen)
    INSERT INTO #Def (ObjectId, Sort1, Sort2, SortName, Line)
    SELECT o.ObjectId, 2, 0, N'',
           N'PERIOD FOR SYSTEM_TIME (' + QUOTENAME(cs.ColumnName) + N', ' + QUOTENAME(ce.ColumnName) + N')'
    FROM cat.[Object] o
    JOIN cat.[Column] cs ON cs.DatabaseName = o.DatabaseName AND cs.ObjectId = o.ObjectId AND cs.GeneratedAlwaysType = 1
    JOIN cat.[Column] ce ON ce.DatabaseName = o.DatabaseName AND ce.ObjectId = o.ObjectId AND ce.GeneratedAlwaysType = 2
    WHERE o.DatabaseName = @DatabaseName AND o.ObjectType = 'U' AND o.TemporalType = 2;

    -- Primaerschluessel und Unique-Constraints
    INSERT INTO #Def (ObjectId, Sort1, Sort2, SortName, Line)
    SELECT i.ObjectId, 3, CASE WHEN i.IsPrimaryKey = 1 THEN 0 ELSE 1 END, ISNULL(i.IndexName, N''),
           CASE WHEN ISNULL(i.IsSystemNamed, 0) = 1 THEN N'' ELSE N'CONSTRAINT ' + QUOTENAME(i.IndexName) + N' ' END
           + CASE WHEN i.IsPrimaryKey = 1 THEN N'PRIMARY KEY ' ELSE N'UNIQUE ' END
           + CASE WHEN i.IndexType = 1 THEN N'CLUSTERED' ELSE N'NONCLUSTERED' END
           + N' (' + k.Cols + N')'
           + CASE WHEN i.IgnoreDupKey = 1 THEN N' WITH (IGNORE_DUP_KEY = ON)' ELSE N'' END
    FROM cat.[Index] i
    JOIN #TabObj t ON t.ObjectId = i.ObjectId
    CROSS APPLY (SELECT Cols = STRING_AGG(QUOTENAME(ic.ColumnName) + CASE WHEN ic.IsDescending = 1 THEN N' DESC' ELSE N' ASC' END, N', ')
                                WITHIN GROUP (ORDER BY ic.KeyOrdinal)
                 FROM cat.IndexColumn ic
                 WHERE ic.DatabaseName = i.DatabaseName AND ic.ObjectId = i.ObjectId AND ic.IndexId = i.IndexId
                   AND ic.KeyOrdinal > 0) k
    WHERE i.DatabaseName = @DatabaseName AND (i.IsPrimaryKey = 1 OR i.IsUniqueConstraint = 1);

    -- Check-Constraints
    INSERT INTO #Def (ObjectId, Sort1, Sort2, SortName, Line)
    SELECT ck.ParentObjectId, 4, 0, ck.ConstraintName,
           CASE WHEN ck.IsSystemNamed = 1 THEN N'' ELSE N'CONSTRAINT ' + QUOTENAME(ck.ConstraintName) + N' ' END
           + N'CHECK ' + ck.Definition
    FROM cat.CheckConstraint ck
    JOIN #TabObj t ON t.ObjectId = ck.ParentObjectId
    WHERE ck.DatabaseName = @DatabaseName;

    CREATE TABLE #Body (ObjectId int NOT NULL PRIMARY KEY, Body nvarchar(max) NOT NULL);
    INSERT INTO #Body (ObjectId, Body)
    SELECT ObjectId,
           N'(' + @nl + STRING_AGG(CAST(N'    ' AS nvarchar(max)) + Line, @sepColumn)
                         WITHIN GROUP (ORDER BY Sort1, Sort2, SortName) + @nl + N')'
    FROM #Def
    GROUP BY ObjectId;

    /* ------------------------------------------------------------------
       Index-Anweisungen (Tabellen und indizierte Views), ohne PK/UQ
       ------------------------------------------------------------------ */
    CREATE TABLE #IdxStmt (ObjectId int NOT NULL, IndexName sysname NOT NULL, Stmt nvarchar(max) NOT NULL);
    INSERT INTO #IdxStmt (ObjectId, IndexName, Stmt)
    SELECT i.ObjectId, i.IndexName,
           CASE
               WHEN i.IndexType IN (1, 2) THEN
                    N'CREATE ' + CASE WHEN i.IsUnique = 1 THEN N'UNIQUE ' ELSE N'' END
                    + CASE WHEN i.IndexType = 1 THEN N'CLUSTERED' ELSE N'NONCLUSTERED' END
                    + N' INDEX ' + QUOTENAME(i.IndexName) + N' ON ' + ddl.fn_QName(o.SchemaName, o.ObjectName)
                    + N' (' + k.KeyCols + N')'
                    + ISNULL(N' INCLUDE (' + n.InclCols + N')', N'')
                    + ISNULL(N' WHERE ' + i.FilterDefinition, N'')
                    + CASE WHEN i.IgnoreDupKey = 1 THEN N' WITH (IGNORE_DUP_KEY = ON)' ELSE N'' END
               WHEN i.IndexType = 5 THEN
                    N'CREATE CLUSTERED COLUMNSTORE INDEX ' + QUOTENAME(i.IndexName) + N' ON ' + ddl.fn_QName(o.SchemaName, o.ObjectName)
               WHEN i.IndexType = 6 THEN
                    N'CREATE NONCLUSTERED COLUMNSTORE INDEX ' + QUOTENAME(i.IndexName) + N' ON ' + ddl.fn_QName(o.SchemaName, o.ObjectName)
                    + N' (' + a.AllCols + N')' + ISNULL(N' WHERE ' + i.FilterDefinition, N'')
               ELSE N'-- Index ' + QUOTENAME(i.IndexName) + N' (Indextyp ' + CAST(i.IndexType AS nvarchar(3)) + N') wird nicht exportiert.'
           END
    FROM cat.[Index] i
    JOIN cat.[Object] o ON o.DatabaseName = i.DatabaseName AND o.ObjectId = i.ObjectId AND o.ObjectType IN ('U', 'V')
    -- getrennte APPLYs: STRING_AGG mit unterschiedlicher Sortierung im selben SELECT ist nicht erlaubt
    CROSS APPLY (SELECT KeyCols  = STRING_AGG(QUOTENAME(ic.ColumnName) + CASE WHEN ic.IsDescending = 1 THEN N' DESC' ELSE N' ASC' END, N', ')
                                   WITHIN GROUP (ORDER BY ic.KeyOrdinal)
                 FROM cat.IndexColumn ic
                 WHERE ic.DatabaseName = i.DatabaseName AND ic.ObjectId = i.ObjectId AND ic.IndexId = i.IndexId
                   AND ic.KeyOrdinal > 0) k
    CROSS APPLY (SELECT InclCols = STRING_AGG(QUOTENAME(ic.ColumnName), N', ') WITHIN GROUP (ORDER BY ic.IndexColumnId)
                 FROM cat.IndexColumn ic
                 WHERE ic.DatabaseName = i.DatabaseName AND ic.ObjectId = i.ObjectId AND ic.IndexId = i.IndexId
                   AND ic.IsIncluded = 1 AND ic.KeyOrdinal = 0) n
    CROSS APPLY (SELECT AllCols  = STRING_AGG(QUOTENAME(ic.ColumnName), N', ') WITHIN GROUP (ORDER BY ic.IndexColumnId)
                 FROM cat.IndexColumn ic
                 WHERE ic.DatabaseName = i.DatabaseName AND ic.ObjectId = i.ObjectId AND ic.IndexId = i.IndexId) a
    WHERE i.DatabaseName = @DatabaseName
      AND i.IsPrimaryKey = 0 AND i.IsUniqueConstraint = 0;

    /* ------------------------------------------------------------------
       Extended Properties (Objekt- und Spaltenebene)
       ------------------------------------------------------------------ */
    CREATE TABLE #EpStmt (ObjectId int NOT NULL, SortKey nvarchar(400) NOT NULL, Stmt nvarchar(max) NOT NULL);
    INSERT INTO #EpStmt (ObjectId, SortKey, Stmt)
    SELECT ep.MajorId,
           RIGHT(N'000000' + CAST(ep.MinorId AS nvarchar(10)), 6) + N'|' + ep.PropertyName,
           N'EXEC sys.sp_addextendedproperty @name = ' + ddl.fn_Literal(ep.PropertyName)
           + N', @value = ' + ddl.fn_LiteralSafe(ep.PropertyValue)
           + CASE WHEN o.ObjectType = 'TR' THEN
                  N', @level0type = N''SCHEMA'', @level0name = ' + ddl.fn_Literal(p.SchemaName)
                  + N', @level1type = N''TABLE'', @level1name = ' + ddl.fn_Literal(p.ObjectName)
                  + N', @level2type = N''TRIGGER'', @level2name = ' + ddl.fn_Literal(o.ObjectName)
             ELSE
                  N', @level0type = N''SCHEMA'', @level0name = ' + ddl.fn_Literal(o.SchemaName)
                  + N', @level1type = N''' + CASE o.ObjectType WHEN 'U' THEN N'TABLE' WHEN 'V' THEN N'VIEW'
                                                               WHEN 'P' THEN N'PROCEDURE' ELSE N'FUNCTION' END + N''''
                  + N', @level1name = ' + ddl.fn_Literal(o.ObjectName)
                  + CASE WHEN ep.MinorId > 0 THEN N', @level2type = N''COLUMN'', @level2name = ' + ddl.fn_Literal(c.ColumnName) ELSE N'' END
             END + N';'
    FROM cat.ExtendedProperty ep
    JOIN cat.[Object] o      ON o.DatabaseName = ep.DatabaseName AND o.ObjectId = ep.MajorId
    LEFT JOIN cat.[Object] p ON p.DatabaseName = o.DatabaseName AND p.ObjectId = o.ParentObjectId
    LEFT JOIN cat.[Column] c ON c.DatabaseName = ep.DatabaseName AND c.ObjectId = ep.MajorId AND c.ColumnId = ep.MinorId
    WHERE ep.DatabaseName = @DatabaseName
      AND o.ObjectType IN ('U', 'V', 'P', 'FN', 'IF', 'TF', 'TR')
      AND (ep.MinorId = 0 OR c.ColumnId IS NOT NULL);

    /* ------------------------------------------------------------------
       Tabellen
       ------------------------------------------------------------------ */
    INSERT INTO #File (RelativePath, ObjectType, TypeLabel, SchemaName, ObjectName, ObjectId)
    SELECT @base + N'Tables/' + ddl.fn_FileName(o.SchemaName + N'.' + o.ObjectName) + N'.sql',
           'Table', N'Tabelle', o.SchemaName, o.ObjectName, o.ObjectId
    FROM cat.[Object] o
    WHERE o.DatabaseName = @DatabaseName AND o.ObjectType = 'U';

    INSERT INTO #Stmt (RelativePath, Section, SortKey, Stmt)
    SELECT f.RelativePath, 0, N'', N'SET ANSI_NULLS ' + CASE WHEN ISNULL(o.UsesAnsiNulls, 1) = 1 THEN N'ON' ELSE N'OFF' END
    FROM #File f JOIN cat.[Object] o ON o.DatabaseName = @DatabaseName AND o.ObjectId = f.ObjectId
    WHERE f.ObjectType = 'Table'
    UNION ALL
    SELECT f.RelativePath, 1, N'', N'SET QUOTED_IDENTIFIER ON'
    FROM #File f WHERE f.ObjectType = 'Table'
    UNION ALL
    SELECT f.RelativePath, 2, N'',
           N'CREATE TABLE ' + ddl.fn_QName(o.SchemaName, o.ObjectName) + @nl + b.Body
           + CASE WHEN o.TemporalType = 2 AND o.HistoryTableName IS NOT NULL
                  THEN @nl + N'WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = ' + ddl.fn_QName(o.HistorySchemaName, o.HistoryTableName) + N'))'
                  ELSE N'' END
    FROM #File f
    JOIN cat.[Object] o ON o.DatabaseName = @DatabaseName AND o.ObjectId = f.ObjectId
    JOIN #Body b        ON b.ObjectId = f.ObjectId
    WHERE f.ObjectType = 'Table'
    UNION ALL
    -- Indizes
    SELECT f.RelativePath, 3, x.IndexName, x.Stmt
    FROM #File f JOIN #IdxStmt x ON x.ObjectId = f.ObjectId
    WHERE f.ObjectType = 'Table'
    UNION ALL
    -- Fremdschluessel
    SELECT f.RelativePath, 4, fk.ForeignKeyName,
           N'ALTER TABLE ' + ddl.fn_QName(f.SchemaName, f.ObjectName)
           + CASE WHEN fk.IsNotTrusted = 1 THEN N' WITH NOCHECK' ELSE N' WITH CHECK' END
           + N' ADD ' + CASE WHEN fk.IsSystemNamed = 1 THEN N'' ELSE N'CONSTRAINT ' + QUOTENAME(fk.ForeignKeyName) + N' ' END
           + N'FOREIGN KEY (' + fc.ParentCols + N')' + @nl
           + N'    REFERENCES ' + ddl.fn_QName(fk.RefSchemaName, fk.RefTableName) + N' (' + fc.RefCols + N')'
           + CASE fk.DeleteAction WHEN N'CASCADE' THEN N' ON DELETE CASCADE' WHEN N'SET_NULL' THEN N' ON DELETE SET NULL'
                                  WHEN N'SET_DEFAULT' THEN N' ON DELETE SET DEFAULT' ELSE N'' END
           + CASE fk.UpdateAction WHEN N'CASCADE' THEN N' ON UPDATE CASCADE' WHEN N'SET_NULL' THEN N' ON UPDATE SET NULL'
                                  WHEN N'SET_DEFAULT' THEN N' ON UPDATE SET DEFAULT' ELSE N'' END
           + CASE WHEN fk.IsDisabled = 1 AND fk.IsSystemNamed = 0
                  THEN N';' + @nl + N'ALTER TABLE ' + ddl.fn_QName(f.SchemaName, f.ObjectName) + N' NOCHECK CONSTRAINT ' + QUOTENAME(fk.ForeignKeyName)
                  ELSE N'' END
    FROM #File f
    JOIN cat.ForeignKey fk ON fk.DatabaseName = @DatabaseName AND fk.ParentObjectId = f.ObjectId
    CROSS APPLY (SELECT ParentCols = STRING_AGG(QUOTENAME(x.ParentColumnName), N', ') WITHIN GROUP (ORDER BY x.ColumnOrdinal),
                        RefCols    = STRING_AGG(QUOTENAME(x.RefColumnName), N', ')    WITHIN GROUP (ORDER BY x.ColumnOrdinal)
                 FROM cat.ForeignKeyColumn x
                 WHERE x.DatabaseName = fk.DatabaseName AND x.ForeignKeyId = fk.ForeignKeyId) fc
    WHERE f.ObjectType = 'Table'
    UNION ALL
    -- deaktivierte Check-Constraints
    SELECT f.RelativePath, 5, ck.ConstraintName,
           N'ALTER TABLE ' + ddl.fn_QName(f.SchemaName, f.ObjectName) + N' NOCHECK CONSTRAINT ' + QUOTENAME(ck.ConstraintName)
    FROM #File f
    JOIN cat.CheckConstraint ck ON ck.DatabaseName = @DatabaseName AND ck.ParentObjectId = f.ObjectId
    WHERE f.ObjectType = 'Table' AND ck.IsDisabled = 1 AND ck.IsSystemNamed = 0
    UNION ALL
    SELECT f.RelativePath, 6, e.SortKey, e.Stmt
    FROM #File f JOIN #EpStmt e ON e.ObjectId = f.ObjectId
    WHERE f.ObjectType = 'Table';

    /* ------------------------------------------------------------------
       Module: Views, Prozeduren, Funktionen, Trigger
       ------------------------------------------------------------------ */
    INSERT INTO #File (RelativePath, ObjectType, TypeLabel, SchemaName, ObjectName, ObjectId)
    SELECT @base
           + CASE o.ObjectType WHEN 'V'  THEN N'Views/'
                               WHEN 'P'  THEN N'StoredProcedures/'
                               WHEN 'TR' THEN N'Triggers/'
                               WHEN 'DT' THEN N'Triggers/'
                               ELSE N'Functions/' END
           + ddl.fn_FileName(CASE o.ObjectType
                                 WHEN 'TR' THEN p.SchemaName + N'.' + p.ObjectName + N'.' + o.ObjectName
                                 WHEN 'DT' THEN N'DB_' + o.ObjectName
                                 ELSE o.SchemaName + N'.' + o.ObjectName END) + N'.sql',
           CASE o.ObjectType WHEN 'V' THEN 'View' WHEN 'P' THEN 'StoredProcedure'
                             WHEN 'TR' THEN 'Trigger' WHEN 'DT' THEN 'DatabaseTrigger' ELSE 'Function' END,
           CASE o.ObjectType WHEN 'V' THEN N'View' WHEN 'P' THEN N'Stored Procedure'
                             WHEN 'TR' THEN N'Trigger' WHEN 'DT' THEN N'Datenbank-Trigger'
                             WHEN 'FN' THEN N'Skalarfunktion' WHEN 'IF' THEN N'Inline-Tabellenwertfunktion'
                             ELSE N'Tabellenwertfunktion' END,
           o.SchemaName,
           o.ObjectName,
           o.ObjectId
    FROM cat.[Object] o
    LEFT JOIN cat.[Object] p ON p.DatabaseName = o.DatabaseName AND p.ObjectId = o.ParentObjectId
    WHERE o.DatabaseName = @DatabaseName AND o.ObjectType IN ('V', 'P', 'FN', 'IF', 'TF', 'TR', 'DT');

    INSERT INTO #Stmt (RelativePath, Section, SortKey, Stmt)
    SELECT f.RelativePath, 0, N'', N'SET ANSI_NULLS ' + CASE WHEN ISNULL(o.UsesAnsiNulls, 1) = 1 THEN N'ON' ELSE N'OFF' END
    FROM #File f JOIN cat.[Object] o ON o.DatabaseName = @DatabaseName AND o.ObjectId = f.ObjectId
    WHERE f.ObjectType IN ('View', 'StoredProcedure', 'Function', 'Trigger', 'DatabaseTrigger')
    UNION ALL
    SELECT f.RelativePath, 1, N'', N'SET QUOTED_IDENTIFIER ' + CASE WHEN ISNULL(o.UsesQuotedIdentifier, 1) = 1 THEN N'ON' ELSE N'OFF' END
    FROM #File f JOIN cat.[Object] o ON o.DatabaseName = @DatabaseName AND o.ObjectId = f.ObjectId
    WHERE f.ObjectType IN ('View', 'StoredProcedure', 'Function', 'Trigger', 'DatabaseTrigger')
    UNION ALL
    SELECT f.RelativePath, 2, N'',
           ISNULL(ddl.fn_TrimWs(o.Definition), N'-- Definition nicht lesbar (WITH ENCRYPTION oder fehlende Berechtigung VIEW DEFINITION).')
    FROM #File f JOIN cat.[Object] o ON o.DatabaseName = @DatabaseName AND o.ObjectId = f.ObjectId
    WHERE f.ObjectType IN ('View', 'StoredProcedure', 'Function', 'Trigger', 'DatabaseTrigger')
    UNION ALL
    -- deaktivierte Trigger
    SELECT f.RelativePath, 3, N'',
           CASE WHEN o.ObjectType = 'DT'
                THEN N'DISABLE TRIGGER ' + QUOTENAME(o.ObjectName) + N' ON DATABASE'
                ELSE N'DISABLE TRIGGER ' + ddl.fn_QName(o.SchemaName, o.ObjectName) + N' ON ' + ddl.fn_QName(p.SchemaName, p.ObjectName) END
    FROM #File f
    JOIN cat.[Object] o      ON o.DatabaseName = @DatabaseName AND o.ObjectId = f.ObjectId
    LEFT JOIN cat.[Object] p ON p.DatabaseName = o.DatabaseName AND p.ObjectId = o.ParentObjectId
    WHERE f.ObjectType IN ('Trigger', 'DatabaseTrigger') AND o.IsDisabled = 1
    UNION ALL
    -- Indizes auf Views
    SELECT f.RelativePath, 4, x.IndexName, x.Stmt
    FROM #File f JOIN #IdxStmt x ON x.ObjectId = f.ObjectId
    WHERE f.ObjectType = 'View'
    UNION ALL
    SELECT f.RelativePath, 5, e.SortKey, e.Stmt
    FROM #File f JOIN #EpStmt e ON e.ObjectId = f.ObjectId
    WHERE f.ObjectType IN ('View', 'StoredProcedure', 'Function', 'Trigger');

    /* ------------------------------------------------------------------
       Schemas, Typen, Sequences, Synonyme
       ------------------------------------------------------------------ */
    INSERT INTO #File (RelativePath, ObjectType, TypeLabel, SchemaName, ObjectName, ObjectId)
    SELECT @base + N'Schemas/' + ddl.fn_FileName(s.SchemaName) + N'.sql', 'Schema', N'Schema', NULL, s.SchemaName, s.SchemaId
    FROM cat.[Schema] s WHERE s.DatabaseName = @DatabaseName;

    INSERT INTO #Stmt (RelativePath, Section, SortKey, Stmt)
    SELECT @base + N'Schemas/' + ddl.fn_FileName(s.SchemaName) + N'.sql', 0, N'',
           N'CREATE SCHEMA ' + QUOTENAME(s.SchemaName) + ISNULL(N' AUTHORIZATION ' + QUOTENAME(s.OwnerName), N'')
    FROM cat.[Schema] s WHERE s.DatabaseName = @DatabaseName;

    INSERT INTO #File (RelativePath, ObjectType, TypeLabel, SchemaName, ObjectName, ObjectId)
    SELECT @base + N'Types/' + ddl.fn_FileName(t.SchemaName + N'.' + t.TypeName) + N'.sql',
           CASE WHEN t.IsTableType = 1 THEN 'TableType' ELSE 'AliasType' END,
           CASE WHEN t.IsTableType = 1 THEN N'Tabellentyp' ELSE N'Alias-Datentyp' END,
           t.SchemaName, t.TypeName, t.UserTypeId
    FROM cat.[Type] t WHERE t.DatabaseName = @DatabaseName;

    INSERT INTO #Stmt (RelativePath, Section, SortKey, Stmt)
    SELECT @base + N'Types/' + ddl.fn_FileName(t.SchemaName + N'.' + t.TypeName) + N'.sql', 0, N'',
           N'CREATE TYPE ' + ddl.fn_QName(t.SchemaName, t.TypeName)
           + CASE WHEN t.IsTableType = 1
                  THEN N' AS TABLE' + @nl + ISNULL(b.Body, N'()')
                  ELSE N' FROM ' + ddl.fn_DataType(t.BaseTypeName, NULL, 0, t.MaxLength, t.[Precision], t.Scale)
                       + CASE WHEN t.IsNullable = 1 THEN N' NULL' ELSE N' NOT NULL' END
             END
    FROM cat.[Type] t
    LEFT JOIN #Body b ON b.ObjectId = t.TableObjectId
    WHERE t.DatabaseName = @DatabaseName;

    INSERT INTO #File (RelativePath, ObjectType, TypeLabel, SchemaName, ObjectName, ObjectId)
    SELECT @base + N'Sequences/' + ddl.fn_FileName(s.SchemaName + N'.' + s.SequenceName) + N'.sql',
           'Sequence', N'Sequence', s.SchemaName, s.SequenceName, s.ObjectId
    FROM cat.[Sequence] s WHERE s.DatabaseName = @DatabaseName;

    INSERT INTO #Stmt (RelativePath, Section, SortKey, Stmt)
    SELECT @base + N'Sequences/' + ddl.fn_FileName(s.SchemaName + N'.' + s.SequenceName) + N'.sql', 0, N'',
           N'CREATE SEQUENCE ' + ddl.fn_QName(s.SchemaName, s.SequenceName)
           + N' AS ' + ddl.fn_DataType(s.TypeName, NULL, 0, 0, s.[Precision], s.Scale) + @nl
           + N'    START WITH ' + s.StartValue + @nl
           + N'    INCREMENT BY ' + s.IncrementValue + @nl
           + N'    MINVALUE ' + s.MinimumValue + @nl
           + N'    MAXVALUE ' + s.MaximumValue + @nl
           + N'    ' + CASE WHEN s.IsCycling = 1 THEN N'CYCLE' ELSE N'NO CYCLE' END + @nl
           + N'    ' + CASE WHEN s.IsCached = 0 THEN N'NO CACHE'
                            WHEN s.CacheSize IS NULL THEN N'CACHE'
                            ELSE N'CACHE ' + CAST(s.CacheSize AS nvarchar(20)) END
    FROM cat.[Sequence] s WHERE s.DatabaseName = @DatabaseName;

    INSERT INTO #File (RelativePath, ObjectType, TypeLabel, SchemaName, ObjectName, ObjectId)
    SELECT @base + N'Synonyms/' + ddl.fn_FileName(s.SchemaName + N'.' + s.SynonymName) + N'.sql',
           'Synonym', N'Synonym', s.SchemaName, s.SynonymName, s.ObjectId
    FROM cat.Synonym s WHERE s.DatabaseName = @DatabaseName;

    INSERT INTO #Stmt (RelativePath, Section, SortKey, Stmt)
    SELECT @base + N'Synonyms/' + ddl.fn_FileName(s.SchemaName + N'.' + s.SynonymName) + N'.sql', 0, N'',
           N'CREATE SYNONYM ' + ddl.fn_QName(s.SchemaName, s.SynonymName) + N' FOR ' + s.BaseObjectName
    FROM cat.Synonym s WHERE s.DatabaseName = @DatabaseName;

    /* ------------------------------------------------------------------
       Dateien zusammensetzen
       ------------------------------------------------------------------ */
    INSERT INTO #Script (RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content)
    SELECT f.RelativePath, @DatabaseName, f.ObjectType, f.SchemaName, f.ObjectName,
           ddl.fn_Header(f.TypeLabel,
                         CASE WHEN f.SchemaName IS NULL THEN QUOTENAME(f.ObjectName)
                              ELSE ddl.fn_QName(f.SchemaName, f.ObjectName) END)
           + s.Body
    FROM #File f
    CROSS APPLY (SELECT Body = STRING_AGG(CAST(x.Stmt AS nvarchar(max)) + @nl + N'GO' + @nl, @nl)
                               WITHIN GROUP (ORDER BY x.Section, x.SortKey)
                 FROM #Stmt x WHERE x.RelativePath = f.RelativePath) s
    WHERE s.Body IS NOT NULL;
END;
GO
