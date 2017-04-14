ALTER PROCEDURE [dbo].[Acc_Rpt_Winloss_AB88_BetList]
	@CustID			INT,
	@FromDate		DATETIME,
	@ToDate			DATETIME,
	@MoveBetsDay	DATETIME,
	@ShowSB			BIT = 1,
	@ShowHR			BIT = 0
AS

/*
Created: Henry 
Date: 2009-11-28
Task : Betlist for AsiaBet88 Winloss Report
DB: DB052.bodb02

Revisions:
	- 20100525@Jamie: Show OpenTote ExRate 
	-- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
	- 20100611@Henry: Change mix-parlay match from 0 to 9
	- 20101007@Henry: Change column transid from INT to BIGINT
	- 20110413@Amy: Change function to get odds value and odds type
	- 20111229@Jim: f_ShowOddsByBettype,f_GetOddsByBettype,


Param's Explanation:
 + @BaseCurrency: 2-RM; 3-US$ 

*/

SET NOCOUNT ON

DECLARE	@srecommend INT 
SELECT	@srecommend = srecommend FROM custinfo (NOLOCK) WHERE custid = @custid

CREATE TABLE #BetListByDateMem(
	Sporttype		tinyint,
	TransID			bigint,
	BetID			bigint,
	Bettype			tinyint,
	hdp1			smallmoney, 
	hdp2			smallmoney, 
	Modds			smallmoney,
	OddsType		tinyint,
	Odds			smallmoney, 
	Stake			money, 
	Betteam			nvarchar(20),
	Status			nvarchar(10),
	RefNO			bigint,	
	Transdate		datetime,
	Winlostdate		datetime,
	Winlost			money,
	awinlost		money,
	acomm			money,
	playercomm		money,
	APositiontaking smallmoney,
	Adiscount		smallmoney,
	Liveindicator	bit,
	Livehomescore	smallint,
	Liveawayscore	smallint,
	IP				nvarchar(15),
	LeagueID		int,
	MatchID			int,
	MatchCode		nvarchar(50),
	Race			nvarchar(20),
	HomeID			int,
	AwayID			int, 	
	Betstatus		nvarchar(50),
	isNeutral		bit,
	virtualrate		float,
	isShowOTExRate	bit
)
IF @Todate > @MoveBetsDay
BEGIN
	--Sport Book
	IF @ShowSB = 1
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
				b.oddstype, 
				--dbo.f_ShowOddsByBettype(b.bettype,b.oddstype) as OddsType, 
				b.odds,
				--dbo.f_GetOddsByBettype(b.Odds,b.bettype,b.oddstype) as Odds, 
				b.Stake, 
				b.betteam, --Betteam
				b.status as Status,				
				b.refno,
				b.Transdate,	
				b.winlostdate,			
				(b.winlost-actual_stake),
				b.awinlost,
				(b.comm - b.PlayerComm) as acomm ,
				b.playercomm,
				b.APositiontaking ,
				b.discount,		
				b.Liveindicator,
				b.Livehomescore,
				b.Liveawayscore,
				b.IP as IP,
				m.LeagueID,
				m.MatchID,	
				m.MatchCode,
				'' as Race,	
				m.HomeID,
				m.AwayID, 		
				m.Betstatus,
				isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
				0,0
			FROM
				dbo.bettrans AS b with (nolock)		
				INNER JOIN dbo.match AS m with (nolock) ON b.matchid=m.matchid 		
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.bettype < 31 and 
				b.bettype <>10 AND
				b.ruben = 1 and
				--b.status NOT IN ('VOID', 'REJECT', 'REFUND') 
				 b.statusID NOT IN (101,102,103) 
				
		
		-- Outright
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
				0,0
			FROM
				dbo.bettrans AS b with (nolock)		
				INNER JOIN dbo.Outright AS m with (nolock) ON b.matchid=m.orid
				INNER JOIN dbo.League as l with (nolock) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.bettype = 10 AND
				b.ruben = 1 and
				--b.status NOT IN ('VOID', 'REJECT', 'REFUND') 
				 b.statusID NOT IN (101,102,103) 
				

		-- Mix Parlay		
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
				b.awinlost,
				(b.comm - b.playercomm) as acomm,	
				b.playercomm,	
				b.APositiontaking ,
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
				CONVERT(BIT,0) as IsNeutral,
				0,0
			FROM
				dbo.bettrans b with (nolock)	
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.bettype = 9 and
				--b.matchid = 0 AND
				b.matchid = 9 and
				b.ruben = 1 and 
				--b.status not in ('VOID', 'REJECT','REFUND') 
				b.statusID NOT IN (101,102,103) 
				
	END
	-- Horse Racing
	IF @ShowHR = 1
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
				dbo.bettrans AS b with (nolock)		
				INNER JOIN dbo.Outright AS m with (nolock) ON b.matchid=m.orid
				INNER JOIN dbo.League as l with (nolock) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				 b.bettype in (31, 32, 33,41,42,43) AND
				b.ruben = 1 and 
				--b.status not in ('VOID','REJECT','REFUND') 
				b.statusID NOT IN (101,102,103)
				
	END
