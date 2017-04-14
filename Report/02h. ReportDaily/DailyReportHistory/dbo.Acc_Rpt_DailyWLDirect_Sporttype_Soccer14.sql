ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Sporttype_Soccer14]
	@winlostdate	datetime,
	@SoccerType		TINYINT = 0
AS

/*	Creator: Elodie
	Date: 2012-07-11
	Task: Daily Winloss Report History for Soccer
	DB: DBACC/bodb02	
	Origional: Acc_Rpt_DailyWLDirect_Sporttype14
	 	
	History:
		- 20130408@Elodie: Add RealLineTotal field for all products that enable virtual currency
		- 20130522@Elodie: Get more fields RealTurnover, VirtualTurnover
		- 20130802@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)	
		- 20140711@Johnson: Separate major and minor bettypes of soccer		
		- 20140930@Johnson: Add new report for soccer minor bettype
		- 20141111@Johnson: include additional bettypes into report
		- 20150204@Johnson: move 1H Double Chance bet type to major bettype [RedmineID: #27216]
		- 20150525@Sophia: Apply Metric Gaming - SuperLive and Sport Betype Matrix [#35359]
		- 20150723@Sophia: Exclude data of Bettrade [#38815]	
		- 20150917@Jim: Integrate MO product (Feature #41935)
		- 20160523@Sophia: Refactor code, Enhance Performance [Redmind: #57987]	
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	Explanation's Param:
		- @SoccerType =	 0: All bettype(major and minor bettype)
					= 1: report soccer for major bettype
					= 2: report soccer for minor bettype
		- @IncludeBettype: include more bettypes in some specific cases(minor bettypes soccer get some major bettypes)
*/


