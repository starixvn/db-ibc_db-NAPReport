/*<info serverAlias="DBWH-bodb_dwrs" executers="wsv_nap,dwrs" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_NonsportGames]
	@FromDate    DATE,
	@ToDate      DATE
AS
/*
    Created	: 20250909
	Task	: Monthly Nonsport Games (#231176)
	DB		: DBWH/bodb_dwrs
	
	Revision:		
		20250909@Cherry: Initial (convert from script adhoc #231176 to SP)

	Param's Explanation:
*/ 
BEGIN

	CREATE TABLE #Data
	(	RptYear INT,
		RptMonth INT,
		bettype INT,
		betfromid INT,
		sitegroup NVARCHAR(20),
		Betcount INT
	)

	DECLARE @rptdate DATE, @StartDate DATE, @EndDate DATE
	SELECT @StartDate = @FromDate,
			@EndDate = @ToDate

	WHILE @fromdate <= @todate
	BEGIN
		SELECT @rptdate = DATEADD(DAY,-1,DATEADD(MONTH,1,@fromdate))
		INSERT INTO #Data (RptYear, RptMonth, bettype, betfromid, sitegroup, Betcount)
		SELECT YEAR(rptdate),
			MONTH(rptdate),
			bettype,
			betfromid,
			CASE WHEN s.isDeposit = 1 THEN 'Licensee' ELSE 'Credit' END, 
			SUM(betcount)
		FROM bodb_Account.dbo.FactCustNonSportDaily b WITH (NOLOCK)
			INNER JOIN bodb_account.dbo.tbl_Site s WITH (NOLOCK) ON b.SiteID = s.siteid
		WHERE rptdate BETWEEN @fromdate AND @rptdate
			AND CurrencyID <> 20
			AND TicketStatus <> 14
		GROUP BY YEAR(rptdate),
				MONTH(rptdate), 
				bettype, 
				betfromid, 
				CASE WHEN s.isDeposit = 1 THEN 'Licensee' ELSE 'Credit' END
		  
		SELECT @fromdate = DATEADD(DAY,1,@rptdate)
	END

	UPDATE yt
	SET sitegroup = 'Both'
	FROM #Data yt
	WHERE EXISTS (
		SELECT 1 
		FROM #Data x 
		WHERE	 x.RptYear = yt.RptYear 
			AND	 x.RptMonth = yt.RptMonth
			AND	 x.bettype = yt.bettype
			AND  x.betfromid = yt.betfromid
			AND  x.sitegroup = 'Credit'
	)
	AND EXISTS (
		SELECT 1 
		FROM #Data x 
		WHERE	 x.RptYear = yt.RptYear 
			AND	 x.RptMonth = yt.RptMonth
			AND	 x.bettype = yt.bettype
			AND  x.betfromid = yt.betfromid
			AND  x.sitegroup = 'Licensee'
	)

	SELECT 
		RptYear [Year],
		RptMonth [Month],
		s.ProductCategory ProductGroup,
		p.ProductName,
		bt.typenamee BettypeName,
		bf.DeviceGroup [Device Type],
		bf.fullname [Device Name],
		b.sitegroup [Site Group],
		SUM(Betcount) Betcount
	FROM #Data b
		LEFT JOIN bodb_Account.dbo.NonSportSetting s WITH (NOLOCK) ON b.bettype = s.Bettype
		LEFT JOIN bodb_Account.dbo.tbl_Betfrom bf WITH (NOLOCK) ON bf.betfromid = b.betfromid
		LEFT JOIN bodb02.dbo.Products p WITH (NOLOCK) ON s.ProductID = p.ProductID
		LEFT JOIN bodb02.dbo.bettype bt WITH (NOLOCK) ON s.Bettype = bt.typeid
	GROUP BY
		RptYear, 
		RptMonth, 
		s.ProductCategory,
		p.ProductName, 
		bt.typenamee,
		bf.DeviceGroup,
		bf.fullname, 
		b.sitegroup 
	ORDER BY 
		RptYear, 
		RptMonth, 
		s.ProductCategory,
		p.ProductName, 
		bt.typenamee,
		bf.DeviceGroup,
		bf.fullname, 
		b.sitegroup 

	-- Live Casino
	CREATE TABLE #LiveCasino
	(	[Year] INT,
		[Month] INT,
		[Product Name] NVARCHAR(100),
		[Game Type] NVARCHAR(200),
		[Table] NVARCHAR(50),
		[Device Type] VARCHAR(50),
		[Device Name] VARCHAR(200),
		[Site Group] VARCHAR(20),
		[BetCount] INT
	)

	INSERT INTO #LiveCasino
	(	[Year],
		[Month],
		[Product Name],
		[Game Type],
		[Table],
		[Device Type],
		[Device Name],
		[Site Group],
		[BetCount] 
	)
	EXEC DBACC.bodb02.dbo.Acc_Rpt_Automail_MonthlyLiveCasino
		@FromDate = @StartDate,
		@ToDate = @EndDate

	SELECT [Year],
		[Month],
		[Product Name],
		[Game Type],
		[Table],
		[Device Type],
		[Device Name],
		[Site Group],
		SUM(BetCount) [BetCount]
	FROM #LiveCasino
	GROUP BY  [Year],
		[Month],
		[Product Name],
		[Game Type],
		[Table],
		[Device Type],
		[Device Name],
		[Site Group]
	ORDER BY [Year],
		[Month],
		[Product Name],
		[Game Type],
		[Table],
		[Device Type],
		[Device Name],
		[Site Group]

	DROP TABLE  #Data
	DROP TABLE  #LiveCasino

END



