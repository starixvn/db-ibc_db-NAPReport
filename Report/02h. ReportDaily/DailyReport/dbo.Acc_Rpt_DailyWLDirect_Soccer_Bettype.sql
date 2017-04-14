use bodb02
GO 

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Soccer_Bettype]
	@winlostdate	datetime,
	@SoccerType		INT = 1,
	@IncludeBettype VARCHAR(MAX) = ''
AS


/*	Creator: Phuong Dao
	Date: 2009-02-26
	Task: WinLost Summary report - History
	DB: DBACC/bodb02
	
	Revisions:
		- 20090714@Kiwi: Exclude 'Refund' ticket
		- 20090731@Jamie: Not to view data in range of date, but only one date at once
		- 20091109@Kiwi: Declare @temp table to contain all matches based on @winlostdate
		- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		- 16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
		- 20110824@Johnson: - remove check winlostdate with '16 Dec 2010' for sumary turnover, get from stake instead actual_stake
		- 20110824@Elly: - Correct Turnover of sports book since Sep 01, 2011
		- 20110826@Lukas: Modify to get bettype automatically
		- 20111202@Sophia: . Add new range for sportbook from 121 to 999
						   . Remove @NegativeBetEffectiveDate
		- 20120412@Hurri: Get win lost of agent 'BARM'
		- 20120530@Elodie: Change formula of 8RM/BARM winloss
		- 20120628@Elodie: check case of matchid = orid
		- 20121018@Lukas: use temp table to enhance performance
		- 20130408@Elodie: Add RealLineTotal field for all products that enable virtual currency
		- 20130522@Elodie: Get more fields RealTurnover, VirtualTurnover
		- 20130731@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)				  
		- 20140711@Johnson: Separate major and minor bettypes of soccer
		- 20141110@Johnson: include additional bettypes into report 
		- 20150108@Dom: Apply sport bettype matrix
		- 20150204@Johnson: move 1H Double Chance bet type to major bettype [RedmineID: #27216]
		- 20150525@Sophia: Apply Metric Gaming - SuperLive and revise Sport Betype Matrix [#35359] 
		- 20150723@Sophia: Exclude data of Bettrade [#38815]	
		- 20150917@Jim: Integrate MO product (Feature #41935)
		- 20160609@Sophia: Enhance Performance [Redmind: #59190]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)		

	Param's Explanation: 
		- @SoccerType= 1: Major bettypes
					= 2: Minor bettypes	
		- @IncludeBettype: include more bettypes in some specific cases(minor bettypes soccer get some major bettypes)
*/	