BEGIN 
	SET NOCOUNT ON

	------Get Sport Bettype Matrix------
	-- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SportBettype (ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500), IsSoccerMajor TINYINT DEFAULT (2))
	INSERT INTO #SportBettype ( ProductID, Bettype, EventType, SubProduct)
	SELECT ProductID,
		Bettype,
		EventType,
		SubProduct
	FROM dbo.f_SportBettypeMatrix_Sel(1, 1, 0, 2, '', '', @isTest)


	DELETE	#SportBettype  
	WHERE	SubProduct IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
		OR EventType NOT IN (1,2)
		OR (@SoccerType = 1 AND Bettype NOT IN (1,2,3,5,6,7,8,12,15,24,25,28,121,122,123,126,151,301,302,303,304))
		OR (@SoccerType = 2 AND Bettype IN (1,3,7,8,122,123,151,301,302,303,304))
		---- '2,5,6,12,15,24,25,28,121,126' : this is Major bettypes but with the Soccer - Minor Report, it will include these bettypes too

	IF @SoccerType <> 2 
	BEGIN 
		UPDATE	#SportBettype
		SET		IsSoccerMajor = 1
		WHERE   Bettype IN (1,2,3,5,6,7,8,12,15,24,25,28,121,122,123,126,151,301,302,303,304)
	END 

	 
	--deposit super
	CREATE TABLE #DepSuper (custid INT)
		
	INSERT INTO #DepSuper 
	SELECT custid FROM f_DepSuper_1('All')
	 
	-----
	CREATE TABLE #Match (matchid INT, sporttype INT, type varchar(10), primary key(matchid, type))
							
	INSERT INTO #Match 
	SELECT	m.matchid, 
			l.sporttype,
			m.type
	FROM (
			SELECT matchid, leagueid, 'match' as type FROM match14 WITH (NOLOCK) WHERE eventdate = @winlostdate
			UNION ALL
			SELECT orid, leagueid, 'outright' as type FROM outright14 WITH (NOLOCK) WHERE eventdate = @winlostdate
			)m	
			INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid	
	WHERE	l.SportType = 1 --Get matchs of Soccer


	------------- get result --------------
	CREATE TABLE #Result (SportName VARCHAR(500), SportType INT, ibc TINYINT, site TINYINT, WinLost MONEY, Position MONEY, Commission MONEY, RealLineTotal MONEY, VirtualLineTotal MONEY, RealTurnover MONEY, VirtualTurnover MONEY)

	INSERT INTO #Result(SportName, SportType, ibc, site, WinLost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover)
	SELECT
			CASE WHEN t.IsSoccerMajor = 1 THEN 'Soccer-Major Bet Types' ELSE 'Soccer-Minor Bet Types' END as SportName,
			t.IsSoccerMajor as SportType,	
			0 ibc,
			CASE WHEN dep.custid IS NULL THEN 1 ELSE 2 END AS Site,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
			sum((1-tpositiontaking)*ABS(stake)*actualrate) RealTurnover,
			sum((1-tpositiontaking)*ABS(stake)*virtualrate) VirtualTurnover
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN #Match m on b.matchid = m.matchid
			LEFT JOIN #DepSuper dep ON b.srecommend = dep.custid 		
			INNER JOIN #SportBettype t ON b.bettype = t.bettype
	WHERE	b.winlostdate = @winlostdate					
			AND b.statusID NOT IN (101, 102,103) 
			AND b.ruben = 1	
			AND b.MatchID > 0 
			AND b.Bettype < 19001
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 
	GROUP BY CASE WHEN t.IsSoccerMajor = 1 THEN 'Soccer-Major Bet Types' ELSE 'Soccer-Minor Bet Types' END,
			t.IsSoccerMajor,		
			CASE WHEN dep.custid IS NULL THEN 1 ELSE 2 END

		
	------ BARM (site only)
	INSERT INTO #Result (SportName, SportType, ibc, site, WinLost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover)
	SELECT
			CASE WHEN t.IsSoccerMajor = 1 THEN 'Soccer-Major Bet Types' ELSE 'Soccer-Minor Bet Types' END as SportName,
			t.IsSoccerMajor as SportType,	
			0 ibc,
			3 AS Site,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
			sum((1-tpositiontaking)*ABS(stake)*actualrate) RealTurnover,
			sum((1-tpositiontaking)*ABS(stake)*virtualrate) VirtualTurnover
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN #Match m on b.matchid = m.matchid
			INNER JOIN #SportBettype t ON t.bettype = b.bettype	
	WHERE	 b.recommend = 5707545 
			AND b.winlostdate = @winlostdate				
			AND b.statusID NOT IN (101, 102,103) --('VOID', 'REJECT','REFUND')
			AND b.ruben = 1	
			AND b.MatchID > 0 
			AND b.Bettype < 19001
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 
	GROUP BY 
			CASE WHEN t.IsSoccerMajor = 1 THEN 'Soccer-Major Bet Types' ELSE 'Soccer-Minor Bet Types' END,
			t.IsSoccerMajor
				 

	---- Update Credit = Credit - BARM, Deposit = Deposit + BARM
	UPDATE 	c
	SET		c.WinLost = ISNULL(c.WinLost,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.WinLost,0) ELSE ISNULL(d.WinLost,0) END,
			c.Position = ISNULL(c.Position,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.Position,0) ELSE ISNULL(d.Position,0) END,
			c.Commission = ISNULL(c.Commission,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.Commission,0) ELSE ISNULL(d.Commission,0) END,
			c.RealLineTotal = ISNULL(c.RealLineTotal,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.RealLineTotal,0) ELSE ISNULL(d.RealLineTotal,0) END,
			c.VirtualLineTotal = ISNULL(c.VirtualLineTotal,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.VirtualLineTotal,0) ELSE ISNULL(d.VirtualLineTotal,0) END,
			c.RealTurnover = ISNULL(c.RealTurnover,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.RealTurnover,0) ELSE ISNULL(d.RealTurnover,0) END,
			c.VirtualTurnover = ISNULL(c.VirtualTurnover,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.VirtualTurnover,0) ELSE ISNULL(d.VirtualTurnover,0) END
	FROM	#Result c
	FULL JOIN  #Result d
			ON	c.SportType = d.SportType
				AND d.Site = 3 
				AND c.site IN (1,2)


	-----Delete BARM row used for calculate
	DELETE #Result WHERE Site = 3

	-----------------------------------------------------------------------------
	-- Get win lost of agent '8RM',  'BARM'
	INSERT INTO #Result (SportName, SportType, ibc, site, WinLost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover)
	SELECT
			'Soccer' as SportName,
			1 as SportType,	
			CASE WHEN  b.recommend = 52466 THEN 1 ELSE 2 END AS ibc,
			0 as site,
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,	
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN #Match m on b.matchid = m.matchid
			INNER JOIN #SportBettype t ON b.bettype = t.bettype		
	WHERE	b.winlostdate = @winlostdate	
			AND b.MatchID > 0 
			AND b.Bettype < 19001
			AND b.statusID NOT IN (101, 102,103) 
			AND b.ruben = 1	
			AND b.recommend IN (52466, 5707545) 
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 
	GROUP BY m.sporttype, CASE WHEN  b.recommend = 52466 THEN 1 ELSE 2 END
 
	SELECT * FROM #Result
	ORDER BY SportType 
 
	DROP TABLE #DepSuper
	DROP TABLE #Match
	DROP TABLE #SportBettype
	DROP TABLE #Result
 
END 
	
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Sporttype_Soccer14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Sporttype_Soccer14] TO [vnteam]		
