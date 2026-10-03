/*
    07_Script_Catalog.sql
    ddl.usp_Script_Catalog
        Erzeugt je Fach-DB die Datei catalog.jsonl fuer KI-Agenten:
        eine JSON-Zeile je Tabelle, View, Prozedur und Funktion (JSON Lines,
        zeilenweise diff-freundlich). Ergebnis -> Temp-Tabelle #Script.

    Felder (je nach Typ):
        type, schema, name, file, description, configData,
        columns[{name,type,nullable,identity,computed,default,description}],
        primaryKey[], foreignKeys[{name,columns[],referencedTable,referencedColumns[]}],
        parameters[{name,type,output}]
*/
USE [$(AdminDb)];
GO

CREATE OR ALTER PROCEDURE ddl.usp_Script_Catalog
    @RunId        int,
    @DatabaseName sysname,
    @FolderName   nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl   nchar(2)      = NCHAR(13) + NCHAR(10);
    DECLARE @base nvarchar(200) = N'Databases/' + ddl.fn_FileName(@FolderName) + N'/';

    CREATE TABLE #Line (SortType int NOT NULL, SchemaName sysname NULL, ObjectName sysname NOT NULL, Line nvarchar(max) NOT NULL);

    INSERT INTO #Line (SortType, SchemaName, ObjectName, Line)
    SELECT CASE o.ObjectType WHEN 'U' THEN 1 WHEN 'V' THEN 2 WHEN 'P' THEN 3 ELSE 4 END,
           o.SchemaName, o.ObjectName,
           (
               SELECT
                   [type]   = CASE o.ObjectType WHEN 'U' THEN 'TABLE' WHEN 'V' THEN 'VIEW' WHEN 'P' THEN 'PROCEDURE'
                                                WHEN 'FN' THEN 'SCALAR_FUNCTION' WHEN 'IF' THEN 'INLINE_TABLE_FUNCTION'
                                                ELSE 'TABLE_FUNCTION' END,
                   [schema] = o.SchemaName,
                   [name]   = o.ObjectName,
                   [file]   = CASE o.ObjectType WHEN 'U' THEN N'Tables/' WHEN 'V' THEN N'Views/' WHEN 'P' THEN N'StoredProcedures/'
                                                ELSE N'Functions/' END
                              + ddl.fn_FileName(o.SchemaName + N'.' + o.ObjectName) + N'.sql',
                   [description] = (SELECT ep.PropertyValue FROM cat.ExtendedProperty ep
                                    WHERE ep.DatabaseName = o.DatabaseName AND ep.MajorId = o.ObjectId
                                      AND ep.MinorId = 0 AND ep.PropertyName = N'MS_Description'),
                   [configData] = CASE WHEN EXISTS (SELECT 1 FROM ddl.ExportConfigTable ct
                                                    WHERE ct.DatabaseName = o.DatabaseName AND ct.IsActive = 1
                                                      AND ct.SchemaName = o.SchemaName AND ct.TableName = o.ObjectName)
                                       THEN N'ConfigData/' + ddl.fn_FileName(o.SchemaName + N'.' + o.ObjectName) + N'.sql' END,
                   [columns] = JSON_QUERY((
                       SELECT [name]     = c.ColumnName,
                              [type]     = ddl.fn_DataType(c.TypeName, c.TypeSchemaName, c.IsUserDefinedType, c.MaxLength, c.[Precision], c.Scale),
                              [nullable] = c.IsNullable,
                              [identity] = CASE WHEN c.IsIdentity = 1 THEN CAST(1 AS bit) END,
                              [computed] = c.ComputedDefinition,
                              [default]  = c.DefaultDefinition,
                              [description] = (SELECT ep.PropertyValue FROM cat.ExtendedProperty ep
                                               WHERE ep.DatabaseName = c.DatabaseName AND ep.MajorId = c.ObjectId
                                                 AND ep.MinorId = c.ColumnId AND ep.PropertyName = N'MS_Description')
                       FROM cat.[Column] c
                       WHERE c.DatabaseName = o.DatabaseName AND c.ObjectId = o.ObjectId
                       ORDER BY c.ColumnId
                       FOR JSON PATH)),
                   [primaryKey] = JSON_QUERY((
                       SELECT N'[' + STRING_AGG(N'"' + STRING_ESCAPE(ic.ColumnName, 'json') + N'"', N',') WITHIN GROUP (ORDER BY ic.KeyOrdinal) + N']'
                       FROM cat.[Index] i
                       JOIN cat.IndexColumn ic ON ic.DatabaseName = i.DatabaseName AND ic.ObjectId = i.ObjectId AND ic.IndexId = i.IndexId
                       WHERE i.DatabaseName = o.DatabaseName AND i.ObjectId = o.ObjectId AND i.IsPrimaryKey = 1 AND ic.KeyOrdinal > 0)),
                   [foreignKeys] = JSON_QUERY((
                       SELECT [name]              = fk.ForeignKeyName,
                              [columns]           = JSON_QUERY(N'[' + fc.ParentCols + N']'),
                              [referencedTable]   = fk.RefSchemaName + N'.' + fk.RefTableName,
                              [referencedColumns] = JSON_QUERY(N'[' + fc.RefCols + N']')
                       FROM cat.ForeignKey fk
                       CROSS APPLY (SELECT ParentCols = STRING_AGG(N'"' + STRING_ESCAPE(x.ParentColumnName, 'json') + N'"', N',') WITHIN GROUP (ORDER BY x.ColumnOrdinal),
                                           RefCols    = STRING_AGG(N'"' + STRING_ESCAPE(x.RefColumnName, 'json') + N'"', N',')    WITHIN GROUP (ORDER BY x.ColumnOrdinal)
                                    FROM cat.ForeignKeyColumn x
                                    WHERE x.DatabaseName = fk.DatabaseName AND x.ForeignKeyId = fk.ForeignKeyId) fc
                       WHERE fk.DatabaseName = o.DatabaseName AND fk.ParentObjectId = o.ObjectId
                       ORDER BY fk.ForeignKeyName
                       FOR JSON PATH)),
                   [parameters] = JSON_QUERY((
                       SELECT [name]   = p.ParameterName,
                              [type]   = ddl.fn_DataType(p.TypeName, p.TypeSchemaName, p.IsUserDefinedType, p.MaxLength, p.[Precision], p.Scale),
                              [output] = CASE WHEN p.IsOutput = 1 THEN CAST(1 AS bit) END
                       FROM cat.[Parameter] p
                       WHERE p.DatabaseName = o.DatabaseName AND p.ObjectId = o.ObjectId
                       ORDER BY p.ParameterId
                       FOR JSON PATH))
               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
           )
    FROM cat.[Object] o
    WHERE o.DatabaseName = @DatabaseName
      AND o.ObjectType IN ('U', 'V', 'P', 'FN', 'IF', 'TF');

    INSERT INTO #Script (RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content)
    SELECT @base + N'catalog.jsonl', @DatabaseName, 'Catalog', NULL, N'catalog',
           STRING_AGG(Line, @nl) WITHIN GROUP (ORDER BY SortType, SchemaName, ObjectName) + @nl
    FROM #Line
    HAVING COUNT(*) > 0;
END;
GO
