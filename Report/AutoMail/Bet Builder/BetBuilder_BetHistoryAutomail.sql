USE [bodb_Report];

ALTER DATABASE bodb_Report ADD FILEGROUP BetBuilder_BetHistoryAutomail;
GO

ALTER DATABASE bodb_Report ADD FILE(NAME = BetBuilder_BetHistoryAutomail, FILENAME = 'D:\DB234_SQLSERVER2008R2\IBC_DB\bodb_Report\BetBuilder_BetHistoryAutomail.ndf', SIZE = 5 MB, MAXSIZE = UNLIMITED, FILEGROWTH = 32 MB) TO FILEGROUP BetBuilder_BetHistoryAutomail;
GO

CREATE TABLE dbo.BetBuilder_BetHistoryAutomail(
	WinlostDate     SMALLDATETIME NOT NULL
   , TransId         BIGINT NOT NULL
   , StatusId        TINYINT NOT NULL
   , MatchId         INT NOT NULL
   , CurrencyId      TINYINT NOT NULL
   , Betcheck        NVARCHAR(100) NULL
   , Hdp2            SMALLMONEY NULL
   , Odds            SMALLMONEY NULL
   , Stake           MONEY
   , Winlost         MONEY
   , Scomm           MONEY
   , CapturedDate    DATETIME NOT NULL
   , Transdate       DATETIME
   , Betfrom         VARCHAR(1))
ON BetBuilder_BetHistoryAutomail WITH(DATA_COMPRESSION = PAGE);

GO

CREATE CLUSTERED INDEX CIX_BetBuilder_BetHistoryAutomail ON dbo.BetBuilder_BetHistoryAutomail(WinlostDate ASC, TransId ASC)
	WITH(DATA_COMPRESSION = PAGE);

GO

GRANT SELECT, INSERT, UPDATE, DELETE ON bodb_Report.dbo.BetBuilder_BetHistoryAutomail TO bodbAdminNet;