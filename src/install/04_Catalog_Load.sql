/*
    04_Catalog_Load.sql
    ddl.usp_Log           Protokollierung
    ddl.usp_Catalog_Load  Liest die Systemkataloge einer Fach-DB in die Staging-Tabellen cat.*

    Die Abfragen laufen per  EXEC [<DB>].sys.sp_executesql  im Kontext der Fach-DB.
    In den Fach-DBs werden keine Objekte angelegt.
*/
USE [$(AdminDb)];
GO

CREATE OR ALTER PROCEDURE ddl.usp_Log
    @RunId        int,
    @LogLevel     varchar(10),
    @Message      nvarchar(4000),
    @DatabaseName sysname     = NULL,
    @Source       varchar(50) = 'T-SQL'
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO ddl.ExportLog (RunId, LogLevel, Source, DatabaseName, Message)
    VALUES (@RunId, @LogLevel, @Source, @DatabaseName, @Message);

    -- Ausgabe auch in die Job-Historie
    DECLARE @line nvarchar(4000) = CONCAT(@LogLevel, N': ', ISNULL(@DatabaseName + N': ', N''), @Message);
    RAISERROR (N'%s', 0, 1, @line) WITH NOWAIT;
END;
GO

CREATE OR ALTER PROCEDURE ddl.usp_Catalog_Load
    @RunId        int,
    @DatabaseName sysname
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @exec nvarchar(400) = QUOTENAME(@DatabaseName) + N'.sys.sp_executesql';
    DECLARE @sql  nvarchar(max);
    DECLARE @prm  nvarchar(100) = N'@db sysname';

    -- Staging dieser DB leeren
    DELETE FROM cat.[Schema]          WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.[Object]          WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.[Column]          WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.[Index]           WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.IndexColumn       WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.ForeignKey        WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.ForeignKeyColumn  WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.CheckConstraint   WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.ExtendedProperty  WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.[Parameter]       WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.[Type]            WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.[Sequence]        WHERE DatabaseName = @DatabaseName;
    DELETE FROM cat.Synonym           WHERE DatabaseName = @DatabaseName;

    /*
        Gemeinsamer Filter: Benutzerobjekte ohne SSMS-Diagramm-Hilfsobjekte
        (microsoft_database_tools_support, z. B. dbo.sysdiagrams).
    */
    DECLARE @userObj nvarchar(max) = N'
        WITH UserObj AS
        (
            SELECT o.object_id, o.type
            FROM sys.objects o
            WHERE o.is_ms_shipped = 0
              AND o.type IN (''U'', ''V'', ''P'', ''FN'', ''IF'', ''TF'', ''TR'')
              AND NOT EXISTS (SELECT 1 FROM sys.extended_properties ep
                              WHERE ep.class = 1 AND ep.major_id = o.object_id AND ep.minor_id = 0
                                AND ep.name = N''microsoft_database_tools_support'')
            UNION ALL
            SELECT tt.type_table_object_id, ''TT''
            FROM sys.table_types tt
            WHERE tt.is_user_defined = 1
        )
    ';

    /* Schemas (nur benutzerdefinierte, ohne dbo/guest/sys/INFORMATION_SCHEMA und Rollen-Schemas) */
    SET @sql = N'
        SELECT @db, s.schema_id, s.name, USER_NAME(s.principal_id)
        FROM sys.schemas s
        WHERE s.schema_id BETWEEN 5 AND 16383;';
    INSERT INTO cat.[Schema] (DatabaseName, SchemaId, SchemaName, OwnerName)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Objekte inkl. Moduldefinitionen */
    SET @sql = @userObj + N'
        SELECT @db, o.object_id, s.name, o.name, o.type,
               NULLIF(o.parent_object_id, 0),
               m.definition, COALESCE(m.uses_ansi_nulls, t.uses_ansi_nulls), m.uses_quoted_identifier,
               tr.is_disabled, t.temporal_type, hs.name, ht.name
        FROM UserObj u
        JOIN sys.objects o            ON o.object_id = u.object_id
        JOIN sys.schemas s            ON s.schema_id = o.schema_id
        LEFT JOIN sys.sql_modules m   ON m.object_id = o.object_id
        LEFT JOIN sys.triggers tr     ON tr.object_id = o.object_id
        LEFT JOIN sys.tables t        ON t.object_id = o.object_id
        LEFT JOIN sys.tables ht       ON ht.object_id = t.history_table_id
        LEFT JOIN sys.schemas hs      ON hs.schema_id = ht.schema_id
        WHERE u.type <> ''TT''
        UNION ALL
        SELECT @db, tr.object_id, NULL, tr.name, ''DT'', NULL,
               m.definition, m.uses_ansi_nulls, m.uses_quoted_identifier,
               tr.is_disabled, NULL, NULL, NULL
        FROM sys.triggers tr
        JOIN sys.sql_modules m ON m.object_id = tr.object_id
        WHERE tr.parent_class = 0 AND tr.is_ms_shipped = 0;';
    INSERT INTO cat.[Object] (DatabaseName, ObjectId, SchemaName, ObjectName, ObjectType, ParentObjectId,
                              Definition, UsesAnsiNulls, UsesQuotedIdentifier, IsDisabled,
                              TemporalType, HistorySchemaName, HistoryTableName)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Spalten von Tabellen, Views, Tabellenwertfunktionen und Tabellentypen */
    SET @sql = @userObj + N'
        SELECT @db, c.object_id, c.column_id, c.name,
               ty.name, SCHEMA_NAME(ty.schema_id), ty.is_user_defined,
               CASE WHEN ty.is_user_defined = 0 THEN ty.name ELSE TYPE_NAME(ty.system_type_id) END,
               c.max_length, c.precision, c.scale, c.is_nullable, c.is_identity,
               CAST(ic.seed_value AS nvarchar(40)), CAST(ic.increment_value AS nvarchar(40)),
               c.is_computed, cc.definition, cc.is_persisted,
               c.is_sparse, c.is_rowguidcol, c.generated_always_type, c.is_hidden,
               dc.name, dc.definition, dc.is_system_named
        FROM UserObj u
        JOIN sys.columns c                    ON c.object_id = u.object_id
        JOIN sys.types ty                     ON ty.user_type_id = c.user_type_id
        LEFT JOIN sys.identity_columns ic     ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        LEFT JOIN sys.computed_columns cc     ON cc.object_id = c.object_id AND cc.column_id = c.column_id
        LEFT JOIN sys.default_constraints dc  ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
        WHERE u.type IN (''U'', ''V'', ''IF'', ''TF'', ''TT'');';
    INSERT INTO cat.[Column] (DatabaseName, ObjectId, ColumnId, ColumnName, TypeName, TypeSchemaName,
                              IsUserDefinedType, SystemTypeName, MaxLength, [Precision], Scale, IsNullable,
                              IsIdentity, SeedValue, IncrementValue, IsComputed, ComputedDefinition, IsPersisted,
                              IsSparse, IsRowGuidCol, GeneratedAlwaysType, IsHidden,
                              DefaultName, DefaultDefinition, DefaultIsSystemNamed)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Indizes (Tabellen, indizierte Views, Tabellentypen) */
    SET @sql = @userObj + N'
        SELECT @db, i.object_id, i.index_id, i.name, i.type, i.is_unique, i.is_primary_key,
               i.is_unique_constraint, kc.is_system_named, i.filter_definition, i.ignore_dup_key
        FROM UserObj u
        JOIN sys.indexes i               ON i.object_id = u.object_id
        LEFT JOIN sys.key_constraints kc ON kc.parent_object_id = i.object_id AND kc.unique_index_id = i.index_id
        WHERE u.type IN (''U'', ''V'', ''TT'') AND i.type > 0 AND i.is_hypothetical = 0;';
    INSERT INTO cat.[Index] (DatabaseName, ObjectId, IndexId, IndexName, IndexType, IsUnique, IsPrimaryKey,
                             IsUniqueConstraint, IsSystemNamed, FilterDefinition, IgnoreDupKey)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    SET @sql = @userObj + N'
        SELECT @db, ic.object_id, ic.index_id, ic.index_column_id, ic.key_ordinal, c.name,
               ic.is_descending_key, ic.is_included_column
        FROM UserObj u
        JOIN sys.indexes i        ON i.object_id = u.object_id
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE u.type IN (''U'', ''V'', ''TT'') AND i.type > 0 AND i.is_hypothetical = 0;';
    INSERT INTO cat.IndexColumn (DatabaseName, ObjectId, IndexId, IndexColumnId, KeyOrdinal, ColumnName,
                                 IsDescending, IsIncluded)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Fremdschluessel */
    SET @sql = @userObj + N'
        SELECT @db, fk.object_id, fk.parent_object_id, fk.name, fk.is_system_named,
               SCHEMA_NAME(rt.schema_id), rt.name,
               fk.delete_referential_action_desc, fk.update_referential_action_desc,
               fk.is_disabled, fk.is_not_trusted
        FROM UserObj u
        JOIN sys.foreign_keys fk ON fk.parent_object_id = u.object_id
        JOIN sys.objects rt      ON rt.object_id = fk.referenced_object_id
        WHERE u.type = ''U'';';
    INSERT INTO cat.ForeignKey (DatabaseName, ForeignKeyId, ParentObjectId, ForeignKeyName, IsSystemNamed,
                                RefSchemaName, RefTableName, DeleteAction, UpdateAction, IsDisabled, IsNotTrusted)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    SET @sql = @userObj + N'
        SELECT @db, fkc.constraint_object_id, fkc.constraint_column_id,
               COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
               COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
        FROM UserObj u
        JOIN sys.foreign_key_columns fkc ON fkc.parent_object_id = u.object_id
        WHERE u.type = ''U'';';
    INSERT INTO cat.ForeignKeyColumn (DatabaseName, ForeignKeyId, ColumnOrdinal, ParentColumnName, RefColumnName)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Check-Constraints */
    SET @sql = @userObj + N'
        SELECT @db, ck.object_id, ck.parent_object_id, ck.name, ck.is_system_named, ck.definition, ck.is_disabled
        FROM UserObj u
        JOIN sys.check_constraints ck ON ck.parent_object_id = u.object_id
        WHERE u.type IN (''U'', ''TT'');';
    INSERT INTO cat.CheckConstraint (DatabaseName, ConstraintId, ParentObjectId, ConstraintName, IsSystemNamed,
                                     Definition, IsDisabled)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Extended Properties auf Objekten und Spalten */
    SET @sql = @userObj + N'
        SELECT @db, ep.major_id, ep.minor_id, ep.name, CONVERT(nvarchar(4000), ep.value)
        FROM UserObj u
        JOIN sys.extended_properties ep ON ep.class = 1 AND ep.major_id = u.object_id
        WHERE u.type <> ''TT'';';
    INSERT INTO cat.ExtendedProperty (DatabaseName, MajorId, MinorId, PropertyName, PropertyValue)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Parameter von Prozeduren und Funktionen */
    SET @sql = @userObj + N'
        SELECT @db, p.object_id, p.parameter_id, p.name, ty.name, SCHEMA_NAME(ty.schema_id), ty.is_user_defined,
               p.max_length, p.precision, p.scale, p.is_output
        FROM UserObj u
        JOIN sys.parameters p ON p.object_id = u.object_id
        JOIN sys.types ty     ON ty.user_type_id = p.user_type_id
        WHERE u.type IN (''P'', ''FN'', ''IF'', ''TF'') AND p.parameter_id > 0;';
    INSERT INTO cat.[Parameter] (DatabaseName, ObjectId, ParameterId, ParameterName, TypeName, TypeSchemaName,
                                 IsUserDefinedType, MaxLength, [Precision], Scale, IsOutput)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Benutzerdefinierte Typen (Alias- und Tabellentypen, keine CLR-Typen) */
    SET @sql = N'
        SELECT @db, ty.user_type_id, SCHEMA_NAME(ty.schema_id), ty.name, ty.is_table_type,
               tt.type_table_object_id,
               CASE WHEN ty.is_table_type = 0 THEN TYPE_NAME(ty.system_type_id) END,
               ty.max_length, ty.precision, ty.scale, ty.is_nullable
        FROM sys.types ty
        LEFT JOIN sys.table_types tt ON tt.user_type_id = ty.user_type_id
        WHERE ty.is_user_defined = 1 AND ty.is_assembly_type = 0;';
    INSERT INTO cat.[Type] (DatabaseName, UserTypeId, SchemaName, TypeName, IsTableType, TableObjectId,
                            BaseTypeName, MaxLength, [Precision], Scale, IsNullable)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Sequences */
    SET @sql = N'
        SELECT @db, sq.object_id, SCHEMA_NAME(sq.schema_id), sq.name, TYPE_NAME(sq.user_type_id),
               sq.precision, sq.scale,
               CONVERT(nvarchar(50), sq.start_value), CONVERT(nvarchar(50), sq.increment),
               CONVERT(nvarchar(50), sq.minimum_value), CONVERT(nvarchar(50), sq.maximum_value),
               sq.is_cycling, sq.is_cached, sq.cache_size
        FROM sys.sequences sq
        WHERE sq.is_ms_shipped = 0;';
    INSERT INTO cat.[Sequence] (DatabaseName, ObjectId, SchemaName, SequenceName, TypeName, [Precision], Scale,
                                StartValue, IncrementValue, MinimumValue, MaximumValue, IsCycling, IsCached, CacheSize)
    EXEC @exec @sql, @prm, @db = @DatabaseName;

    /* Synonyme */
    SET @sql = N'
        SELECT @db, sn.object_id, SCHEMA_NAME(sn.schema_id), sn.name, sn.base_object_name
        FROM sys.synonyms sn
        WHERE sn.is_ms_shipped = 0;';
    INSERT INTO cat.Synonym (DatabaseName, ObjectId, SchemaName, SynonymName, BaseObjectName)
    EXEC @exec @sql, @prm, @db = @DatabaseName;
END;
GO
