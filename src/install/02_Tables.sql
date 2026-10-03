/*
    02_Tables.sql
    Konfigurations-, Protokoll-, Snapshot- und Staging-Tabellen (idempotent).

    Schema ddl : Konfiguration, Lauf-Protokoll, Export-Snapshot
    Schema cat : Staging der Systemkataloge der Fach-DBs (wird je Lauf und DB neu befuellt)
*/
USE [$(AdminDb)];
GO

/* ---------------------------------------------------------------------------
   Konfiguration
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'ddl.ExportSetting', N'U') IS NULL
CREATE TABLE ddl.ExportSetting
(
    SettingKey      varchar(50)    NOT NULL CONSTRAINT PK_ExportSetting PRIMARY KEY,
    SettingValue    nvarchar(4000) NULL,
    Description     nvarchar(1000) NULL,
    ModifiedAt      datetime2(0)   NOT NULL CONSTRAINT DF_ExportSetting_ModifiedAt DEFAULT (SYSDATETIME()),
    ModifiedBy      sysname        NOT NULL CONSTRAINT DF_ExportSetting_ModifiedBy DEFAULT (SUSER_SNAME())
);
GO

IF OBJECT_ID(N'ddl.ExportDatabase', N'U') IS NULL
CREATE TABLE ddl.ExportDatabase
(
    DatabaseName    sysname        NOT NULL CONSTRAINT PK_ExportDatabase PRIMARY KEY,
    IsActive        bit            NOT NULL CONSTRAINT DF_ExportDatabase_IsActive DEFAULT (1),
    FolderName      nvarchar(128)  NULL,      -- Ordnername unter export/Databases; NULL = DatabaseName
    Description     nvarchar(1000) NULL,
    ModifiedAt      datetime2(0)   NOT NULL CONSTRAINT DF_ExportDatabase_ModifiedAt DEFAULT (SYSDATETIME()),
    ModifiedBy      sysname        NOT NULL CONSTRAINT DF_ExportDatabase_ModifiedBy DEFAULT (SUSER_SNAME())
);
GO

IF OBJECT_ID(N'ddl.ExportConfigTable', N'U') IS NULL
CREATE TABLE ddl.ExportConfigTable
(
    DatabaseName    sysname        NOT NULL,
    SchemaName      sysname        NOT NULL CONSTRAINT DF_ExportConfigTable_SchemaName DEFAULT (N'dbo'),
    TableName       sysname        NOT NULL,
    IsActive        bit            NOT NULL CONSTRAINT DF_ExportConfigTable_IsActive DEFAULT (1),
    OrderByColumns  nvarchar(1000) NULL,      -- kommagetrennt; NULL = Primaerschluessel
    ExcludeColumns  nvarchar(1000) NULL,      -- kommagetrennt; Spalten werden nicht exportiert
    MaskColumns     nvarchar(1000) NULL,      -- kommagetrennt; Werte werden maskiert (Text: N'***', sonst NULL)
    Description     nvarchar(1000) NULL,
    ModifiedAt      datetime2(0)   NOT NULL CONSTRAINT DF_ExportConfigTable_ModifiedAt DEFAULT (SYSDATETIME()),
    ModifiedBy      sysname        NOT NULL CONSTRAINT DF_ExportConfigTable_ModifiedBy DEFAULT (SUSER_SNAME()),
    CONSTRAINT PK_ExportConfigTable PRIMARY KEY (DatabaseName, SchemaName, TableName),
    CONSTRAINT FK_ExportConfigTable_ExportDatabase FOREIGN KEY (DatabaseName)
        REFERENCES ddl.ExportDatabase (DatabaseName) ON UPDATE CASCADE
);
GO

IF OBJECT_ID(N'ddl.ExportJob', N'U') IS NULL
CREATE TABLE ddl.ExportJob
(
    JobNamePattern  nvarchar(128)  NOT NULL CONSTRAINT PK_ExportJob PRIMARY KEY,  -- LIKE-Muster
    IsActive        bit            NOT NULL CONSTRAINT DF_ExportJob_IsActive DEFAULT (1),
    Description     nvarchar(1000) NULL,
    ModifiedAt      datetime2(0)   NOT NULL CONSTRAINT DF_ExportJob_ModifiedAt DEFAULT (SYSDATETIME()),
    ModifiedBy      sysname        NOT NULL CONSTRAINT DF_ExportJob_ModifiedBy DEFAULT (SUSER_SNAME())
);
GO

/* ---------------------------------------------------------------------------
   Lauf-Protokoll
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'ddl.ExportRun', N'U') IS NULL
CREATE TABLE ddl.ExportRun
(
    RunId           int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExportRun PRIMARY KEY,
    StartedAt       datetime2(0)   NOT NULL CONSTRAINT DF_ExportRun_StartedAt DEFAULT (SYSDATETIME()),
    FinishedAt      datetime2(0)   NULL,
    ExportMode      varchar(20)    NOT NULL,
    Status          varchar(20)    NOT NULL CONSTRAINT DF_ExportRun_Status DEFAULT ('Running'),  -- Running/Succeeded/Warning/Failed/Skipped
    FileCount       int            NULL,
    WarningCount    int            NULL,
    ErrorCount      int            NULL,
    StartedBy       sysname        NOT NULL CONSTRAINT DF_ExportRun_StartedBy DEFAULT (SUSER_SNAME())
);
GO

IF OBJECT_ID(N'ddl.ExportLog', N'U') IS NULL
CREATE TABLE ddl.ExportLog
(
    LogId           bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExportLog PRIMARY KEY,
    RunId           int            NULL,
    LoggedAt        datetime2(3)   NOT NULL CONSTRAINT DF_ExportLog_LoggedAt DEFAULT (SYSDATETIME()),
    LogLevel        varchar(10)    NOT NULL,   -- INFO/WARN/ERROR
    Source          varchar(50)    NOT NULL CONSTRAINT DF_ExportLog_Source DEFAULT ('T-SQL'),
    DatabaseName    sysname        NULL,
    Message         nvarchar(4000) NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ddl.ExportLog') AND name = N'IX_ExportLog_RunId')
    CREATE INDEX IX_ExportLog_RunId ON ddl.ExportLog (RunId);
GO

/* ---------------------------------------------------------------------------
   Export-Snapshot: 1 Zeile = 1 Datei unter ExportRoot.
   Zeilen einer DB werden nur bei erfolgreichem Scripting dieser DB ersetzt.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'ddl.ExportScript', N'U') IS NULL
CREATE TABLE ddl.ExportScript
(
    RelativePath    nvarchar(400)  NOT NULL CONSTRAINT PK_ExportScript PRIMARY KEY,  -- mit '/' getrennt
    Scope           sysname        NOT NULL,  -- DB-Name bzw. '(Server)' fuer Jobs
    ObjectType      varchar(30)    NOT NULL,
    SchemaName      sysname        NULL,
    ObjectName      nvarchar(256)  NOT NULL,
    Content         nvarchar(max)  NOT NULL,
    ContentHash     AS CAST(HASHBYTES('SHA2_256', CAST(Content AS varbinary(max))) AS binary(32)) PERSISTED,
    RunId           int            NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ddl.ExportScript') AND name = N'IX_ExportScript_Scope')
    CREATE INDEX IX_ExportScript_Scope ON ddl.ExportScript (Scope);
GO

/* ---------------------------------------------------------------------------
   Staging der Systemkataloge (cat.*). Inhalt ist fluechtig.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'cat.[Schema]', N'U') IS NULL
CREATE TABLE cat.[Schema]
(
    DatabaseName sysname NOT NULL, SchemaId int NOT NULL, SchemaName sysname NOT NULL, OwnerName sysname NULL,
    CONSTRAINT PK_cat_Schema PRIMARY KEY (DatabaseName, SchemaId)
);
GO

IF OBJECT_ID(N'cat.[Object]', N'U') IS NULL
CREATE TABLE cat.[Object]
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    SchemaName            sysname       NULL,
    ObjectName            sysname       NOT NULL,
    ObjectType            char(2)       NOT NULL,   -- U, V, P, FN, IF, TF, TR, TT (Tabellentyp), DT (DB-Trigger)
    ParentObjectId        int           NULL,
    Definition            nvarchar(max) NULL,
    UsesAnsiNulls         bit           NULL,
    UsesQuotedIdentifier  bit           NULL,
    IsDisabled            bit           NULL,       -- Trigger
    TemporalType          tinyint       NULL,       -- 2 = system-versioniert
    HistorySchemaName     sysname       NULL,
    HistoryTableName      sysname       NULL,
    CONSTRAINT PK_cat_Object PRIMARY KEY (DatabaseName, ObjectId)
);
GO

IF OBJECT_ID(N'cat.[Column]', N'U') IS NULL
CREATE TABLE cat.[Column]
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    ColumnId              int           NOT NULL,
    ColumnName            sysname       NOT NULL,
    TypeName              sysname       NOT NULL,
    TypeSchemaName        sysname       NULL,
    IsUserDefinedType     bit           NOT NULL,
    SystemTypeName        sysname       NULL,       -- Basistyp (bei Alias-Typen)
    MaxLength             smallint      NOT NULL,
    [Precision]           tinyint       NOT NULL,
    Scale                 tinyint       NOT NULL,
    IsNullable            bit           NOT NULL,
    IsIdentity            bit           NOT NULL,
    SeedValue             nvarchar(40)  NULL,
    IncrementValue        nvarchar(40)  NULL,
    IsComputed            bit           NOT NULL,
    ComputedDefinition    nvarchar(max) NULL,
    IsPersisted           bit           NULL,
    IsSparse              bit           NOT NULL,
    IsRowGuidCol          bit           NOT NULL,
    GeneratedAlwaysType   tinyint       NOT NULL,
    IsHidden              bit           NOT NULL,
    DefaultName           sysname       NULL,
    DefaultDefinition     nvarchar(max) NULL,
    DefaultIsSystemNamed  bit           NULL,
    CONSTRAINT PK_cat_Column PRIMARY KEY (DatabaseName, ObjectId, ColumnId)
);
GO

IF OBJECT_ID(N'cat.[Index]', N'U') IS NULL
CREATE TABLE cat.[Index]
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    IndexId               int           NOT NULL,
    IndexName             sysname       NULL,
    IndexType             tinyint       NOT NULL,   -- 1 CL, 2 NCL, 5 CCI, 6 NCCI, 3 XML, 4 Spatial ...
    IsUnique              bit           NOT NULL,
    IsPrimaryKey          bit           NOT NULL,
    IsUniqueConstraint    bit           NOT NULL,
    IsSystemNamed         bit           NULL,       -- nur fuer PK/UQ
    FilterDefinition      nvarchar(max) NULL,
    IgnoreDupKey          bit           NOT NULL,
    CONSTRAINT PK_cat_Index PRIMARY KEY (DatabaseName, ObjectId, IndexId)
);
GO

IF OBJECT_ID(N'cat.IndexColumn', N'U') IS NULL
CREATE TABLE cat.IndexColumn
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    IndexId               int           NOT NULL,
    IndexColumnId         int           NOT NULL,
    KeyOrdinal            tinyint       NOT NULL,
    ColumnName            sysname       NOT NULL,
    IsDescending          bit           NOT NULL,
    IsIncluded            bit           NOT NULL,
    CONSTRAINT PK_cat_IndexColumn PRIMARY KEY (DatabaseName, ObjectId, IndexId, IndexColumnId)
);
GO

IF OBJECT_ID(N'cat.ForeignKey', N'U') IS NULL
CREATE TABLE cat.ForeignKey
(
    DatabaseName          sysname       NOT NULL,
    ForeignKeyId          int           NOT NULL,
    ParentObjectId        int           NOT NULL,
    ForeignKeyName        sysname       NOT NULL,
    IsSystemNamed         bit           NOT NULL,
    RefSchemaName         sysname       NOT NULL,
    RefTableName          sysname       NOT NULL,
    DeleteAction          nvarchar(60)  NOT NULL,
    UpdateAction          nvarchar(60)  NOT NULL,
    IsDisabled            bit           NOT NULL,
    IsNotTrusted          bit           NOT NULL,
    CONSTRAINT PK_cat_ForeignKey PRIMARY KEY (DatabaseName, ForeignKeyId)
);
GO

IF OBJECT_ID(N'cat.ForeignKeyColumn', N'U') IS NULL
CREATE TABLE cat.ForeignKeyColumn
(
    DatabaseName          sysname       NOT NULL,
    ForeignKeyId          int           NOT NULL,
    ColumnOrdinal         int           NOT NULL,
    ParentColumnName      sysname       NOT NULL,
    RefColumnName         sysname       NOT NULL,
    CONSTRAINT PK_cat_ForeignKeyColumn PRIMARY KEY (DatabaseName, ForeignKeyId, ColumnOrdinal)
);
GO

IF OBJECT_ID(N'cat.CheckConstraint', N'U') IS NULL
CREATE TABLE cat.CheckConstraint
(
    DatabaseName          sysname       NOT NULL,
    ConstraintId          int           NOT NULL,
    ParentObjectId        int           NOT NULL,
    ConstraintName        sysname       NOT NULL,
    IsSystemNamed         bit           NOT NULL,
    Definition            nvarchar(max) NOT NULL,
    IsDisabled            bit           NOT NULL,
    CONSTRAINT PK_cat_CheckConstraint PRIMARY KEY (DatabaseName, ConstraintId)
);
GO

IF OBJECT_ID(N'cat.ExtendedProperty', N'U') IS NULL
CREATE TABLE cat.ExtendedProperty
(
    DatabaseName          sysname       NOT NULL,
    MajorId               int           NOT NULL,   -- object_id
    MinorId               int           NOT NULL,   -- 0 = Objekt, sonst column_id
    PropertyName          sysname       NOT NULL,
    PropertyValue         nvarchar(max) NULL,
    CONSTRAINT PK_cat_ExtendedProperty PRIMARY KEY (DatabaseName, MajorId, MinorId, PropertyName)
);
GO

IF OBJECT_ID(N'cat.[Parameter]', N'U') IS NULL
CREATE TABLE cat.[Parameter]
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    ParameterId           int           NOT NULL,
    ParameterName         sysname       NOT NULL,
    TypeName              sysname       NOT NULL,
    TypeSchemaName        sysname       NULL,
    IsUserDefinedType     bit           NOT NULL,
    MaxLength             smallint      NOT NULL,
    [Precision]           tinyint       NOT NULL,
    Scale                 tinyint       NOT NULL,
    IsOutput              bit           NOT NULL,
    CONSTRAINT PK_cat_Parameter PRIMARY KEY (DatabaseName, ObjectId, ParameterId)
);
GO

IF OBJECT_ID(N'cat.[Type]', N'U') IS NULL
CREATE TABLE cat.[Type]
(
    DatabaseName          sysname       NOT NULL,
    UserTypeId            int           NOT NULL,
    SchemaName            sysname       NOT NULL,
    TypeName              sysname       NOT NULL,
    IsTableType           bit           NOT NULL,
    TableObjectId         int           NULL,
    BaseTypeName          sysname       NULL,
    MaxLength             smallint      NOT NULL,
    [Precision]           tinyint       NOT NULL,
    Scale                 tinyint       NOT NULL,
    IsNullable            bit           NOT NULL,
    CONSTRAINT PK_cat_Type PRIMARY KEY (DatabaseName, UserTypeId)
);
GO

IF OBJECT_ID(N'cat.[Sequence]', N'U') IS NULL
CREATE TABLE cat.[Sequence]
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    SchemaName            sysname       NOT NULL,
    SequenceName          sysname       NOT NULL,
    TypeName              sysname       NOT NULL,
    [Precision]           tinyint       NOT NULL,
    Scale                 tinyint       NOT NULL,
    StartValue            nvarchar(50)  NOT NULL,
    IncrementValue        nvarchar(50)  NOT NULL,
    MinimumValue          nvarchar(50)  NOT NULL,
    MaximumValue          nvarchar(50)  NOT NULL,
    IsCycling             bit           NOT NULL,
    IsCached              bit           NOT NULL,
    CacheSize             int           NULL,
    CONSTRAINT PK_cat_Sequence PRIMARY KEY (DatabaseName, ObjectId)
);
GO

IF OBJECT_ID(N'cat.Synonym', N'U') IS NULL
CREATE TABLE cat.Synonym
(
    DatabaseName          sysname       NOT NULL,
    ObjectId              int           NOT NULL,
    SchemaName            sysname       NOT NULL,
    SynonymName           sysname       NOT NULL,
    BaseObjectName        nvarchar(1035) NOT NULL,
    CONSTRAINT PK_cat_Synonym PRIMARY KEY (DatabaseName, ObjectId)
);
GO