END

IF @Fromdate <= @MoveBetsDay
BEGIN
	--Sport Book
	IF @ShowSB = 1
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
				b.oddstype, 
				--dbo.f_ShowOddsByBettype(b.bettype,b.oddstype) as OddsType, 
				b.odds,
				--dbo.f_GetOddsByBettype(b.Odds,b.bettype,b.oddstype) as Odds, 
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
			FROM
				dbo.bettrans14 AS b with (nolock)		
				INNER JOIN dbo.match14 AS m with (nolock) ON b.matchid=m.matchid 					
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.bettype < 31
				and b.bettype <>10 and
				b.ruben = 1 and 
				--b.status not in ('VOID', 'REJECT','REFUND') 
				b.statusID NOT IN (101,102,103)
				

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
			FROM
				dbo.bettrans14 as b with (nolock)	
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.bettype = 9 and
				--b.matchid = 0 and
				b.matchid = 9 and
				b.ruben = 1 and 
				--b.status not in ('VOID', 'REJECT','REFUND') 
				b.statusID NOT IN (101,102,103)
				
			
				
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
			FROM
				dbo.bettrans14 AS b with (nolock)		
				INNER JOIN dbo.Outright14 AS m with (nolock) ON b.matchid=m.orid
				INNER JOIN dbo.League as l with (nolock) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.bettype = 10 and
				b.ruben = 1 and
				--b.status not in ('VOID', 'REJECT','REFUND') 
				b.statusID NOT IN (101,102,103)
				
	END	
	--Horse Racing
	IF @ShowHR = 1
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
			FROM
				dbo.bettrans14 AS b with (nolock)		
				INNER JOIN dbo.Outright14 AS m with (nolock) ON b.matchid=m.orid
				INNER JOIN dbo.League as l with (nolock) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid
				and b.bettype in (31, 32, 33,41,42,43) and
				b.ruben = 1 and
				--b.status not in ('VOID', 'REJECT','REFUND') 
				b.statusID NOT IN (101,102,103)
				
	END
END		
	
SELECT	d.* , 
		--BASE RM
		d.stake*h.actualrate		AS	StakeRM,
		d.winlost*h.actualrate		AS	WinlostRM,
		d.awinlost*h.actualrate		AS	AWinlostRM,
		d.acomm*h.actualrate		AS	AcommRM,
		d.playercomm*h.actualrate	AS  PlayerCommRM,
		--BASEUSD
		d.stake*h.USDRate			AS	StakeUSD,
		d.winlost*h.USDRate			AS	WinlostUSD,
		d.awinlost*h.USDRate		AS	AWinlostUSD,
		d.acomm*h.USDRate			AS	AcommUSD,
		d.playercomm*h.USDRate		AS  PlayerCommUSD

FROM	#BetListByDateMem d 
		INNER JOIN Exchange_History h WITH (NOLOCK) ON d.winlostdate = h.winlostdate AND h.srecommendAB88 = @srecommend 
ORDER BY TransID 

IF @ShowHR = 1
begin
	DECLARE @Bettransm TABLE(  
	 refno bigint,  
	 finalodds smallmoney,
	 odds smallmoney,  
	 status nvarchar(10),  
	 apositiontaking smallmoney,  
	 bettype tinyint
	 )   

	IF @Todate > @MoveBetsDay 
	BEGIN
		INSERT INTO @Bettransm
		SELECT 
			BM.refno, 
			BM.finalodds,
			BM.odds, 
			BM.status, 
			BM.apositiontaking AS APositiontaking, 
			BM.bettype  
		FROM bettransm BM with (NOLOCK)
		INNER JOIN #BetListByDateMem B ON BM.refno = B.transid
		WHERE B.Bettype IN (33,43)
	END
		
	IF @Fromdate <= @MoveBetsDay
	BEGIN
		INSERT INTO @Bettransm
		SELECT 
			BM.refno, 
			BM.finalodds,
			BM.odds, 
			BM.status, 
			BM.apositiontaking AS APositiontaking, 
			BM.bettype  
		FROM bettransm14 BM with (NOLOCK)
		INNER JOIN #BetListByDateMem B ON BM.refno = B.transid
		WHERE B.Bettype IN (33,43)
	END	
	
	SELECT * FROM @Bettransm ORDER BY RefNo,Bettype
	DROP TABLE #BetListByDateMem
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_AB88_BetList] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_AB88_BetList] TO [vnteam]