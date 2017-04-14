 CREATE PROCEDURE [dbo].[Acc_Rpt_Winloss_Zzun88_BetList_History]
	@CustID			INT,
	@FromDate		DATETIME,
	@ToDate			DATETIME,
	@ShowSB			BIT = 1,
	@ShowHR			BIT = 0
AS
/*
Created: 2011-01-21
Task : Betlist for Zzun88 Winloss Report
DB: DB052.bodb02

Revisions:
	- 20110413@Amy: Change function to get odds value and odds type
	
Param's Explanation:
 + @BaseCurrency: 2-RM; 3-US$ 

*/
BEGIN
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
				DB06.bodb_archive.dbo.bettrans_bk AS b with (nolock)		
				INNER JOIN DB06.bodb_archive.dbo.match_BK AS m with (nolock) ON b.matchid=m.matchid 		
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.ruben = 1 and
				b.status NOT IN ('VOID', 'REJECT', 'REFUND') and 
				b.bettype < 31 and
				b.bettype <> 10
				
		
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
				DB06.bodb_archive.dbo.bettrans_bk  AS b with (nolock)		
				INNER JOIN DB06.bodb_archive.dbo.Outright_bk AS m with (nolock) ON b.matchid=m.orid
				INNER JOIN dbo.League as l with (nolock) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.ruben = 1 and
				b.status NOT IN ('VOID', 'REJECT', 'REFUND') and 
				b.bettype = 10

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
				CONVERT(BIT,0) as IsNeutral,
				0,0
			FROM
				DB06.bodb_archive.dbo.bettrans_bk b with (nolock)	
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.ruben = 1 and 
				b.status not in ('VOID', 'REJECT','REFUND') and
				b.bettype = 9 and
				--b.matchid = 0
				b.matchid IN (0,9) --should not remove 0 in archive
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
				DB06.bodb_archive.dbo.bettrans_bk AS b with (nolock)		
				INNER JOIN DB06.bodb_archive.dbo.Outright_bk AS m with (nolock) ON b.matchid=m.orid
				INNER JOIN dbo.League as l with (nolock) ON m.leagueID = l.leagueID
			WHERE
				b.winlostdate between @fromdate and @todate and
				b.custid=@custid and
				b.ruben = 1 and 
				b.status not in ('VOID','REJECT','REFUND') and
				b.bettype in (31, 32, 33,41,42,43)
	END

		
	SELECT	d.* , 
			--BASE RM
			d.stake*h.actualrate		AS	StakeRM,
			d.winlost*h.actualrate		AS	WinlostRM,
			d.awinlost*h.actualrate		AS	AWinlostRM,
			d.acomm*h.actualrate		AS	AcommRM,
			d.playercomm*h.actualrate	AS	PlayerCommRM,
			--BASEUSD
			d.stake*h.USDRate			AS	StakeUSD,
			d.winlost*h.USDRate			AS	WinlostUSD,
			d.awinlost*h.USDRate		AS	AWinlostUSD,
			d.acomm*h.USDRate			AS	AcommUSD,
			d.playercomm*h.USDRate		AS	PlayerCommUSD

	FROM	#BetListByDateMem d 
			INNER JOIN Exchange_History h WITH (NOLOCK) ON d.winlostdate = h.winlostdate AND h.srecommendZ88 = @srecommend 
	ORDER BY TransID 

	IF @ShowHR = 1
	BEGIN
		SELECT 
				BM.refno, 
				BM.finalodds,
				BM.odds, 
				BM.status, 
				BM.apositiontaking AS APositiontaking, 
				BM.bettype  
		FROM	DB06.bodb_archive.dbo.bettransm BM with (NOLOCK)
				INNER JOIN #BetListByDateMem B ON BM.refno = B.transid
		WHERE	B.Bettype IN (33,43)
		ORDER BY RefNo,Bettype
	END
DROP TABLE #BetListByDateMem
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Winloss_Zzun88_BetList_History] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Winloss_Zzun88_BetList_History] TO [vnteam]