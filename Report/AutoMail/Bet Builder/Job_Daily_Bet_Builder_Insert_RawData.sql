/*<info serverAlias="DBRPT-bodb_Report" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_Report
GO

ALTER PROCEDURE dbo.Job_Daily_Bet_Builder_Insert_RawData
	@WinlostDate    SMALLDATETIME = NULL
AS
/*
	Creator: Robert
	Date: 2019-05-27
	DB: DBRPT.bodb_Report
	Task: Bet Builder - Daily Automail report to 3rd
	Revisions:		
		- 20190527@Robert: Bet Builder - Daily Automail report to 3rd [#114248]
		- 20210504@Jaden: Use SP to get balanceup & movebets (#154116)
		- 20220907@Jaden: Change betfrom datatype (#177202)

	Param's Explanation:	   
				    - @IsCaptureData:
					   = 0 => Local, UAT, SIT
					   = 1 => PROD
*/

BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #RawData(
	    Id                INT IDENTITY(1, 1)
	  , TransId           BIGINT
	  , MatchId           INT
	  , LeagueId          INT
	  , HomeId            INT
	  , AwayId            INT
	  , GlobalShowTime    DATETIME
	  , MarketId          VARCHAR(20)
	  , DateTimePlaced    DATETIME
	  , NoOfLegsPerBet    SMALLMONEY
	  , Betfrom           NVARCHAR(5)
	  , Odds              SMALLMONEY
	  , Currency          INT
	  , Stake             MONEY
	  , StatusId          INT
	  , Payout            MONEY
	  , Commission        MONEY
	  , GrossRevenue      MONEY);

    DECLARE @movebetdate      DATETIME
		, @balanceupdate    DATETIME
		, @CapturedDate     DATETIME = GETDATE()
		, @NumberOfRows     BIGINT
		, @RowsPerBatch     INT      = 20000
		, @BatchNumber      INT      = 0
		, @StartId          INT
		, @EndId            INT;


	SELECT @balanceupdate = BalanceUpDay, @movebetdate = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

    IF @WinlostDate IS NULL
	   SELECT @WinlostDate = CONVERT(VARCHAR(10), DATEADD(DAY, -1, GETDATE()), 110);

    IF @WinlostDate > @movebetdate
	   BEGIN
		  INSERT INTO #RawData(TransId
						 , MatchId
						 , LeagueId
						 , HomeId
						 , AwayId
						 , GlobalShowTime
						 , MarketId
						 , DateTimePlaced
						 , NoOfLegsPerBet
						 , Betfrom
						 , Odds
						 , Currency
						 , Stake
						 , StatusId
						 , Payout
						 , Commission
						 , GrossRevenue)
			    (
				   SELECT b.transid
					   , b.matchid
					   , m.leagueid
					   , m.homeid
					   , m.awayid
					   , m.GlobalShowTime
					   , b.betcheck AS MarketId
					   , b.transdate AS [Date/Time Placed]
					   , b.hdp2 AS [No. of legs per bet]
					   , b.betfrom
					   , b.odds
					   , b.currency
					   , b.stake
					   , b.statusID
					   , b.winlost AS Payout
					   , b.scomm AS Commission
					   , b.stake - b.winlost - b.scomm AS [Gross Revenue]
				   FROM bodb02.dbo.bettrans AS b WITH (NOLOCK)
					  INNER JOIN bodb02.dbo.match AS m WITH (NOLOCK) ON b.matchid = m.matchid
				   WHERE b.winlostdate = @WinlostDate
					    AND b.statusID IN(112, 113, 111)
					    AND b.bettype = 38
					    AND b.currency NOT IN(20, 27, 28, 72)
			    );
	   END;

    IF @WinlostDate <= @movebetdate
	   BEGIN
		  INSERT INTO #RawData(TransId
						 , MatchId
						 , LeagueId
						 , HomeId
						 , AwayId
						 , GlobalShowTime
						 , MarketId
						 , DateTimePlaced
						 , NoOfLegsPerBet
						 , Betfrom
						 , Odds
						 , Currency
						 , Stake
						 , StatusId
						 , Payout
						 , Commission
						 , GrossRevenue)
			    (
				   SELECT b.transid
					   , b.matchid
					   , m.leagueid
					   , m.homeid
					   , m.awayid
					   , m.GlobalShowTime
					   , b.betcheck AS MarketId
					   , b.transdate AS [Date/Time Placed]
					   , b.hdp2 AS [No. of legs per bet]
					   , b.betfrom
					   , b.odds
					   , b.currency
					   , b.stake
					   , b.statusID
					   , b.winlost AS Payout
					   , b.scomm AS Commission
					   , b.stake - b.winlost - b.scomm AS [Gross Revenue]
				   FROM bodb02.dbo.bettrans14 AS b WITH (NOLOCK)
					  INNER JOIN bodb02.dbo.match14 AS m WITH (NOLOCK) ON b.matchid = m.matchid
				   WHERE b.winlostdate = @WinlostDate
					    AND b.statusID IN(112, 113, 111)
					    AND b.bettype = 38
					    AND b.currency NOT IN(20, 27, 28, 72)
			    );
	   END;

    IF @WinlostDate < @balanceupdate
	   BEGIN
		  INSERT INTO #RawData(TransId
						 , MatchId
						 , LeagueId
						 , HomeId
						 , AwayId
						 , GlobalShowTime
						 , MarketId
						 , DateTimePlaced
						 , NoOfLegsPerBet
						 , Betfrom
						 , Odds
						 , Currency
						 , Stake
						 , StatusId
						 , Payout
						 , Commission
						 , GrossRevenue)
			    (
				   SELECT b.transid
					   , b.matchid
					   , m.leagueid
					   , m.homeid
					   , m.awayid
					   , m.GlobalShowTime
					   , b.betcheck AS MarketId
					   , b.transdate AS [Date/Time Placed]
					   , b.hdp2 AS [No. of legs per bet]
					   , b.betfrom
					   , b.odds
					   , b.currency
					   , b.stake
					   , b.statusID
					   , b.winlost AS Payout
					   , b.scomm AS Commission
					   , b.stake - b.winlost - b.scomm AS [Gross Revenue]
				   FROM bodb_Archive.dbo.bettrans_bk AS b WITH (NOLOCK)
					  INNER JOIN bodb_Archive.dbo.match_bk AS m WITH (NOLOCK) ON b.matchid = m.matchid
				   WHERE b.winlostdate = @WinlostDate
					    AND b.statusID IN(112, 113, 111)
					    AND b.bettype = 38
					    AND b.currency NOT IN(20, 27, 28, 72)
			    );
	   END;

    CREATE CLUSTERED INDEX CIX_Data_Id ON #RawData(Id ASC);

    WHILE 1 = 1
	   BEGIN
		  IF NOT EXISTS
					 (
						SELECT TOP 1 1
						FROM bodb_Report.dbo.BetBuilder_BetHistoryAutomail AS b WITH (NOLOCK)
						WHERE b.WinlostDate = @WinlostDate
					 )
			 BREAK;

		  DELETE TOP (@RowsPerBatch)
		  b
		  FROM bodb_Report.dbo.BetBuilder_BetHistoryAutomail b
		  WHERE b.WinlostDate = @WinlostDate;
	   END;

    SELECT @NumberOfRows = COUNT(1)
    FROM #RawData;

    WHILE 1 = 1
	   BEGIN
		  SELECT @StartId = 1 + @BatchNumber * @RowsPerBatch
			  , @EndId = @StartId + @RowsPerBatch - 1;

		  INSERT INTO bodb_Report.dbo.BetBuilder_BetHistoryAutomail(CapturedDate
													   , TransId
													   , WinlostDate
													   , MatchId
													   , Betcheck
													   , Hdp2
													   , Odds
													   , CurrencyId
													   , Stake
													   , StatusId
													   , Winlost
													   , Scomm
													   , Transdate
													   , Betfrom)
			    (
				   SELECT @CapturedDate AS CapturedDate
					   , TransId
					   , @WinlostDate AS WinlostDate
					   , MatchId
					   , MarketId AS Betcheck
					   , NoOfLegsPerBet AS Hdp2
					   , Odds
					   , Currency AS CurrencyId
					   , Stake
					   , StatusId
					   , Payout AS Winlost
					   , Commission AS Scomm
					   , DateTimePlaced AS Transdate
					   , Betfrom
				   FROM #RawData
				   WHERE Id BETWEEN @StartId AND @EndId
			    );

		  IF @EndId > @NumberOfRows
			 BEGIN
				BREAK;
			 END;

		  SELECT @BatchNumber = @BatchNumber + 1;
	   END;

    DROP TABLE #RawData;
END;