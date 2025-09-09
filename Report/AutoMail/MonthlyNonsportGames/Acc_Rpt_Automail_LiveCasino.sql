/*<info serverAlias="DBACC-bodb02" executers="wsv_nap,dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

CREATE PROCEDURE [dbo].[Acc_Rpt_Automail_MonthlyLiveCasino]
	@FromDate    DATE,
	@ToDate      DATE
AS
/*
    Created	: 20250909
	Task	: Monthly Nonsport Games (#231176)
	DB		: DBACC/bodb02
	
	Revision:		
		20250909@Cherry: Initial (convert from script adhoc #231176 to SP)

	Param's Explanation:
*/ 
BEGIN

	DECLARE @BalanceUpDay DATE,@MovebetsDay DATE 
	CREATE TABLE #Movebets (BalanceUpDay DATE, MovebetsDay DATE)
	INSERT INTO #Movebets (BalanceUpDay, MovebetsDay)
	EXEC bodb02.dbo.Age_SelBalanceUpDay

	SELECT @BalanceUpDay = BalanceUpDay,
			@MovebetsDay = MovebetsDay
	FROM #Movebets
 
	CREATE TABLE #Data (srecommend INT, productID INT, bettype INT, CustId INT,  
			 BetCount INT, CurrencyId INT, Currency NVARCHAR(50),
			 TableCode NVARCHAR(50), winlostdate date, betfrom NVARCHAR(10)
			 )
			 
	CREATE TABLE #tbl_betfrom (betfrom VARCHAR(5), fullname VARCHAR(200), DeviceGroup VARCHAR(50))

	INSERT INTO #tbl_betfrom (betfrom, fullname, DeviceGroup)
	SELECT betfrom, fullname, DeviceGroup
	FROM DBDW.bodb_account.dbo.tbl_betfrom WITH (NOLOCK)

	CREATE TABLE #tmpCasino (productid INT, sportname NVARCHAR(100), refid NVARCHAR(50))

	INSERT INTO #tmpCasino (productid, sportname, refid)
	VALUES
		(129, N'Playtech Live', N'PTL_BB'),
		(136, N'W Casino', N'WLC_BC'),
		(138, N'ON Casino', N'ON_BT'),
		(176, N'FGG', N'FGG_GN'),
		(228, N'WE Live Casino', N'WE_BT'),
		(211, N'Allbet', N'TableCode'),
		(159, N'YeeBet', N'TableCode'),
		(233, N'WM', N'TableCode'),
		(242, N'IBCBet Live Casino', N'TableCode'),
		(243, N'AE Sexy', N'TableCode'),
		(244, N'SA Gaming', N'TableCode')

	INSERT INTO #Data (srecommend, productID, bettype, CustId, BetCount, CurrencyId, TableCode, winlostdate, betfrom)    
	SELECT  srecommend, productID, gameID, CustID AS CustID,  
			COUNT(CASE WHEN StatusID IN (111,112,113) THEN TransId ELSE NULL END) AS BetCount, Currency,
			CASE WHEN transdesc like '%tableCode%' THEN
				CASE WHEN CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) = 0
					THEN RIGHT(transdesc, LEN(transdesc) - CHARINDEX('tableCode=', transdesc) - 9)
				ELSE SUBSTRING(transdesc, CHARINDEX('tableCode=', transdesc) + 10,
							CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) 
							- (CHARINDEX('tableCode=', transdesc) + 10))
				END
			 ELSE '' END AS TableCode,
		 winlostdate, betfrom
	FROM  dbo.BettransLC WITH (NOLOCK)  
	WHERE WinlostDate > @MovebetsDay AND  WinlostDate <= @todate
		AND WinlostDate >= @FromDate
		AND currency <> 20
	    AND statusID IN (111, 112, 113)   
	GROUP BY  Currency, CustID, srecommend, gameID, productID,
		 CASE WHEN transdesc like '%tableCode%' THEN
			CASE WHEN CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) = 0
				THEN RIGHT(transdesc, LEN(transdesc) - CHARINDEX('tableCode=', transdesc) - 9)
			ELSE SUBSTRING(transdesc, CHARINDEX('tableCode=', transdesc) + 10,
					CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) 
					- (CHARINDEX('tableCode=', transdesc) + 10))
			END
		 ELSE '' END,
		 winlostdate, betfrom
	
	INSERT INTO #Data (srecommend, productID, bettype, CustId, BetCount, CurrencyId, TableCode, winlostdate, betfrom)  
	SELECT srecommend, productID, gameID, CustID,  
		COUNT(CASE WHEN StatusID IN (111,112,113) THEN TransId ELSE NULL END) AS BetCount, Currency,
	    CASE WHEN transdesc like '%tableCode%' THEN
			CASE WHEN CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) = 0
				THEN RIGHT(transdesc, LEN(transdesc) - CHARINDEX('tableCode=', transdesc) - 9)
			ELSE SUBSTRING(transdesc, CHARINDEX('tableCode=', transdesc) + 10,
				CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) 
				 - (CHARINDEX('tableCode=', transdesc) + 10))
			END
		ELSE '' END AS tableCode,
		winlostdate, betfrom
	FROM  dbo.BettransLC14 WITH (NOLOCK)  
	WHERE winlostdate BETWEEN @BalanceUpDay AND @ToDate   
		AND winlostdate BETWEEN @FromDate AND @ToDate
	    AND statusID IN (111, 112, 113)   
	    AND currency <> 20
	GROUP BY  Currency, CustID, srecommend, gameID, productID,
		 CASE WHEN transdesc like '%tableCode%' THEN
			CASE WHEN CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) = 0
				THEN RIGHT(transdesc, LEN(transdesc) - CHARINDEX('tableCode=', transdesc) - 9)
			ELSE SUBSTRING(transdesc, CHARINDEX('tableCode=', transdesc) + 10,
				CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) 
				 - (CHARINDEX('tableCode=', transdesc) + 10))
			END
		ELSE '' END,
		winlostdate, betfrom

	WHILE @FromDate < @BalanceUpDay
	BEGIN
	   INSERT INTO #Data (srecommend, productID, bettype, CustId, BetCount, CurrencyId, tableCode, winlostdate, betfrom)    
	   SELECT  srecommend, productID, gameID, CustID,  
			COUNT(CASE WHEN StatusID IN (111,112,113) THEN TransId ELSE NULL END) AS BetCount, Currency,
			CASE WHEN transdesc like '%tableCode%' THEN
				CASE WHEN CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) = 0
					THEN RIGHT(transdesc, LEN(transdesc) - CHARINDEX('tableCode=', transdesc) - 9)
				ELSE SUBSTRING(transdesc, CHARINDEX('tableCode=', transdesc) + 10,
					CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) 
					- (CHARINDEX('tableCode=', transdesc) + 10))
				END
			ELSE '' END AS tableCode,
			winlostdate, betfrom
	  FROM  bodb_archive.dbo.BettransLC_bk WITH (NOLOCK)  
	  WHERE  WinlostDate = @fromdate
			AND AND WinlostDate <= @ToDate
			AND statusID IN (111, 112, 113)   
			AND currency <> 20
	  GROUP BY  Currency, CustID, srecommend, gameID, productID,
			CASE WHEN transdesc like '%tableCode%' THEN
				CASE WHEN CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) = 0
					THEN RIGHT(transdesc, LEN(transdesc) - CHARINDEX('tableCode=', transdesc) - 9)
				ELSE SUBSTRING(transdesc, CHARINDEX('tableCode=', transdesc) + 10,
					CHARINDEX('*', transdesc + '*', CHARINDEX('tableCode=', transdesc)) 
					- (CHARINDEX('tableCode=', transdesc) + 10))
				END
			ELSE '' END,
			winlostdate, betfrom

	  SELECT @FromDate = DATEADD(DAY,1,@FromDate)

	END 

	CREATE TABLE #Data_Final
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

	INSERT INTO #Data_Final
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
	SELECT  YEAR(winlostdate) [Year],
		MONTH(winlostdate) [Month],
		s.SportName [Product Name],
		bt.typenamee [Game Type],
		CASE WHEN ca.refid = 'tablecode' THEN b.tableCode ELSE isnull(re.resource_en,'') END [Table],
		bf.devicegroup [Device Type],
		bf.fullname [Device Name],
		CASE WHEN su.custid IS NOT NULL THEN 'Licensee' ELSE 'Credit' END [Site Group],
		SUM(b.BetCount) AS BetCount   
	FROM #Data b   
		INNER JOIN dbo.sports s WITH (NOLOCK) ON s.SportType = b.productID
		INNER JOIN dbo.bettype bt WITH (NOLOCK) ON bt.typeid = b.bettype
		LEFT JOIN #tbl_betfrom bf ON bf.betfrom = b.betfrom
		LEFT JOIN #tmpCasino ca ON ca.productid = b.productID
		LEFT JOIN  dbo.Refresource re WITH (NOLOCK) ON re.refid = ca.refid AND b.tableCode = re.Resourceid 
		LEFT JOIN dbo.Dep_CustSuper su WITH (NOLOCK) ON su.custid = b.srecommend
	GROUP BY MONTH(winlostdate),
		YEAR(winlostdate),
		s.SportName,
		bt.typenamee,
		CASE WHEN ca.refid = 'tablecode' THEN b.tableCode ELSE isnull(re.resource_en,'') END,
		bf.devicegroup, 
		bf.fullname,
		CASE WHEN su.custid IS NOT NULL THEN 'Licensee' ELSE 'Credit' END 
	ORDER BY YEAR(winlostdate),
		MONTH(winlostdate),
		s.SportName,
		bt.typenamee, 
		CASE WHEN ca.refid = 'tablecode' THEN b.tableCode ELSE isnull(re.resource_en,'') END,
		bf.devicegroup, 
		bf.fullname,
		CASE WHEN su.custid IS NOT NULL THEN 'Licensee' ELSE 'Credit' END 

	UPDATE yt
	SET [Site Group] = 'Both'
	FROM #Data_Final yt
	WHERE EXISTS (
		SELECT 1 
		FROM #Data_Final x 
		WHERE	 x.[Year] = yt.[Year] 
			AND	 x.[Month] = yt.[Month]
			AND	 x.[Game Type] = yt.[Game Type]
			AND x.[Product Name] = yt.[Product Name]
			AND x.[Table] = yt.[Table]
			AND x.[Device Type] = yt.[Device Type]
			AND x.[Device Name] = yt.[Device Name]
			AND x.[Site Group] = 'Credit'
	)
	AND EXISTS (
		SELECT 1 
		FROM #Data_Final x 
		WHERE	 x.[Year] = yt.[Year] 
			AND	 x.[Month] = yt.[Month]
			AND	 x.[Game Type] = yt.[Game Type]
			AND x.[Product Name] = yt.[Product Name]
			AND x.[Table] = yt.[Table]
			AND x.[Device Type] = yt.[Device Type]
			AND x.[Device Name] = yt.[Device Name]
			AND x.[Site Group] = 'Licensee'
	)

	SELECT [Year],
		[Month],
		[Product Name],
		[Game Type],
		[Table],
		[Device Type],
		[Device Name],
		[Site Group],
		SUM(BetCount) [BetCount]
	FROM #Data_Final
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

	DROP TABLE #Movebets
	DROP TABLE #Data
	DROP TABLE #tbl_betfrom
	DROP TABLE #tmpCasino
	DROP TABLE #Data_Final

END