BEGIN 
	SET NOCOUNT ON	
	------Get Sport Bettype Matrix------
	-- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SportBettype (Bettype INT,EventType INT,SubProduct VARCHAR(500), DisplayOrder INT )
	INSERT INTO #SportBettype (Bettype, EventType, SubProduct, DisplayOrder)
	SELECT 
		Bettype,
		EventType,
		SubProduct,
		Bettype
	FROM dbo.f_SportBettypeMatrix_Sel(1, 1, 0, 2, '', '', @isTest)


	DELETE	#SportBettype  
	WHERE	SubProduct IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
		OR EventType NOT IN (1,2)
		OR (@SoccerType = 1 AND Bettype NOT IN (1,2,3,5,6,7,8,12,15,24,25,28,121,122,123,126,151,301,302,303,304))
		OR (@SoccerType = 2 AND Bettype IN (1,3,7,8,122,123,151,301,302,303,304))
		---- '2,5,6,12,15,24,25,28,121,126' : this is Major bettypes but with the Soccer - Minor Report, it will include these bettypes too


	IF @IncludeBettype = '' AND @SoccerType = 2
	BEGIN 
		DELETE #SportBettype
		WHERE Bettype IN (2,5,6,12,15,24,25,28,121,126)
	END  

	------------ 

	Declare @tmpBettype table (	Bettype			int primary key, 
								DisplayOrder	int)
	Insert into @tmpBettype
	select 1,  1 --'Handicap',
	UNION ALL
	select 301,2 --% Handicap
	UNION ALL
	Select 3,  3 --'Over/Under',
	UNION ALL 
	select 302,4 --- % Over/Under
	UNION ALL
	select 7,  5 --'1st Half Handicap',
	UNION ALL 
	select 303,6 -- 1H % Handicap
	UNION ALL
	Select 8,  7 --'1st Half Over/Under',
	UNION ALL 
	select 304,8 --1H % Over/Under
	UNION ALL
	select 2,  9 --'Odd/Even',
	UNION ALL
	select 5,  9 --'1x2',
	UNION ALL
	Select 4,  9 --'Correct Score',
	UNION ALL
	Select 6,  9 --'Total Goal',
	UNION ALL 
	Select 10, 10 --'Outright',


	UPDATE	s
	SET		s.DisplayOrder = t.DisplayOrder
	FROM	#SportBettype s 
	INNER JOIN @tmpBettype t 
		ON	s.bettype = t.bettype 

	
	-------------------
	--deposit super
	CREATE TABLE #DepSuper (custid INT)
		
	INSERT INTO #DepSuper 
	SELECT custid FROM f_DepSuper_1('All')
	 

	-------					 
	CREATE TABLE #Match (matchid INT,  matchcode NVARCHAR(50), type varchar(10), primary key(matchid, type))
							
	INSERT INTO #Match 
	SELECT	m.matchid, 
			m.matchcode, 
			m.type
	FROM (
			SELECT matchid, leagueid, matchcode, 'match' as type FROM match WITH (NOLOCK) WHERE eventdate = @winlostdate
			UNION ALL
			SELECT orid, leagueid, matchcode, 'outright' as type FROM outright WITH (NOLOCK) WHERE eventdate = @winlostdate
			)m	
			INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid	
	WHERE	l.SportType = 1  

	
	------------- get result --------------
	CREATE TABLE #TempBettrans (liveindicator BIT, Bettype INT, isHedge VARCHAR(20), site tinyint, WinLost MONEY, Position MONEY, Commission MONEY, RealLineTotal MONEY, VirtualLineTotal MONEY, RealTurnover MONEY, VirtualTurnover MONEY)
	INSERT INTO #TempBettrans	
	SELECT		
			liveindicator,
			b.Bettype,			
			case when m.matchcode like '%hedge%' then ' (hedge)' else '' end isHedge,
			case when dep.custid is null then 1 else 2 end as site,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
			sum((1-tpositiontaking)*ABS(stake)*actualrate) RealTurnover,
			sum((1-tpositiontaking)*ABS(stake)*virtualrate) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)	
		INNER JOIN #Match m on b.matchid = m.matchid
		inner join #SportBettype s ON s.bettype = b.bettype
		LEFT JOIN #DepSuper dep ON b.srecommend = dep.custid 	
	WHERE	b.winlostdate = @winlostdate
			AND b.matchid > 0		
			AND b.statusID NOT IN (101, 102,103) 
			AND ruben = 1	
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 		
	GROUP BY		
			liveindicator,
			b.Bettype,			
			case when dep.custid is null then 1 else 2 end ,
			case when m.matchcode like '%hedge%' then ' (hedge)' else '' end 
	


	------ BARM (site only)
	INSERT INTO #TempBettrans 
	SELECT
			liveindicator,
			b.Bettype,			
			case when m.matchcode like '%hedge%' then ' (hedge)' else '' end isHedge,
			3 as site,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
			sum((1-tpositiontaking)*ABS(stake)*actualrate) RealTurnover,
			sum((1-tpositiontaking)*ABS(stake)*virtualrate) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN #Match m on b.matchid = m.matchid
			INNER JOIN #SportBettype t ON t.bettype = b.bettype	
	WHERE	 b.recommend = 5707545 
			AND	b.winlostdate = @winlostdate
			AND b.matchid > 0		
			AND b.statusID NOT IN (101, 102,103) 
			AND ruben = 1	
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 	
	GROUP BY 
			liveindicator,
			b.Bettype,
			case when m.matchcode like '%hedge%' then ' (hedge)' else '' end 


	---- Update Credit = Credit - BARM, Deposit = Deposit + BARM
	UPDATE 	c
	SET		c.WinLost = ISNULL(c.WinLost,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.WinLost,0) ELSE ISNULL(d.WinLost,0) END,
			c.Position = ISNULL(c.Position,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.Position,0) ELSE ISNULL(d.Position,0) END,
			c.Commission = ISNULL(c.Commission,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.Commission,0) ELSE ISNULL(d.Commission,0) END,
			c.RealLineTotal = ISNULL(c.RealLineTotal,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.RealLineTotal,0) ELSE ISNULL(d.RealLineTotal,0) END,
			c.VirtualLineTotal = ISNULL(c.VirtualLineTotal,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.VirtualLineTotal,0) ELSE ISNULL(d.VirtualLineTotal,0) END,
			c.RealTurnover = ISNULL(c.RealTurnover,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.RealTurnover,0) ELSE ISNULL(d.RealTurnover,0) END,
			c.VirtualTurnover = ISNULL(c.VirtualTurnover,0) + CASE WHEN c.Site = 1 THEN - ISNULL(d.VirtualTurnover,0) ELSE ISNULL(d.VirtualTurnover,0) END
	FROM	#TempBettrans c
	FULL JOIN  #TempBettrans d
			ON	c.Bettype = d.Bettype
				AND c.isHedge = d.isHedge
				AND c.liveindicator = d.liveindicator
				AND d.Site = 3 
				AND c.site IN (1,2)


	-----Delete BARM row used for calculate
	DELETE #TempBettrans WHERE Site = 3

-------------------------	 

	SELECT	b.* 
	FROM	#TempBettrans b
	INNER JOIN #SportBettype bt ON b.bettype = bt.Bettype
	ORDER BY b.liveindicator, bt.DisplayOrder, b.Bettype, b.site, b.isHedge

----------------------------------
	CREATE TABLE #RM (liveindicator BIT, ibc TINYINT, WinLost MONEY, Position MONEY, Commission MONEY, RealLineTotal MONEY, VirtualLineTotal MONEY, RealTurnover MONEY, VirtualTurnover MONEY)
	
	INSERT INTO #RM (liveindicator, ibc, WinLost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover )
	SELECT	b.liveindicator, 
			CASE WHEN  b.recommend = 52466 THEN 1 ELSE 2 END AS ibc,
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,				
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN #Match m on b.matchid = m.matchid 	
			inner join #SportBettype s ON s.bettype = b.bettype
	WHERE	b.winlostdate = @winlostdate
			--AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999)
			AND b.matchid > 0 
			AND b.statusID NOT IN (101, 102,103) 
			AND b.ruben = 1		
			AND recommend IN ( 52466,5707545)
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120628@Elodie: check case of matchid = orid
	GROUP BY b.liveindicator , CASE WHEN  b.recommend = 52466 THEN 1 ELSE 2 END  	

	SELECT liveindicator, ibc, WinLost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover 
	FROM #RM
	WHERE ibc = 1

	
	SELECT liveindicator, ibc, WinLost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover 
	FROM #RM
	WHERE ibc = 2

	--------------------------------

DROP TABLE #TempBettrans
DROP TABLE #DepSuper
DROP TABLE #RM

END 

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Soccer_Bettype] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Soccer_Bettype] TO [vnteam]