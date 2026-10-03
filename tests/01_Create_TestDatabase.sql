/*
    01_Create_TestDatabase.sql
    Legt die Testdatenbank DDLX_Test mit moeglichst vielen Objekttypen an.
    Nur fuer Entwicklung/Test des Packages - NICHT auf Produktion ausfuehren.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE [master];
GO
IF DB_ID(N'DDLX_Test') IS NOT NULL
BEGIN
    ALTER DATABASE [DDLX_Test] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [DDLX_Test];
END;
GO
CREATE DATABASE [DDLX_Test];
GO
USE [DDLX_Test];
GO
CREATE SCHEMA [cfg] AUTHORIZATION [dbo];
GO
CREATE TYPE dbo.Kurztext FROM nvarchar(50) NOT NULL;
GO
CREATE TYPE dbo.IdListe AS TABLE (Id int NOT NULL PRIMARY KEY, Bemerkung nvarchar(100) NULL, CHECK (Id > 0));
GO
CREATE SEQUENCE dbo.SeqBeleg AS bigint START WITH 1000 INCREMENT BY 1 MINVALUE 1 MAXVALUE 999999999 NO CYCLE CACHE 50;
GO
CREATE TABLE dbo.Kunde
(
    KundeId     int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Kunde PRIMARY KEY,
    Name        dbo.Kurztext,
    Email       varchar(200) NULL CONSTRAINT UQ_Kunde_Email UNIQUE,
    Rabatt      decimal(5,2) NOT NULL CONSTRAINT DF_Kunde_Rabatt DEFAULT (0) CONSTRAINT CK_Kunde_Rabatt CHECK (Rabatt BETWEEN 0 AND 100),
    Anlage      datetime2(3) NOT NULL DEFAULT (SYSDATETIME()),
    NameLaenge  AS (LEN(Name)) PERSISTED,
    RowVer      rowversion
);
GO
CREATE TABLE dbo.Auftrag
(
    AuftragId   bigint NOT NULL CONSTRAINT DF_Auftrag_Id DEFAULT (NEXT VALUE FOR dbo.SeqBeleg),
    KundeId     int NOT NULL,
    Datum       date NOT NULL,
    Betrag      money NULL,
    Status      char(1) NOT NULL CHECK (Status IN ('N', 'B', 'S')),
    CONSTRAINT PK_Auftrag PRIMARY KEY CLUSTERED (AuftragId DESC),
    CONSTRAINT FK_Auftrag_Kunde FOREIGN KEY (KundeId) REFERENCES dbo.Kunde (KundeId) ON DELETE CASCADE
);
GO
CREATE NONCLUSTERED INDEX IX_Auftrag_Kunde ON dbo.Auftrag (KundeId, Datum DESC) INCLUDE (Betrag) WHERE Status <> 'S';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Auftraege der Kunden', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Auftrag';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Kunden-''Referenz''', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'Auftrag', @level2type = N'COLUMN', @level2name = N'KundeId';
GO
/* system-versionierte Tabelle */
CREATE TABLE cfg.Parameter
(
    ParamKey    varchar(50)   NOT NULL CONSTRAINT PK_Parameter PRIMARY KEY,
    ParamWert   nvarchar(max) NULL,
    Zahl        float         NULL,
    Stichtag    datetime      NULL,
    Offset      datetimeoffset(7) NULL,
    Uhrzeit     time(3)       NULL,
    Guid        uniqueidentifier NULL,
    Bin         varbinary(20) NULL,
    Aktiv       bit           NOT NULL CONSTRAINT DF_Parameter_Aktiv DEFAULT (1),
    Geheim      nvarchar(100) NULL,
    GueltigVon  datetime2(7) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    GueltigBis  datetime2(7) GENERATED ALWAYS AS ROW END HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (GueltigVon, GueltigBis)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = cfg.ParameterHistorie));
GO
INSERT INTO cfg.Parameter (ParamKey, ParamWert, Zahl, Stichtag, Offset, Uhrzeit, Guid, Bin, Aktiv, Geheim)
VALUES ('A_Text',     N'Mit ''Hochkomma'' und Umlaut äöüß €', 0.1, '2026-01-31T13:45:00.123', '2026-01-31T13:45:00.1234567+01:00', '08:15:30.5', '6F9619FF-8B86-D011-B42D-00C04FC964FF', 0x0102FF, 1, N'pw1'),
       ('B_Mehrzeil', N'Zeile1' + NCHAR(13) + NCHAR(10) + N'GO' + NCHAR(13) + NCHAR(10) + N'Zeile3', 1E+300, NULL, NULL, NULL, NULL, NULL, 0, N'pw2'),
       ('C_Null',     NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, NULL);
GO
/* Konfig-Tabelle mit Identity, ohne PK */
CREATE TABLE cfg.Mapping
(
    MappingId   int IDENTITY(10,5) NOT NULL,
    Quelle      nvarchar(20) NOT NULL,
    Ziel        nvarchar(20) NULL,
    Gewicht     numeric(9,4) NULL
);
GO
INSERT INTO cfg.Mapping (Quelle, Ziel, Gewicht) VALUES (N'X', N'Y', 1.5), (N'A', NULL, -2.25);
GO
CREATE VIEW dbo.vAuftragKunde
WITH SCHEMABINDING
AS
SELECT a.AuftragId, a.Datum, k.KundeId, k.Name
FROM dbo.Auftrag a
JOIN dbo.Kunde k ON k.KundeId = a.KundeId;
GO
CREATE UNIQUE CLUSTERED INDEX CIX_vAuftragKunde ON dbo.vAuftragKunde (AuftragId);
GO
CREATE PROCEDURE dbo.usp_KundeAnlegen
    @Name  nvarchar(50),
    @Email varchar(200) = NULL,
    @Id    int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Kunde (Name, Email) VALUES (@Name, @Email);
    SET @Id = SCOPE_IDENTITY();
END;
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Legt einen Kunden an', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'PROCEDURE', @level1name = N'usp_KundeAnlegen';
GO
CREATE FUNCTION dbo.fn_Brutto (@Netto money) RETURNS money AS BEGIN RETURN @Netto * 1.19; END;
GO
CREATE FUNCTION dbo.fn_AuftraegeVon (@KundeId int) RETURNS TABLE AS RETURN (SELECT AuftragId, Datum FROM dbo.Auftrag WHERE KundeId = @KundeId);
GO
CREATE TRIGGER dbo.trg_Kunde_Upd ON dbo.Kunde AFTER UPDATE AS BEGIN SET NOCOUNT ON; END;
GO
DISABLE TRIGGER dbo.trg_Kunde_Upd ON dbo.Kunde;
GO
CREATE TRIGGER trg_DDL_Log ON DATABASE FOR CREATE_TABLE AS BEGIN SET NOCOUNT ON; END;
GO
CREATE SYNONYM dbo.synKunde FOR dbo.Kunde;
GO
