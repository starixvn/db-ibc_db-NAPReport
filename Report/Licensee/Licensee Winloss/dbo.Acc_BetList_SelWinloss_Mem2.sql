USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_BetList_SelWinloss_Mem2]    Script Date: 10/12/2015 1:44:48 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_BetList_SelWinloss_Mem2]
	@CustID				INT,
	@CurrencyId			INT				= 0,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@MoveBetsDay		SMALLDATETIME,
	@BalanceUpDay		SMALLDATETIME,
	@ShowSB				BIT				= 1,
	@ShowRB				BIT				= 0,
	@ShowNG				BIT				= 0,
	@ShowBA				BIT				= 0,
	@ShowLC				BIT				= 0,
	@ShowVS				BIT				= 0,
	@ShowCS				BIT				= 0, -- RNG Casino
	@ShowKN				BIT				= 0, -- Keno
	@ShowGD				BIT				= 0, -- Gold Deluxe
	@ShowMGC			BIT				= 0, -- MicroGamming
	@ShowAGC			BIT				= 0, -- AG Casino
	@BaseCurrency		TINYINT			= 0,
	@TotalRows			INT				= 0 OUTPUT,
	@SumWinlost			MONEY			= 0 OUTPUT,
	@SumWinlostUSD		MONEY			= 0 OUTPUT,
	@SumWinlostEUR		MONEY			= 0 OUTPUT,
	@SumLicenseeWL		MONEY			= 0 OUTPUT,
	@SumLicenseeWLUSD	MONEY			= 0 OUTPUT,
	@SumLicenseeWLEUR	MONEY			= 0 OUTPUT,
	@SumComm			MONEY			= 0 OUTPUT,
	@SumCommUSD			MONEY			= 0 OUTPUT,
	@SumCommEUR			MONEY			= 0 OUTPUT,
	@SumPlayerComm		MONEY			= 0 OUTPUT,
	@SumPlayerCommUSD	MONEY			= 0 OUTPUT,
	@SumPlayerCommEUR	MONEY			= 0 OUTPUT,
	@drawfilter			SMALLINT		= 1,
	@Language			VARCHAR(10)		= 'en-us'  
AS

