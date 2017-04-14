 ALTER PROCEDURE [dbo].[Acc_Rpt_Winloss_Spondemo_BetList]
	@CustID			INT = 0,
	@FromDate		DATETIME,
	@ToDate			DATETIME,
	@MoveBetsDay	DATETIME,
	@showSB			BIT =1,
	@showHR			BIT = 0	
AS
/*
	Created: Johnson
	Date: 2010-11-16
	Task: Bets List for Spondemo  Winloss Report
	DB: DB05.BODB02
	
	Revisions:
	- 20110413@Amy: Change function to get odds value and odds type
	
	Param's Explanation:  
	  + @CustID: Member ID  	 	  
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @srecommend INT
	SELECT @srecommend = srecommend FROM custinfo (NOLOCK) WHERE custid = @custid

	CREATE TABLE #BetListByDateMem(
		sporttype	tinyint,
		TransID		bigint,
		BetID		bigint,
		Bettype		tinyint,
		hdp1		smallmoney,
		hdp2		smallmoney,
		Modds		smallmoney,
		OddsType	tinyint,
		Odds		smallmoney,
		Stake		money,
		Betteam		nvarchar(20),
		Status		nvarchar(10),
		refno		bigint,
		transdate	datetime,
		WinlostDate	datetime,
		Winlost		money,
		awinlost	money,
		acomm		money,
		playercomm	money,
		APositiontaking	smallmoney,
		ADiscount		smallmoney,
		LiveIndicator	bit,
		LiveHomeScore	smallint,
		LiveAwayScore	smallint,
		IP			nvarchar(15),
		LeagueID	int,
		MatchID		int,
		MatchCode	nvarchar(50),
		Race		nvarchar(20),
		HomeID		int,
		AwayID		int,
		Betstatus	nvarchar(50),
		isNeutral	bit,
		virtualrate	float,
		isShowOTExRate	bit)

	IF @ToDate > @MoveBetsDay
	BEGIN
		--Sport Book		
		IF @showSB = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.sporttype,
				b.transID,
				isnull(b.BetID,0),
				b.Bettype,
				b.hdp1,
				b.hdp2,
				modds,
				dbo.f_ShowOddsByBettype(b.bettype,b.oddstype) as OddsType, 
				dbo.f_GetOddsByBettype(b.Odds,b.bettype,b.oddstype) as Odds,
				b.Stake,
				b.betteam,
				b.status as Status,
				b.refno,
				b.TransDate,
				b.winlostdate,
				b.winlost-b.actual_stake,
				b.awinlost,
				b.comm-b.playercomm as acomm,
				b.playercomm,
				b.APositiontaking,
				b.discount,
				b.liveindicator,
				b.livehomescore,
				b.liveawayscore,
				b.IP as IP,
				m.leagueID,
				m.matchid,
				m.matchcode,
				'' as Race,
				m.homeid,
				m.awayid,
				m.betstatus,
				isnull(m.isNeutral, CONVERT(BIT,0)) as isNeutral,
				0 as virtualrate,
				0 as isShowOTExRate
			FROM bettrans b WITH(NOLOCK)
				INNER JOIN match m WITH(NOLOCK)  ON b.matchid = m.matchid
			WHERE b.winlostdate BETWEEN @FromDate AND @ToDate AND
				b.custid = @custid AND			
				b.bettype < 31 AND
				b.bettype <> 10 AND
				b.ruben = 1 AND
				-- b.status NOT IN ('VOID','REJECT','REFUND')  		
				b.statusID NOT IN (101,102,103)

			--Outright
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype,
				b.TransID,
				isnull(b.betid,0),
				b.bettype,
				0 as hdp1,
				0 as hdp2,
				modds,
				0 as OddsType,
				b.Odds,
				b.stake,
				'' as betteam,
				b.status,
				b.refno,
				b.transdate,
				b.winlostdate,
				b.winlost - b.actual_stake,
				b.awinlost,
				b.comm- b.playercomm as acomm,
				b.playercomm,
				b.apositiontaking,
				b.discount,
				0 as liveindicator,
				b.livehomescore,
				b.liveawayscore,
				b.Ip as IP,
				m.leagueID,
				m.orid,--matchid
				m.matchcode,
				m.groupmatch,--race
				m.teamid,--homeid
				0,--awayid
				0,--betstatus
				convert(BIT,0) as isNeutral,
				0,0			
			FROM
				dbo.bettrans as b with(nolock)
				INNER JOIN dbo.Outright as m with(nolock) ON b.matchid = m.orid
				INNER JOIN dbo.League as l with(nolock) On m.leagueID = l.leagueID
			WHERE 
				b.winlostdate between @fromdate and @todate and
				b.custid = @custid and
				b.bettype = 10 and
				b.ruben = 1 and
				b.statusID not in (101,102,103)
			
			--mixparlay
			INSERT INTO #BetListByDateMem 
			SELECT
				0, --sporttype
				b.transID,
				isnull(b.betid,0),
				b.bettype,
				b.hdp1,
				b.hdp2,
				modds,
				0 as OddsType,
				b.Odds,
				b.Stake,
				b.betteam,
				b.status,
				b.refno,
				b.Transdate,
				b.winlostdate,
				b.winlost-b.actual_stake,
				b.awinlost,
				b.comm-b.playercomm as acomm,
				b.playercomm,
				b.apositiontaking,
				b.discount,
				b.liveindicator,
				b.livehomescore,
				b.liveawayscore,
				b.Ip as IP,
				0,--leagueid
				0,--matchid
				'',--matchcode
				'',--race
				0,--homeid
				0,--awayid
				0,--betstatus
				convert(bit,0) as isNeutral,
				0,0
			FROM
				dbo.bettrans b with(nolock)
			WHERE 
				b.winlostdate between @fromdate and @todate and
				b.custid = @custid AND
				b.bettype = 9 AND
				b.matchid = 9 AND
				b.ruben = 1 AND
				b.statusID NOT IN (101,102,103)	
		END
		--Horse Racing
		IF @showHR = 1
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				isnull(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2,
				modds,
				0 as OddsType, 
				b.Odds, 
				b.Stake, 
				'' as Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				b.awinlost,
				(b.comm - b.playercomm) as acomm,	
				b.playercomm,	
				b.APositiontaking,
				b.discount,		
				0 as LiveIndicator , 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP as IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) as IsNeutral,
				b.virtualrate,
				isnumeric(m.programID)
			FROM
				dbo.bettrans as b with(NOLOCK)
				INNER JOIN dbo.Outright as m with(nolock) ON b.matchid = m.orid
				INNER JOIN dbo.league as l with(nolock) ON m.leagueid = l.leagueid
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid = @custid and
				b.bettype in (31,32,33,41,42,43) and 
				b.ruben = 1 and 
				--b.status not in ('void','reject','refund')
				b.statusid not in (101,102,103)
		END
	END

	IF @FromDate <= @MoveBetsDay
	BEGIN
		--Sport Book
		IF @showSB = 1 
		BEGIN
			INSERT INTO #BetListByDateMem
			SELECT
				m.Sporttype, 
				b.TransID,
				isnull(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				dbo.f_ShowOddsByBettype(b.bettype,b.oddstype) as OddsType, 
				dbo.f_GetOddsByBettype(b.Odds,b.bettype,b.oddstype) as Odds,
				b.Stake, 
				b.betteam, --Betteam
				b.status as Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				b.awinlost,
				(b.comm - b.playercomm) as acomm,
				b.playercomm,
				b.APositiontaking,
				b.discount,				
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP as IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' as Race,	--Race
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
				0,0
			FROM dbo.bettrans14 AS b WITH(NOLOCK)
				INNER JOIN dbo.match14 AS m WITH(NOLOCK) ON b.matchid = m.matchid
			WHERE
				b.winlostdate BETWEEN @FromDate AND @ToDate AND
				b.custid = @custid AND
				b.bettype < 31 AND
				b.bettype <> 10 AND
				b.ruben = 1 AND 
				b.statusID NOT IN(101,102,103)		

			--Outright
			INSERT INTO #BetListByDateMem
			SELECT 
				l.sporttype, --Sporttype
				b.TransID,
				isnull(b.BetID,0),
				b.Bettype,
				0 as hdp1, 
				0 as hdp2, 
				modds,
				0 as OddsType, 
				b.Odds, 
				b.Stake, 
				'' as Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				b.awinlost,
				(b.comm - b.playercomm) as acomm,
				b.playercomm,
				b.APositiontaking ,
				b.discount,	
				0 as LiveIndicator, 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP as IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch as Race,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) as isNeutral,
				0,0
			FROM dbo.bettrans14 AS b WITH(NOLOCK)
				INNER JOIN dbo.outright14 AS m WITH(NOLOCK) ON b.matchid = m.orid
				INNER JOIN dbo.League AS l WITH(NOLOCK) ON m.leagueid = l.leagueid
			WHERE
				b.winlostdate BETWEEN @FromDate AND @ToDate AND
				b.custid = @custid AND 
				b.ruben = 1 AND 
				b.bettype = 10 AND
				b.statusID NOT IN (101,102,103)
		
			--Mix Parlay
			INSERT INTO #BetListByDateMem
			SELECT 
				0, --Sporttype
				b.TransID,
				isnull(b.BetID,0),
				b.bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 as OddsType, 
				b.Odds, 
				b.Stake, 
				b.betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				b.awinlost ,
				(b.comm - b.playercomm) as acomm,
				b.playercomm,
				b.APositiontaking,
				b.discount,	
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP as IP,
				0, --LeagueID
				0, --MatchID
				'',--MatchCode
				'',--Race	
				0, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) as isNeutral,
				0,0
			FROM dbo.bettrans14 AS b WITH(NOLOCK)
			WHERE
				b.winlostdate BETWEEN @FromDate AND @ToDate AND 
				b.custid = @custid AND
				b.bettype = 9 AND
				b.matchid = 9 AND
				b.ruben = 1 AND
				b.statusID NOT IN (101,102,103)	
		END

		--Horse Racing
		IF @showHR =1 
		BEGIN
			INSERT INTO #BetListByDateMem 
			SELECT
				l.sporttype, --Sporttype
				b.TransID,
				isnull(b.BetID,0),
				b.Bettype,
				b.hdp1, 
				b.hdp2, 
				modds,
				0 as OddsType, 
				b.Odds, 
				b.Stake, 
				'' as Betteam, --Betteam
				b.Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,						
				(b.winlost-actual_stake),
				b.awinlost,
				(b.comm - b.playercomm) as acomm,
				b.playercomm,
				b.APositiontaking,
				b.discount,					
				0 as LiveIndicator, 
				b.LiveHomescore, 
				b.LiveAwayscore,
				b.IP as IP,
				m.LeagueID,
				m.OrId,--0, --MatchID	
				m.MatchCode,
				m.GroupMatch as Race,--Race
				m.TeamID, --HomeID
				0, --AwayID		
				0, --Betstatus
				CONVERT(BIT,0) as isNeutral,
				b.virtualrate,		
				isnumeric(m.programID)
			FROM dbo.bettrans14 AS b WITH(NOLOCK) 
				INNER JOIN dbo.Outright14 AS m WITH(NOLOCK) ON b.matchid = m.orid
				INNER JOIN dbo.League AS l WITH(NOLOCK) ON m.leagueid = l.leagueid
			WHERE 
				b.winlostdate BETWEEN @FromDate AND @ToDate AND
				b.custid = @custid AND
				b.bettype IN (31,32,33,41,42,43) AND 
				b.ruben = 1 AND
				b.statusID NOT IN (101,102,103)
		END
	END

	SELECT
		d.*,
		--BASE RM
		d.stake*h.actualrate	AS stakeRM,
		d.winlost*h.actualrate	AS WinlostRM,
		d.awinlost*h.actualrate	AS AWinlostRM,
		d.acomm*h.actualrate	AS ACommRM,
		d.playercomm*h.actualrate	AS PlayerCommRM,
		--BASE USD
		d.stake*h.USDRate		AS stakeUSD,
		d.winlost*h.USDRate		AS WinlostUSD,
		d.AWinlost*h.USDRate	AS AWinlostUSD,
		d.AComm*h.USDRate		AS ACommUSD,
		d.PlayerComm*h.USDRate	AS PlayerCommUSD
		
	FROM #BetListByDateMem d
		INNER JOIN Exchange_History h WITH(NOLOCK) ON d.winlostdate = h.winlostdate AND h.srecommendSPON = @srecommend
	ORDER BY TransID

	IF @showHR = 1
	BEGIN
		DECLARE @Bettransm TABLE(
		refno bigint,
		finalodds smallmoney,
		odds smallmoney,
		status nvarchar(10),
		apositiontaking smallmoney,
		bettype tinyint
		)

		IF @ToDate > @MoveBetsDay
		BEGIN
			INSERT INTO @Bettransm
			SELECT
				bm.refno,
				bm.finalodds,
				bm.odds,
				bm.status,
				bm.apositiontaking as APositiontaking,
				bm.bettype
			FROM bettransm bm WITH(NOLOCK)
				INNER JOIN #BetListByDateMem b ON bm.refno = b.transid
			WHERE b.bettype IN  (33,43)
		END

		IF @FromDate <= @MoveBetsDay
		BEGIN
			INSERT INTO @Bettransm
			SELECT
				bm.refno,
				bm.finalodds,
				bm.odds,
				bm.status,
				bm.apositiontaking AS APositiontaking,
				bm.bettype
			FROM bettransm14 bm WITH(NOLOCK)
				INNER JOIN #BetListByDateMem b ON bm.refno = b.transid
			WHERE b.bettype IN (33,43)
		END

		SELECT * FROM @Bettransm ORDER BY RefNo, Bettype
		DROP TABLE #BetListByDateMem
	END
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Spondemo_BetList] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Spondemo_BetList] TO [vnteam]