/*
	Created: Henry 
	Date: 2011-07-11
	Task : Betlist for Licensee Winloss Report
	DB: DBACC/bodb02

	Revisions:
		- 20110729@Henry: offer 3 new bettypes for Number Game + Combination Mixed Parlay
		- 20111208@Jim: change condition bettype<31 
		- 20120214@Jim: change to use  table ExchangeDaily by use function Lrf_f_GetExchangeDaily_xtest
		- 20120319@Henry: show main transid for sub-ticket of system parlay
		- 20120508@Jim: enhance query performance 
		- 20120802@Jim: add playercomm value 
		- 20120816@Henry: add ShowLiveCasino 
		- 20120912@Jim : add virtual sport 
		- 20130123@Daniel: Change link server alias
		- 20130527@Jim: support RNG Casino
		- 20130719@Victor: apply betlist core
		- 20130716@Jim: update matchid for RNG Casino and Bingo
		- 20140331@Hannah: offer Keno
		- 20140704@Jim: support sporting solution
		- 20140909@Jim: retrict Virtual Horse Racing bettype
		- 20141205@Winnie: change from LicenseeCust to f_SelLicenseeCust, from DepCustSuper to f_SelDepCustSuper ( task change currency KeenOcean)
		- 20150123@Jim: support base on GBP currency
		- 20150414@Sophia: Support Sporttype Bettype Matrix and Bet Radar
		- 20150506@Tom: Support Gold Deluxe Product [#34847]
		- 20150506@Bobby: Add transdesc column for metric gaming bettypes (801-899)
		- 20150729@Edward: Support Microgaming and Exclude 3 transactions Sold/Bought/BT Comm
		- 20151012@Kos: Support Microgaming RNG Game and AG Casino
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	
	Param's Explanation: 
		+ @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @BaseCurrency : Base currency in Result tables 0: ALL, 1: USD, 2: MYR, 3: EUR ,4:GBP
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #BetListByDateMem (
		Sporttype		INT,
		TransID			BIGINT,
		BetID			BIGINT,
		Bettype			INT,
		hdp1			SMALLMONEY, 
		hdp2			SMALLMONEY, 
		Modds			SMALLMONEY,
		OddsType		TINYINT,
		Odds			SMALLMONEY, 
		Stake			MONEY, 
		Actual_Stake	MONEY,
		Betteam			NVARCHAR(50),
		Status			NVARCHAR(10),
		RefNO			BIGINT,	
		Transdate		DATETIME,
		Winlostdate		DATETIME,
		Winlost			MONEY,
		LicenseeWL		MONEY,
		comm			MONEY,
		playercomm		MONEY,
		Liveindicator	BIT,
		Livehomescore	SMALLINT,
		Liveawayscore	SMALLINT,
		IP				NVARCHAR(15),
		LeagueID		INT,
		MatchID			INT,
		MatchCode		NVARCHAR(50),
		Race			NVARCHAR(20),
		HomeID			INT,
		AwayID			INT, 	
		Betstatus		NVARCHAR(50),
		isNeutral		BIT,
		virtualrate		FLOAT,
		isShowOTExRate	BIT,
		currency		INT,
		showtime		NVARCHAR(50), -- table - shoe - hand of Live Casino
		BetCheck		NVARCHAR(50),
		transdesc		NVARCHAR(300)
	)

	CREATE TABLE  #TempBetList (
		TransID			BIGINT PRIMARY KEY,
		BetID			BIGINT,
		Bettype			INT,
		hdp1			SMALLMONEY, 
		hdp2			SMALLMONEY, 
		Modds			SMALLMONEY,
		OddsType		TINYINT,
		Odds			SMALLMONEY, 
		Stake			MONEY, 
		Actual_Stake	MONEY,
		Betteam			NVARCHAR(50),
		Status			NVARCHAR(10),
		RefNO			BIGINT,	
		Transdate		DATETIME,
		Winlostdate		DATETIME,
		Winlost			MONEY,
		LicenseeWL		MONEY,
		comm			MONEY,
		playercomm		MONEY,
		Liveindicator	BIT,
		Livehomescore	SMALLINT,
		Liveawayscore	SMALLINT,
		IP				NVARCHAR(50),
		currency		INT,
		MatchID			INT,
		BetCheck		NVARCHAR(50),
		transdesc		NVARCHAR(300)
	)

	DECLARE @fdate DATETIME, @tdate DATETIME

	SELECT @fdate = @FromDate, @tdate = @ToDate

	--DECLARE	@currency INT 
	--SELECT	@currency = currency FROM custinfo (NOLOCK) WHERE custid = @custid

	DECLARE @ProductPrefix VARCHAR(100)='-'

	IF @ShowSB	= 1 OR @ShowBA = 1
		BEGIN
			SET @ProductPrefix=@ProductPrefix+',SB'
		END

	IF @showRB	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',RB'
		END

	IF @showNG	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',NG'
		END
		
	IF @ShowLC	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',LC'		
		END
		
	IF @showVS	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',VS'
		END	
		
	IF @ShowCS	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',CS'
		END	
		
	IF @ShowKN	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',KN'
		END	
		
	IF @ShowGD	= 1
		BEGIN	
			SET @ProductPrefix=@ProductPrefix+',GD'
		END	

	IF @ShowMGC = 1
		BEGIN
			SET @ProductPrefix=@ProductPrefix+',MGC'
		END
				
	Declare @TempFromDate DATETIME
	Declare @TempToDate DATETIME

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID TINYINT, Bettype SMALLINT,EventType TINYINT, SubProduct VARCHAR(500))

	INSERT INTO @SportBettype
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode = 5, @ProductPrefix=@ProductPrefix

	DELETE @SportBettype WHERE ProductID = 1 AND Bettype IN (901, 902, 903, 904)

	IF @tdate > @MoveBetsDay
	BEGIN
		IF @fdate <= @MoveBetsDay 
			SET @TempFromDate =  DATEADD(DAY, 1, @MoveBetsDay)
		ELSE
			SET @TempFromDate = @fdate

		IF @ShowBA = 1
		BEGIN
			--Get BA Tickets
			INSERT INTO #TempBetList
			SELECT
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				b.modds,
				b.OddsType,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam, --Betteam
				b.status AS Status,
				b.refno,
				b.Transdate,	
				b.winlostdate,
				(b.winlost-actual_stake),
				0,
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				b.currency,
				b.matchid,
				b.BetCheck,
				b.transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN DBLIC.bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON b.transid = BA.transid
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				b.statusID IN (111,112,113)
		
			--sport book
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				b.BetID,
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				b.modds,
				b.oddstype,
				b.odds,
				b.stake,
				b.actual_stake, 
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				b.Winlost,
				b.LicenseeWL,
				b.comm,	
				b.playercomm, 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,
				0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				CASE WHEN b.bettype BETWEEN 801 AND 899 THEN b.transdesc ELSE '' END AS transdesc 
			FROM
				#TempBetList b
				INNER JOIN dbo.match AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 		
			WHERE 
				s.ProductID = 1 AND
				s.EventType = 1
			--	(b.bettype < 31 OR (b.Bettype BETWEEN 121 AND 999)  OR (b.bettype BETWEEN 1301 AND 1399)) AND
			--	b.bettype <>10
				
			--	Outright
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				b.BetID,
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				b.modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,  
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				b.Winlost,
				b.LicenseeWL,
				b.comm,
				b.playercomm,
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				#TempBetList b		
				INNER JOIN dbo.Outright AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 					
			WHERE
				s.ProductID = 1 AND
				s.EventType = 2
				---b.bettype = 10
					
			--Mix Parlay + System Parlay
			INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN b.bettype <> 29 THEN b.transid
				ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
				END AS transid,	
				b.BetID,
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake, 
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				b.Winlost,
				b.LicenseeWL,
				b.comm,
				b.playercomm,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID	
				'',--MatchCode
				'',--Race
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				#TempBetList b
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				s.ProductID = 1 AND
				s.EventType = 0 AND
				---b.bettype IN (9,29) AND
				b.matchid IN (9,29)
		END

		-- Sport Book
		IF @ShowSB = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				b.OddsType,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,
				0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				CASE WHEN b.bettype BETWEEN 801 AND 899 THEN b.transdesc ELSE '' END AS transdesc 
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.match AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 1 AND
				s.EventType = 1 AND
				--(b.bettype < 31 OR (b.bettype BETWEEN 121 AND 999 ) OR (b.bettype BETWEEN 1301 AND 1399))  AND
				--b.bettype NOT IN (9,29,10)	AND
				b.matchid > 0 AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking<>0
			
			-- Outright
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake, 
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm ,
				b.playercomm , 
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.Outright AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID 
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 1 AND
				s.EventType = 2 AND
				---b.bettype = 10 AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking<>0

			-- Mix Parlay + System Parlay		
			INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN b.bettype <> 29 THEN b.transid
				ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
				END AS transid,	
				ISNULL(b.BetID,0),
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake, 
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID	
				'',--MatchCode
				'',--Race
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans b WITH (NOLOCK)
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 	
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 1 AND
				s.EventType = 0 AND
				---b.bettype IN (9,29) AND
				b.matchid IN (9,29) AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking<>0
		END
		
		-- Number Game
		IF @ShowNG = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,
				0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.match AS m WITH (NOLOCK) ON b.matchid=m.matchid 		
				INNER JOIN @SportBettype s ON s.BetType = b.BetType 
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 3 AND
				---b.bettype BETWEEN 81 AND 120 AND
				b.statusID IN (111,112,113)
		END
		
		--Live Casino
		IF @ShowLC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				ISNULL(m.showtime, '') AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.match AS m WITH (NOLOCK) ON b.matchid=m.matchid 	
				INNER JOIN @SportBettype s ON s.BetType = b.BetType 	
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 4 AND
				---b.bettype BETWEEN 1101 AND 1199 AND
				b.statusID IN (111,112,113)
		END
		
		IF @ShowVS = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)		
				INNER JOIN dbo.match AS m WITH (NOLOCK) ON b.matchid=m.matchid 	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 5 AND 
				s.EventType = 1 AND
				--(b.bettype BETWEEN 1201 AND 1299) AND
				--b.bettype NOT IN (SELECT bettype FROM dbo.f_VSHorseRacingByBettype()) AND
				b.statusID IN (111,112,113)
				
			UNION ALL 
			SELECT 
				r.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				b.comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				r.LeagueID,
				o.EventID MatchID,	
				CONVERT(varchar(50),o.RacerNum) MatchCode,
				b.oddsid  AS Race,	
				o.RacerID HomeID,
				0 AS  AwayID, 		
				r.Betstatus,
				ISNULL(0, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				CONVERT(VARCHAR(20),r.EventTime)  AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM dbo.bettrans AS b WITH (NOLOCK)
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
				INNER JOIN VSOutright o with (nolock) ON b.oddsid=o.Orid
				INNER JOIN VSRaceInfo r WITH (NOLOCK) ON r.EventID = o.EventID	
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 5 AND 
				s.EventType = 3 AND
				----b.bettype IN (SELECT bettype FROM dbo.f_VSHorseRacingByBettype()) AND	
				b.statusID IN (111,112,113)
		END
		
		-- Horse Racing
		IF @ShowRB = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,  
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				awinlost,
				comm ,
				b.playercomm  , 
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				b.virtualrate,
				CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK )		
				INNER JOIN dbo.Outright AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 2 AND 
				---b.bettype IN (31, 32, 33) AND
				b.statusID IN (111,112,113)
		END

		-- RNG Casino
		IF @ShowCS = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				251 Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				71 AS MatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype		
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 6 AND
				---b.bettype =71 AND
				b.statusID IN (111,112,113)
		END

		-- Keno
		IF @ShowKN = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				202 Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				ChoiceId AS betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				GameId AS MMatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype		
				CROSS APPLY dbo.f_ParseTransDesc(b.transdesc, b.bettype)
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 8 AND
				---b.bettype BETWEEN 1501 AND 1599 AND
				b.statusID IN (111,112,113)
		END

		-- Gold Deluxe
		IF @ShowGD = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				255 Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				b.modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				b.MatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 12 AND
				b.statusID IN (111,112,113)
		END

		-- Microgaming
		IF @ShowMGC = 1
		BEGIN
			-- Microgaming - Live Casino
			INSERT INTO #BetListByDateMem
			SELECT
				203 AS Sporttype, 
				b.TransID,
				ISNULL(b.BetID, 0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2,
				0 AS modds,
				0 AS oddstype,
				0 AS Odds,
				b.stake,
				b.actual_stake, 
				'' AS betteam,
				b.status,
				b.refno,
				b.Transdate,
				b.winlostdate,
				(b.winlost - actual_stake),
				- (b.winlost - actual_stake) ,
				b.comm,
				b.playercomm,
				0 AS Liveindicator,
				0 AS Livehomescore,
				0 AS Liveawayscore,
				b.IP,
				0 AS LeagueID,
				0 AS MMatchID,
				0 AS MatchCode,
				'' AS Race,
				0 AS HomeID,
				0 AS AwayID,
				'' AS Betstatus,
				CONVERT(BIT, 0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)
				INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate 
				AND b.custid = @custid 
				AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
				AND s.ProductID = 13 
				AND s.SubProduct <> 'MGC-RNG'
				AND b.statusID IN (111, 112, 113)

			-- Microgaming - RNG Game (up to yesterday settled ticket)
			INSERT INTO #BetListByDateMem
			SELECT
				203 AS Sporttype, 
				b.TransID,
				ISNULL(b.BetID, 0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2,
				0 AS modds,
				0 AS oddstype,
				0 AS Odds,
				b.stake,
				b.actual_stake, 
				'' AS betteam,
				b.status,
				b.refno,
				b.Transdate,
				b.winlostdate,
				(b.winlost - actual_stake),
				- (b.winlost - actual_stake) ,
				b.comm,
				b.playercomm,
				0 AS Liveindicator,
				0 AS Livehomescore,
				0 AS Liveawayscore,
				b.IP,
				0 AS LeagueID,
				0 AS MMatchID,
				0 AS MatchCode,
				'' AS Race,
				0 AS HomeID,
				0 AS AwayID,
				'' AS Betstatus,
				CONVERT(BIT, 0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS showtime,
				'' AS BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)
				INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate 
				AND b.winlostdate <> DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)	-- not today
				AND b.custid = @custid 
				AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
				AND s.ProductID = 13 
				AND s.SubProduct = 'MGC-RNG'
				AND b.statusID IN (111, 112, 113)

			IF @tdate >= DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)
				AND @TempFromDate <= DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)	-- today
			BEGIN
				-- Today settled ticket
				INSERT INTO #BetListByDateMem
				SELECT
					203 AS Sporttype, 
					b.TransID,
					ISNULL(b.BetID, 0),
					b.Bettype,
					0 AS hdp1, 
					0 AS hdp2,
					0 AS modds,
					0 AS oddstype,
					0 AS Odds,
					SUM(brng.stake) AS Stake,
					SUM(brng.actual_stake) AS Actual_Stake, 
					'' AS betteam,
					CASE 
						WHEN SUM(brng.winlost - brng.actual_stake) = 0 THEN 'Draw'
						WHEN SUM(brng.winlost - brng.actual_stake) > 0 THEN 'Won'
						WHEN SUM(brng.winlost - brng.actual_stake) < 0 THEN 'Lose'
					END AS Status,
					b.refno,
					b.Transdate,
					b.winlostdate,
					SUM(brng.winlost - brng.actual_stake) AS Winlost,
					SUM(- (brng.winlost - brng.actual_stake)) AS LicenseeWL,
					SUM(brng.comm) AS comm,
					SUM(brng.playercomm) AS playercomm,
					0 AS Liveindicator,
					0 AS Livehomescore,
					0 AS Liveawayscore,
					b.IP,
					0 AS LeagueID,
					0 AS MMatchID,
					0 AS MatchCode,
					'' AS Race,
					0 AS HomeID,
					0 AS AwayID,
					'' AS Betstatus,
					CONVERT(BIT, 0) AS IsNeutral,
					0,
					0,
					b.currency,
					'' AS showtime,
					'' AS BetCheck,
					'' AS transdesc
				FROM
					dbo.bettransRnG AS brng WITH (NOLOCK)
					INNER JOIN dbo.bettrans AS b WITH (NOLOCK) ON brng.RefNo = b.transid
					INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
				WHERE
					b.winlostdate = DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)	-- today
					AND b.custid = @custid 
					AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
					AND s.ProductID = 13 
					AND s.SubProduct = 'MGC-RNG'
					AND brng.statusID <> 0
				GROUP BY
					b.transid,
					ISNULL(b.BetID, 0),
					b.Bettype,
					b.refno,
					b.transdate,
					b.winlostdate,
					b.IP,
					b.currency
			END
		END

		-- AG Casino
		IF @ShowAGC = 1
		BEGIN
			-- AG Casino (up to yesterday settled ticket)
			INSERT INTO #BetListByDateMem
			SELECT
				250 AS Sporttype, 
				b.TransID,
				ISNULL(b.BetID, 0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2,
				0 AS modds,
				0 AS oddstype,
				0 AS Odds,
				b.stake,
				b.actual_stake, 
				'' AS betteam,
				b.status,
				b.refno,
				b.Transdate,
				b.winlostdate,
				(b.winlost - actual_stake),
				- (b.winlost - actual_stake) ,
				b.comm,
				b.playercomm,
				0 AS Liveindicator,
				0 AS Livehomescore,
				0 AS Liveawayscore,
				b.IP,
				0 AS LeagueID,
				0 AS MMatchID,
				0 AS MatchCode,
				'' AS Race,
				0 AS HomeID,
				0 AS AwayID,
				'' AS Betstatus,
				CONVERT(BIT, 0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS showtime,
				'' AS BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans AS b WITH (NOLOCK)
				INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @TempFromDate AND @tdate 
				AND b.winlostdate <> DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)	-- not today
				AND b.custid = @custid 
				AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
				AND s.ProductID = 11
				AND b.statusID IN (111, 112, 113)

			IF @tdate >= DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)
				AND @TempFromDate <= DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)	-- today
			BEGIN
				-- Today settled ticket
				INSERT INTO #BetListByDateMem
				SELECT
					250 AS Sporttype, 
					b.TransID,
					ISNULL(b.BetID, 0),
					b.Bettype,
					0 AS hdp1, 
					0 AS hdp2,
					0 AS modds,
					0 AS oddstype,
					0 AS Odds,
					SUM(blc.stake) AS Stake,
					SUM(blc.actual_stake) AS Actual_Stake, 
					'' AS betteam,
					CASE 
						WHEN SUM(blc.winlost - blc.actual_stake) = 0 THEN 'Draw'
						WHEN SUM(blc.winlost - blc.actual_stake) > 0 THEN 'Won'
						WHEN SUM(blc.winlost - blc.actual_stake) < 0 THEN 'Lose'
					END AS Status,
					b.refno,
					b.Transdate,
					b.winlostdate,
					SUM(blc.winlost - blc.actual_stake) AS Winlost,
					SUM(- (blc.winlost - blc.actual_stake)) AS LicenseeWL,
					SUM(blc.comm) AS comm,
					SUM(blc.playercomm) AS playercomm,
					0 AS Liveindicator,
					0 AS Livehomescore,
					0 AS Liveawayscore,
					b.IP,
					0 AS LeagueID,
					0 AS MMatchID,
					0 AS MatchCode,
					'' AS Race,
					0 AS HomeID,
					0 AS AwayID,
					'' AS Betstatus,
					CONVERT(BIT, 0) AS IsNeutral,
					0,
					0,
					b.currency,
					'' AS showtime,
					'' AS BetCheck,
					'' AS transdesc
				FROM
					dbo.bettransLC AS blc WITH (NOLOCK)
					INNER JOIN dbo.bettrans AS b WITH (NOLOCK) ON blc.RefNo = b.transid
					INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
				WHERE
					b.winlostdate = DATEADD(DAY, DATEDIFF(DAY, 0, GETDATE()), 0)	-- today
					AND b.custid = @custid 
					AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
					AND s.ProductID = 11
					AND blc.statusID <> 0
				GROUP BY
					b.transid,
					ISNULL(b.BetID, 0),
					b.Bettype,
					b.refno,
					b.transdate,
					b.winlostdate,
					b.IP,
					b.currency
			END
		END
	END

	IF @fdate <= @MoveBetsDay
	BEGIN
		IF @tdate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @tdate
		
		IF @BalanceUpDay < @fdate 
			SELECT @BalanceUpDay=@fdate

		IF @ShowBA = 1
		BEGIN
			--Get BA Tickets
			DELETE FROM #TempBetList

			INSERT INTO #TempBetList
			SELECT
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				b.modds,
				b.OddsType,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				0,
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				b.currency,
				b.matchid,
				b.BetCheck,
				b.transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN DBLIC.bodb_Licensee.dbo.LicenseeBATransaction BA WITH (NOLOCK) ON b.transid = BA.transid
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				b.statusID IN (111,112,113)

			--sport book
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				b.BetID,
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				b.modds,
				b.oddstype,
				b.odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				b.Winlost,
				b.LicenseeWL,
				b.comm,	
				b.playercomm, 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				CASE WHEN b.bettype BETWEEN 801 AND 899 THEN b.transdesc ELSE '' END AS transdesc 
			FROM
				#TempBetList b
				INNER JOIN dbo.match14 AS m WITH (NOLOCK) ON b.matchid=m.matchid 	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
			WHERE 
				s.ProductID = 1 AND
				s.EventType = 1 

			-- Outright
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				b.BetID,
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				b.modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,   
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				b.Winlost,
				b.LicenseeWL,
				b.comm,
				b.playercomm,
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				#TempBetList b		
				INNER JOIN dbo.Outright14 AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 				
			WHERE
				s.ProductID = 1 AND
				s.EventType = 2

			--Mix Parlay + System Parlay
			INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN b.bettype <> 29 THEN b.transid
				ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
				END AS transid,	
				b.BetID,
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				b.Winlost,
				b.LicenseeWL,
				b.comm,
				b.playercomm,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID	
				'',--MatchCode
				'',--Race
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				#TempBetList b
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				s.ProductID = 1 AND
				s.EventType = 0 AND
				b.matchid IN (9,29) 
		END

		-- Sportsbook
		IF @ShowSB = 1
		BEGIN	
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm  ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	--Race
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				CASE WHEN b.bettype BETWEEN 801 AND 899 THEN b.transdesc ELSE '' END AS transdesc 
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN dbo.match14 AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 1 AND
				s.EventType = 1 AND
				--(b.bettype < 31 OR (b.bettype BETWEEN 121 AND 999 ) OR (b.bettype BETWEEN 1301 AND 1399)) AND
				--b.bettype NOT IN (9,29,10) AND
				b.matchid>0 AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking<>0

			-- Mix Parlay + System Parlay
			INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN b.bettype <> 29 THEN b.transid
				ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
				END AS transid,	
				ISNULL(b.BetID,0),
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,   
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm ,
				b.playercomm  ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID
				'',--MatchCode
				'',--Race	
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS isNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 1 AND
				s.EventType = 0 AND
				---b.bettype IN (9,29) AND
				b.matchid IN (9,29) AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking<>0
				
			--outright
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,  
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm ,
				b.playercomm ,
				0 AS LiveIndicator, 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch AS Race,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS isNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN dbo.Outright14 AS m WITH (NOLOCK) ON b.matchid=m.orid 
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 1 AND
				s.EventType = 2 AND
				---b.bettype = 10 AND
				b.statusID IN (111,112,113) AND
				b.tpositiontaking<>0
		END
		
		-- Number Game
		IF @ShowNG = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,
				b.betteam,
				b.status AS Status,
				b.refno,
				b.Transdate,	
				b.winlostdate,
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN dbo.match14 AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 3 AND 
				---(b.bettype BETWEEN 81 AND 120) AND
				b.statusID IN (111,112,113)
		END
		
		-- Live Casino
		IF @ShowLC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,
				b.betteam,
				b.status AS Status,
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				ISNULL(m.showtime, '') AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN dbo.match14 AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 4 AND
				---b.bettype BETWEEN 1101 AND 1199 AND
				b.statusID IN (111,112,113)
		END
		
		IF @ShowVS = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,   		
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN dbo.match14 AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 5 AND
				s.EventType = 1 AND
				--( b.bettype BETWEEN 1201 AND 1299) AND
				--b.bettype NOT IN (SELECT bettype FROM dbo.f_VSHorseRacingByBettype()) AND	
				b.statusID IN (111,112,113)
			UNION ALL 
			SELECT 
				r.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.oddstype,
				b.Odds,
				b.stake,
				b.actual_stake, 
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake) ,
				b.comm,
				b.playercomm  , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				r.LeagueID,
				o.EventID MatchID,	
				CONVERT(varchar(50),o.RacerNum) MatchCode,
				b.oddsid  AS Race,	
				o.RacerID HomeID,
				0 AS  AwayID, 		
				r.Betstatus,
				ISNULL(0, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				CONVERT(VARCHAR(20),r.EventTime)  AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM dbo.bettrans14 AS b WITH (NOLOCK)	
				INNER JOIN VSOutright14 o with (nolock) ON b.oddsid=o.Orid
				INNER JOIN VSRaceInfo r WITH (NOLOCK) ON r.EventID = o.EventID	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 5 AND 
				s.EventType = 3 AND 
				--b.bettype IN (SELECT bettype FROM dbo.f_VSHorseRacingByBettype()) AND	
				b.statusID IN (111,112,113)
		END

		-- RNG Casino 
		IF @ShowCS = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				251 AS Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,   		
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				0 AS MatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 6 AND 
				--b.bettype =71 AND
				b.statusID IN (111,112,113)
		END

		-- Keno
		IF @ShowKN = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				202 AS Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,   		
				ChoiceID AS betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				GameId AS MatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
				CROSS APPLY dbo.f_ParseTransDesc(b.transdesc, b.bettype)	
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 8 AND
				b.statusID IN (111,112,113)
		END

		-- Horse Racing
		IF @ShowRB = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,   
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				awinlost,
				comm ,
				b.playercomm,
				0 AS LiveIndicator, 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch AS Race,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS isNeutral,
				b.virtualrate,
				CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)		
				INNER JOIN dbo.Outright14 AS m WITH (NOLOCK) ON b.matchid=m.orid 
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 2 AND
				b.statusID IN (111,112,113)
		END
		
		-- Gold Deluxe
		IF @ShowGD = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				255 AS Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				b.modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,   		
				b.betteam,
				b.status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				b.MatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)	
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 12 AND
				b.statusID IN (111,112,113)
		END

		-- Microgaming
		IF @ShowMGC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				203 AS Sporttype,
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				0 AS hdp1,
				0 AS hdp2,
				0 AS modds,
				0 AS Oddstype,
				0 AS Odds,
				b.stake,
				b.actual_stake,
				'' AS betteam,
				b.status,
				b.refno,
				b.Transdate,
				b.winlostdate,
				(b.winlost - actual_stake),
				- (b.winlost - actual_stake),
				b.comm,
				b.playercomm ,
				0 AS Liveindicator,
				0 AS Livehomescore,
				0 AS Liveawayscore,
				b.IP,
				0 AS LeagueID,
				0 AS MatchID,
				0 AS MatchCode,
				'' AS Race,
				0 AS HomeID,
				0 AS AwayID,
				'' AS Betstatus,
				CONVERT(BIT, 0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS showtime,
				CASE
					WHEN s.SubProduct = 'MGC-RNG' THEN ''
					ELSE b.BetCheck
				END AS BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)
				INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate 
				AND b.custid = @custid 
				AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
				AND s.ProductID = 13 
				AND b.statusID IN (111, 112, 113)
		END

		-- AG Casino
		IF @ShowAGC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				250 AS Sporttype,
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				0 AS hdp1,
				0 AS hdp2,
				0 AS modds,
				0 AS Oddstype,
				0 AS Odds,
				b.stake,
				b.actual_stake,
				'' AS betteam,
				b.status,
				b.refno,
				b.Transdate,
				b.winlostdate,
				(b.winlost - actual_stake),
				- (b.winlost - actual_stake),
				b.comm,
				b.playercomm ,
				0 AS Liveindicator,
				0 AS Livehomescore,
				0 AS Liveawayscore,
				b.IP,
				0 AS LeagueID,
				0 AS MatchID,
				0 AS MatchCode,
				'' AS Race,
				0 AS HomeID,
				0 AS AwayID,
				'' AS Betstatus,
				CONVERT(BIT, 0) AS IsNeutral,
				0,
				0,
				b.currency,
				'' AS showtime,
				'' AS BetCheck,
				'' AS transdesc
			FROM
				dbo.bettrans14 AS b WITH (NOLOCK)
				INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @BalanceUpDay AND @tdate 
				AND b.custid = @custid 
				AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
				AND s.ProductID = 11
				AND b.statusID IN (111, 112, 113)
		END
	END

	IF @fdate < @BalanceUpDay
	BEGIN
		IF @tdate >= DATEADD(dd, -1, @BalanceUpDay)
			SET @TempToDate = DATEADD(dd, -1, @BalanceUpDay)
		ELSE
			SET @TempToDate = @tdate

		IF @ShowBA = 1
		BEGIN
			DELETE FROM #TempBetList
			
			--Get BA Tickets
			INSERT INTO #TempBetList
			SELECT
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				b.modds,
				b.OddsType,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				0,
				comm,
				b.playercomm ,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				b.currency,
				b.matchid,
				b.BetCheck,
				b.transdesc
			FROM
				bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
				INNER JOIN DBLIC.bodb_Licensee.dbo.LicenseeBATransaction BA WITH (NOLOCK) ON b.transid = BA.transid
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				b.ruben = 1 AND
				b.status NOT IN ('VOID','REJECT','REFUND')
		
			--sport book
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				b.BetID,
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				b.modds,
				b.oddstype,
				b.odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				b.Winlost,
				b.LicenseeWL,
				b.comm,	
				b.playercomm,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				CASE WHEN b.bettype BETWEEN 801 AND 899 THEN b.transdesc ELSE '' END AS transdesc 
			FROM
				#TempBetList b
				INNER JOIN bodb_archive.dbo.match_bk AS m WITH (NOLOCK) ON b.matchid=m.matchid
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 		
			WHERE
				s.ProductID = 1 AND
				s.EventType = 1

			--	Outright
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				b.BetID,
				b.Bettype,
				0 AS hdp1, 
				0 AS hdp2, 
				b.modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,  
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				b.Winlost,
				b.LicenseeWL,
				b.comm,
				b.playercomm, 
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				#TempBetList b		
				INNER JOIN bodb_archive.dbo.Outright_bk AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				s.ProductID = 1 AND
				s.EventType = 2

			--Mix Parlay + System parlay
			INSERT INTO #BetListByDateMem
			SELECT
				0, --Sporttype
				CASE WHEN b.bettype <> 29 THEN b.transid
					ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
					END AS transid,	
				b.BetID,
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,   
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				b.Winlost,
				b.LicenseeWL,
				b.comm,
				b.playercomm,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0, --LeagueID
				0, --MatchID	
				'',--MatchCode
				'',--Race
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				#TempBetList b
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
			WHERE
				s.ProductID = 1 AND
				s.EventType = 0 AND
				b.matchid IN (9,29)
		END
			
		--Sport Book
		IF @ShowSB = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,  
				b.betteam, --Betteam
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm,
				b.playercomm,
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' AS Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
				0,0,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				CASE WHEN b.bettype BETWEEN 801 AND 899 THEN b.transdesc ELSE '' END AS transdesc 
			FROM
				bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
				INNER JOIN bodb_archive.dbo.match_BK AS m WITH (NOLOCK) ON b.matchid=m.matchid  
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				b.ruben = 1 AND
				b.status NOT IN ('VOID', 'REJECT', 'REFUND') AND 
				s.ProductID = 1 AND
				s.EventType = 1 AND
				--(b.bettype < 31 OR (b.bettype BETWEEN 121 AND 999 ) OR (b.bettype BETWEEN 1301 AND 1399)) AND
				--b.bettype NOT IN (9,29, 10) AND
				b.tpositiontaking<>0

			-- Outright
			INSERT INTO #BetListByDateMem
				SELECT
					l.sporttype, --Sporttype
					b.TransID,
					ISNULL(b.BetID,0),
					b.Bettype,
					0 AS hdp1, 
					0 AS hdp2, 
					modds,
					0 AS OddsType, 
					b.Odds, 
					b.stake,
					b.actual_stake,  
					'' AS Betteam, --Betteam
					b.Status,				
					b.refno,
					b.Transdate,	
					b.winlostdate,						
					(b.winlost-actual_stake),
					- (b.winlost-actual_stake),
					comm,
					b.playercomm, 
					0 AS LiveIndicator , 
					b.LiveHomescore, 
					b.LiveAwayscore,
					b.IP AS IP,
					m.LeagueID,
					m.OrId,--0, --MatchID	
					m.MatchCode,
					m.GroupMatch,--Race
					m.TeamID, --HomeID
					0, --AwayID		
					0, --Betstatus
					CONVERT(BIT,0) AS IsNeutral,
					0,0,
					b.currency,
					'' As ShowTime,
					b.BetCheck,
					'' AS transdesc
				FROM
					bodb_archive.dbo.bettrans_bk  AS b WITH (NOLOCK)		
					INNER JOIN bodb_archive.dbo.Outright_bk AS m WITH (NOLOCK) ON b.matchid=m.orid
					INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID
					INNER JOIN @SportBettype s ON s.Bettype = b.bettype 
				WHERE
					b.winlostdate BETWEEN @fdate AND @TempToDate AND
					b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
					b.ruben = 1 AND
					b.status NOT IN ('VOID', 'REJECT', 'REFUND') AND 
					s.ProductID = 1 AND
					s.EventType = 2 AND
					---b.bettype = 10 AND
					b.tpositiontaking<>0

			-- Mix Parlay	+ System Parlay	
			INSERT INTO #BetListByDateMem
				SELECT
					0, --Sporttype
					CASE WHEN b.bettype <> 29 THEN b.transid
					ELSE CASE WHEN ISNULL(b.BetID,0)=0 THEN b.transid ELSE betid END
					END AS transid,	
					ISNULL(b.BetID,0),
					b.bettype,
					b.hdp1, 
					b.hdp2, 
					modds,
					0 AS OddsType, 
					b.Odds, 
					b.stake,
					b.actual_stake,   
					b.betteam, --Betteam
					b.Status,				
					b.refno,
					b.Transdate,	
					b.winlostdate,						
					(b.winlost-actual_stake),
					 - (b.winlost-actual_stake) ,
					comm ,
					b.playercomm, 
					b.Liveindicator,
					b.Livehomescore,
					b.Liveawayscore,
					b.IP AS IP,
					0, --LeagueID
					0, --MatchID	
					'',--MatchCode
					'',--Race
					0, --HomeID
					0, --AwayID		
					0, --Betstatus
					CONVERT(BIT,0) AS IsNeutral,
					0,0,
					b.currency,
					'' As ShowTime,
					b.BetCheck,
					'' AS transdesc
				FROM
					bodb_archive.dbo.bettrans_bk b WITH (NOLOCK)
					INNER JOIN @SportBettype s ON s.Bettype = b.bettype 	
				WHERE
					b.winlostdate BETWEEN @fdate AND @TempToDate AND
					b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
					b.ruben = 1 AND 
					b.status NOT IN ('VOID', 'REJECT','REFUND') AND
					s.ProductID = 1 AND
					s.EventType = 0 AND
					---b.bettype IN (9,29) AND		
					b.matchid IN (0,9,29) AND --should NOT remove 0 IN archive
					b.tpositiontaking<>0
		END
		
		--Number game
		IF @ShowNG = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			m.Sporttype, 
			b.TransID,
			ISNULL(b.BetID,0),
			b.Bettype,
			b.hdp1 AS hdp1, 
			b.hdp2 AS hdp2,
			modds,
			b.Oddstype,
			b.Odds,
			b.stake,
			b.actual_stake,  		
			b.betteam,
			b.status AS Status,				
			b.refno,
			b.Transdate,	
			b.winlostdate,			
			(b.winlost-actual_stake),
			- (b.winlost-actual_stake),
			comm ,
			b.playercomm , 
			b.Liveindicator,
			b.Livehomescore,
			b.Liveawayscore,
			b.IP AS IP,
			m.LeagueID,
			m.MatchID,	
			m.MatchCode,
			'' AS Race,	
			m.HomeID,
			m.AwayID, 		
			m.Betstatus,
			ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
			0,0,
			b.currency,
			'' As ShowTime,
			b.BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
			INNER JOIN bodb_archive.dbo.match_BK AS m WITH (NOLOCK) ON b.matchid=m.matchid  
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate AND
			b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
			s.ProductID = 3 AND
			b.ruben = 1 AND
			b.status NOT IN ('VOID', 'REJECT', 'REFUND')
		END
		
		--Live Casino
		IF @ShowLC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			m.Sporttype, 
			b.TransID,
			ISNULL(b.BetID,0),
			b.Bettype,
			b.hdp1 AS hdp1, 
			b.hdp2 AS hdp2,
			modds,
			b.Oddstype,
			b.Odds,
			b.stake,
			b.actual_stake,  		
			b.betteam,
			b.status AS Status,				
			b.refno,
			b.Transdate,	
			b.winlostdate,			
			(b.winlost-actual_stake),
			- (b.winlost-actual_stake),
			comm ,
			b.playercomm , 
			b.Liveindicator,
			b.Livehomescore,
			b.Liveawayscore,
			b.IP AS IP,
			m.LeagueID,
			m.MatchID,	
			m.MatchCode,
			'' AS Race,	
			m.HomeID,
			m.AwayID, 		
			m.Betstatus,
			ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
			0,0,
			b.currency,
			ISNULL(m.showtime, '') AS showtime,
			b.BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
			INNER JOIN bodb_archive.dbo.match_BK AS m WITH (NOLOCK) ON b.matchid=m.matchid  
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate AND
			b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
			s.ProductID = 4 AND
			b.ruben = 1 AND
			b.status NOT IN ('VOID', 'REJECT', 'REFUND')
		END
		
		IF @ShowVS = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			m.Sporttype, 
			b.TransID,
			ISNULL(b.BetID,0),
			b.Bettype,
			b.hdp1 AS hdp1, 
			b.hdp2 AS hdp2,
			modds,
			b.Oddstype,
			b.Odds,
			b.stake,
			b.actual_stake,  		
			b.betteam,
			b.status AS Status,				
			b.refno,
			b.Transdate,	
			b.winlostdate,			
			(b.winlost-actual_stake),
			- (b.winlost-actual_stake),
			comm ,
			b.playercomm , 
			b.Liveindicator,
			b.Livehomescore,
			b.Liveawayscore,
			b.IP AS IP,
			m.LeagueID,
			m.MatchID,	
			m.MatchCode,
			'' AS Race,	
			m.HomeID,
			m.AwayID, 		
			m.Betstatus,
			ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral,
			0,0,
			b.currency,
			'' AS showtime,
			b.BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
			INNER JOIN bodb_archive.dbo.match_BK AS m WITH (NOLOCK) ON b.matchid=m.matchid  
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate AND
			b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
			s.ProductID = 5 AND 
			s.EventType = 1 AND 
			b.ruben = 1 AND
			b.status NOT IN ('VOID', 'REJECT', 'REFUND')
			
		UNION ALL 
		SELECT 
			r.Sporttype, 
			b.TransID,
			ISNULL(b.BetID,0),
			b.Bettype,
			b.hdp1 AS hdp1, 
			b.hdp2 AS hdp2,
			modds,
			b.oddstype,
			b.Odds,
			b.stake,
			b.actual_stake, 
			b.betteam,
			b.status AS Status,				
			b.refno,
			b.Transdate,	
			b.winlostdate,			
			(b.winlost-actual_stake),
			- (b.winlost-actual_stake) ,
			b.comm,
			b.playercomm  , 
			b.Liveindicator,
			b.Livehomescore,
			b.Liveawayscore,
			b.IP AS IP,
			r.LeagueID,
			o.EventID MatchID,	
			CONVERT(varchar(50),o.RacerNum) MatchCode,
			b.oddsid  AS Race,	
			o.RacerID HomeID,
			0 AS  AwayID, 		
			r.Betstatus,
			ISNULL(0, CONVERT(BIT,0)) AS IsNeutral,
			0,0,
			b.currency,
			CONVERT(VARCHAR(20),r.EventTime)  AS showtime,
			b.BetCheck,
			'' AS transdesc
		FROM bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)	
			INNER JOIN DBARC.bodb_Archive.dbo.VSOutright_bk o with (nolock) ON b.oddsid=o.Orid
			INNER JOIN VSRaceInfo r WITH (NOLOCK) ON r.EventID = o.EventID	
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate AND
			b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
			s.ProductID = 5 AND
			s.EventType = 3 AND 
			b.statusID IN (111,112,113)
		END

		-- RNG Casino 
		IF @ShowCS = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			251 Sporttype, 
			b.TransID,
			ISNULL(b.BetID,0),
			b.Bettype,
			b.hdp1 AS hdp1, 
			b.hdp2 AS hdp2,
			modds,
			b.Oddstype,
			b.Odds,
			b.stake,
			b.actual_stake,  		
			b.betteam,
			b.status AS Status,				
			b.refno,
			b.Transdate,	
			b.winlostdate,			
			(b.winlost-actual_stake),
			- (b.winlost-actual_stake),
			comm ,
			b.playercomm , 
			b.Liveindicator,
			b.Livehomescore,
			b.Liveawayscore,
			b.IP AS IP,
			0 AS LeagueID,
			0 AS MatchID,	
			0 AS MatchCode,
			'' AS Race,	
			0 AS HomeID,
			0 AS AwayID, 		
			'' AS Betstatus,
			CONVERT(BIT,0) AS IsNeutral,
			0,0,
			b.currency,
			'' AS showtime,
			b.BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)	
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype	
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate AND
			b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
			s.ProductID = 6 AND
			b.ruben = 1 AND
			b.status NOT IN ('VOID', 'REJECT', 'REFUND')
		END	

		-- Keno
		IF @ShowKN = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			202 Sporttype, 
			b.TransID,
			ISNULL(b.BetID,0),
			b.Bettype,
			b.hdp1 AS hdp1, 
			b.hdp2 AS hdp2,
			modds,
			b.Oddstype,
			b.Odds,
			b.stake,
			b.actual_stake,  		
			ChoiceID AS betteam,
			b.status AS Status,				
			b.refno,
			b.Transdate,	
			b.winlostdate,			
			(b.winlost-actual_stake),
			- (b.winlost-actual_stake),
			comm ,
			b.playercomm , 
			b.Liveindicator,
			b.Livehomescore,
			b.Liveawayscore,
			b.IP AS IP,
			0 AS LeagueID,
			GameId AS MatchID,	
			0 AS MatchCode,
			'' AS Race,	
			0 AS HomeID,
			0 AS AwayID, 		
			'' AS Betstatus,
			CONVERT(BIT,0) AS IsNeutral,
			0,0,
			b.currency,
			'' AS showtime,
			b.BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			CROSS APPLY dbo.f_ParseTransDesc(b.transdesc, b.bettype)
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate AND
			b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
			s.ProductID = 8 AND 
			--b.bettype BETWEEN 1501 AND 1599 AND
			b.ruben = 1 AND
			b.status NOT IN ('VOID', 'REJECT', 'REFUND')
		END	

		-- Racebook
		IF @ShowRB = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				0 AS OddsType, 
				b.Odds, 
				b.stake,
				b.actual_stake,   
				'' AS Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				awinlost,
				comm ,
				b.playercomm,	
				0 AS LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP AS IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) AS IsNeutral,
				b.virtualrate,
				CASE WHEN b.currency2 IS NULL THEN CONVERT(BIT,0) ELSE CONVERT(BIT,1) END,
				b.currency,
				'' As ShowTime,
				b.BetCheck,
				'' AS transdesc
			FROM
				bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
				INNER JOIN bodb_archive.dbo.Outright_bk AS m WITH (NOLOCK) ON b.matchid=m.orid
				INNER JOIN dbo.League AS l WITH (NOLOCK) ON m.leagueID = l.leagueID 
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				b.ruben = 1 AND 
				b.status NOT IN ('VOID','REJECT','REFUND') AND
				s.ProductID = 2
		END	

		-- Gold Deluxe
		IF @ShowGD = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				255 Sporttype, 
				b.TransID,
				ISNULL(b.BetID,0),
				b.Bettype,
				b.hdp1 AS hdp1, 
				b.hdp2 AS hdp2,
				b.modds,
				b.Oddstype,
				b.Odds,
				b.stake,
				b.actual_stake,  		
				b.betteam,
				b.status AS Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				- (b.winlost-actual_stake),
				comm ,
				b.playercomm , 
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP AS IP,
				0 AS LeagueID,
				b.MatchID,	
				0 AS MatchCode,
				'' AS Race,	
				0 AS HomeID,
				0 AS AwayID, 		
				'' AS Betstatus,
				CONVERT(BIT,0) AS IsNeutral,
				0,0,
				b.currency,
				'' AS showtime,
				b.BetCheck,
				'' AS transdesc
			FROM
				bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)		
				INNER JOIN @SportBettype s ON s.Bettype = b.bettype
			WHERE
				b.winlostdate BETWEEN @fdate AND @TempToDate AND
				b.custid=@custid AND (@CurrencyId=0 OR b.currency=@CurrencyId) AND 
				s.ProductID = 12 AND 
				b.ruben = 1 AND
				b.status NOT IN ('VOID', 'REJECT', 'REFUND')
		END

		-- Microgaming
		IF @ShowMGC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			203 AS Sporttype, 
			b.TransID,
			ISNULL(b.BetID, 0),
			b.Bettype,
			0 AS hdp1, 
			0 AS hdp2,
			0 AS modds,
			0 AS Oddstype,
			0 AS Odds,
			b.stake,
			b.actual_stake,
			'' AS betteam,
			b.status,
			b.refno,
			b.Transdate,
			b.winlostdate,
			(b.winlost - actual_stake),
			- (b.winlost - actual_stake),
			b.comm,
			b.playercomm,
			0 AS Liveindicator,
			0 AS Livehomescore,
			0 AS Liveawayscore,
			b.IP,
			0 AS LeagueID,
			0 AS MatchID,
			0 AS MatchCode,
			'' AS Race,
			0 AS HomeID,
			0 AS AwayID,
			'' AS Betstatus,
			CONVERT(BIT,0) AS IsNeutral,
			0,
			0,
			b.currency,
			'' AS showtime,
			CASE
				WHEN s.SubProduct = 'MGC-RNG' THEN ''
				ELSE b.BetCheck
			END AS BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)
			INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate 
			AND b.custid = @custid 
			AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
			AND s.ProductID = 13 
			AND b.statusID IN (111, 112, 113)
		END

		-- AG Casino
		IF @ShowAGC = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
			250 AS Sporttype, 
			b.TransID,
			ISNULL(b.BetID, 0),
			b.Bettype,
			0 AS hdp1, 
			0 AS hdp2,
			0 AS modds,
			0 AS Oddstype,
			0 AS Odds,
			b.stake,
			b.actual_stake,
			'' AS betteam,
			b.status,
			b.refno,
			b.Transdate,
			b.winlostdate,
			(b.winlost - actual_stake),
			- (b.winlost - actual_stake),
			b.comm,
			b.playercomm,
			0 AS Liveindicator,
			0 AS Livehomescore,
			0 AS Liveawayscore,
			b.IP,
			0 AS LeagueID,
			0 AS MatchID,
			0 AS MatchCode,
			'' AS Race,
			0 AS HomeID,
			0 AS AwayID,
			'' AS Betstatus,
			CONVERT(BIT,0) AS IsNeutral,
			0,
			0,
			b.currency,
			'' AS showtime,
			'' AS BetCheck,
			'' AS transdesc
		FROM
			bodb_archive.dbo.bettrans_bk AS b WITH (NOLOCK)
			INNER JOIN @SportBettype AS s ON s.Bettype = b.bettype
		WHERE
			b.winlostdate BETWEEN @fdate AND @TempToDate 
			AND b.custid = @custid 
			AND (@CurrencyId = 0 OR b.currency = @CurrencyId) 
			AND s.ProductID = 11 
			AND b.statusID IN (111, 112, 113)
		END
	END

	--@currency

	SELECT * INTO #TempExchange 
	FROM Lrf_f_GetExchangeDaily (@FDate,@TDate)
	--WHERE exchangeid = @currency

	--exclude draw for no draw option (2)
	DELETE FROM #BetListByDateMem
	WHERE @drawfilter = 2 AND status = 'DRAW' AND ABS(modds) <> 0.25

	SELECT 
		@TotalRows = count(transid),
		@SumWinlost=SUM(ISNULL(winlost,0)),
		@SumLicenseeWL=SUM(ISNULL(LicenseeWL,0)),
		@SumComm=SUM(ISNULL(comm,0)) ,
		@SumPlayerComm=SUM(ISNULL(playercomm,0)),
		--USD
		@SumWinlostUSD=SUM(ISNULL(winlost*e.USD,0)),
		@SumLicenseeWLUSD=SUM(ISNULL(LicenseeWL*e.USD,0)),
		@SumCommUSD=SUM(ISNULL(comm*e.USD,0)) ,
		@SumPlayerCommUSD=SUM(ISNULL(Playercomm*e.USD,0)),
		--EUR
		@SumWinlostEUR=SUM(ISNULL(winlost*e.EUR,0)),
		@SumLicenseeWLEUR=SUM(ISNULL(LicenseeWL*e.EUR,0)),
		@SumCommEUR=SUM(ISNULL(comm*e.EUR,0)) ,
		@SumPlayerCommEUR=SUM(ISNULL(playercomm*e.EUR,0))
	FROM #BetListByDateMem b
		INNER JOIN #TempExchange e 
			ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = b.currency

	-- Update Stake to Base currency
	UPDATE #BetListByDateMem
	SET stake = stake *					(CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
		actual_stake = actual_stake *	(CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
		winlost = winlost *				(CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
		LicenseeWL = LicenseeWL *		(CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
		comm = comm *					(CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
		playercomm = playercomm *		(CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END)
	FROM	#BetListByDateMem d 
			INNER JOIN #TempExchange e 
			ON e.ExchangeDate =  d.winlostdate AND e.exchangeid = d.currency

	-- Final SELECT for 1st result set
	SELECT	d.Sporttype,
			d.TransID,
			d.BetID,
			d.Bettype,
			d.hdp1,
			d.hdp2,
			d.Modds,
			d.OddsType,
			d.Odds,
			d.Stake,
			d.Actual_Stake,
			d.Betteam,
			d.[Status],
			d.RefNO,
			d.Transdate,
			d.Winlostdate AS eventdate,
			d.Winlost,
			d.LicenseeWL,
			d.comm,
			d.playercomm,
			d.Liveindicator,
			d.Livehomescore,
			d.Liveawayscore,
			d.IP,
			d.LeagueID,
			d.MatchID,
			d.MatchCode,
			d.Race,
			d.HomeID,
			d.AwayID, 	
			d.Betstatus,
			d.isNeutral,
			d.virtualrate,
			d.isShowOTExRate,
			d.currency,
			d.showtime,
			0 AS sdiscount,
			0 AS adiscount,
			0 AS discount,
			CAST(0 AS DATETIME) AS settleTime,
			0 AS finalodds,
			0 AS finalodds2,
			0 AS comstatus,
			0 AS spositiontaking,
			0 AS mpositiontaking,
			0 AS apositiontaking,
			0 AS spositiontaking2,
			0 AS mpositiontaking2,
			0 AS apositiontaking2,
			@CustID AS custid,
			NULL AS finalhomescore,
			NULL AS finalawayscore,
			'' AS betfrom,
			0 AS allowdelete,
			0 AS commission,
			0 AS scomm,
			0 AS acomm,
			0 AS awinlost,
			0 AS mwinlost,
			0 AS swinlost,
			d.Winlostdate AS winlostdate,
			d.BetCheck,
			d.transdesc
	FROM	#BetListByDateMem d 
			INNER JOIN #TempExchange e 
			ON e.ExchangeDate =  d.winlostdate AND e.exchangeid = d.currency
	ORDER BY TransID 

	DECLARE @BettransDetail TABLE(  
		refno BIGINT,  
		odds SMALLMONEY,  
		stake MONEY,
		status NVARCHAR(10),  
		apositiontaking SMALLMONEY,  
		mpositiontaking SMALLMONEY,
		spositiontaking SMALLMONEY,
		bettype SMALLINT,
		Betteam NVARCHAR (10),
		BetCheck NVARCHAR(50),
		TransDesc		varchar(300)
		 )   

	IF @ShowRB = 1
	BEGIN
		IF @tdate > @MoveBetsDay 
		BEGIN
			INSERT INTO @BettransDetail
			SELECT 
				BM.refno, 
				BM.odds, 
				BM.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BM.status, 
				BM.apositiontaking,
				0,
				0,
				BM.bettype,
				BM.Betteam,	
				BM.BetCheck,
				''	TransDesc
			FROM bettransm BM WITH (NOLOCK)
			INNER JOIN #BetListByDateMem B ON BM.refno = B.transid
			INNER JOIN #TempExchange e 
			ON e.ExchangeDate =  b.winlostdate AND e.exchangeid = b.currency
			WHERE B.Bettype IN (33,43)
		END
			
		IF @fdate <= @MoveBetsDay
		BEGIN
			INSERT INTO @BettransDetail
			SELECT 
				BM.refno, 
				BM.odds, 
				BM.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BM.status, 
				BM.apositiontaking, 
				0,
				0,
				BM.bettype,
				BM.Betteam,
				BM.BetCheck ,
				''	TransDesc
			FROM bettransm14 BM WITH (NOLOCK)
				INNER JOIN #BetListByDateMem B ON BM.refno = B.transid
				INNER JOIN #TempExchange e 
					ON e.ExchangeDate =  b.winlostdate AND e.exchangeid = b.currency
			WHERE B.Bettype IN (33,43)
		END	
		
		IF @fdate < @BalanceUpDay
		BEGIN
			INSERT INTO @BettransDetail
			SELECT 
				BM.refno, 
				BM.odds, 
				BM.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BM.status, 
				BM.apositiontaking, 
				0,
				0,
				BM.bettype,
				BM.Betteam,
				BM.BetCheck ,
				''	TransDesc
			FROM bodb_archive.dbo.bettransm BM WITH (NOLOCK)
				INNER JOIN #BetListByDateMem B ON BM.refno = B.transid
				INNER JOIN #TempExchange e ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = b.currency
			WHERE B.Bettype IN (33,43)
		END
	END	

	IF @ShowLC = 1 OR @ShowGD = 1 
	BEGIN
		IF @tdate > @MoveBetsDay 
		BEGIN
			INSERT INTO @BettransDetail
			SELECT 
				BG.refno,
				BG.odds, 
				BG.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BG.status, 
				BG.apositiontaking, 
				0,
				0,
				BG.bettype,
				BG.Betteam,
				'' AS BetCheck,
				BG.TransDesc 
			FROM bettransg BG WITH (NOLOCK)		
				INNER JOIN @SportBettype sp ON BG.bettype = sp.bettype AND sp.Productid in (4)
				INNER JOIN #BetListByDateMem B ON (BG.refno = B.refno AND BG.CustID = @CustID AND sp.Productid in (4))
				INNER JOIN #TempExchange e ON e.ExchangeDate =  b.winlostdate AND e.exchangeid = b.currency
			UNION ALL
			SELECT 
				BG.refno,
				BG.odds, 
				BG.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BG.status, 
				BG.apositiontaking, 
				0,
				0,
				BG.bettype,
				BG.Betteam,
				'' AS BetCheck,
				BG.TransDesc 
			FROM bettransg BG WITH (NOLOCK)		
				INNER JOIN @SportBettype sp ON BG.bettype = sp.bettype AND sp.Productid in (12)
				INNER JOIN #BetListByDateMem B ON (BG.refno = B.transid AND BG.CustID = @CustID AND sp.Productid in (12))
				INNER JOIN #TempExchange e ON e.ExchangeDate =  b.winlostdate AND e.exchangeid = b.currency
		END
			
		IF @fdate <= @MoveBetsDay
		BEGIN
			INSERT INTO @BettransDetail
			SELECT 
				BG.refno,
				BG.odds, 
				BG.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BG.status, 
				BG.apositiontaking, 
				0,
				0,
				BG.bettype,
				BG.Betteam,
				'' AS BetCheck,
				BG.TransDesc 
			FROM bettransg14 BG WITH (NOLOCK)
				INNER JOIN @SportBettype sp ON BG.bettype = sp.bettype AND sp.Productid in (4)
				INNER JOIN #BetListByDateMem B ON  (BG.refno = B.refno AND BG.CustID = @CustID AND sp.Productid in (4))
				INNER JOIN #TempExchange e ON e.ExchangeDate =  b.winlostdate AND e.exchangeid = b.currency
			UNION ALL
			SELECT 
				BG.refno,
				BG.odds, 
				BG.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BG.status, 
				BG.apositiontaking, 
				0,
				0,
				BG.bettype,
				BG.Betteam,
				'' AS BetCheck,
				BG.TransDesc 
			FROM bettransg14 BG WITH (NOLOCK)
				INNER JOIN @SportBettype sp ON BG.bettype = sp.bettype AND sp.Productid in (12)
				INNER JOIN #BetListByDateMem B ON  (BG.refno = B.transid AND BG.CustID = @CustID AND sp.Productid in (12))
				INNER JOIN #TempExchange e ON e.ExchangeDate =  b.winlostdate AND e.exchangeid = b.currency
		END	
		 
		IF @fdate < @BalanceUpDay
		BEGIN
			INSERT INTO @BettransDetail
			SELECT 
				BG.refno,
				BG.odds, 
				BG.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BG.status, 
				BG.apositiontaking,
				0,
				0, 
				BG.bettype,
				BG.Betteam,
				'' AS BetCheck,
				BG.TransDesc 
			FROM bodb_archive.dbo.bettransG BG WITH (NOLOCK)
				INNER JOIN @SportBettype sp ON BG.bettype = sp.bettype AND sp.Productid in (4)
				INNER JOIN #BetListByDateMem B ON (BG.refno = B.refno AND BG.CustID = @CustID AND sp.Productid in (4))
				INNER JOIN #TempExchange e  ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = b.currency
			UNION ALL
			SELECT 
				BG.refno,
				BG.odds, 
				BG.stake * (CASE @BaseCurrency WHEN 0 THEN 1 WHEN 1 THEN e.USD WHEN 2 THEN e.MYR WHEN 3 THEN e.EUR WHEN 4 THEN e.GBP ELSE 1 END),
				BG.status, 
				BG.apositiontaking,
				0,
				0, 
				BG.bettype,
				BG.Betteam,
				'' AS BetCheck,
				BG.TransDesc 
			FROM bodb_archive.dbo.bettransG BG WITH (NOLOCK)
				INNER JOIN @SportBettype sp ON BG.bettype = sp.bettype AND sp.Productid in (12)
				INNER JOIN #BetListByDateMem B ON (BG.refno = B.transid AND BG.CustID = @CustID AND sp.Productid in (12))
				INNER JOIN #TempExchange e  ON e.ExchangeDate = b.winlostdate   AND e.exchangeid = b.currency
		END 
	END
		
	SELECT * FROM @BettransDetail ORDER BY RefNo,Bettype	

	DROP TABLE #TempBetList	
	DROP TABLE #BetListByDateMem
	DROP TABLE #TempExchange
END
