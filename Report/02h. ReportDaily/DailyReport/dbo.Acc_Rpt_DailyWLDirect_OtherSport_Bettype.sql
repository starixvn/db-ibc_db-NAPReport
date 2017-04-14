ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_OtherSport_Bettype]
	@winlostdate	datetime,
	@sporttype int
AS
SET NOCOUNT ON

/*	Creator: Phuong Dao
	Date: 2009-02-26
	Task: Winloss Summary History
	DB: DBACC/bodb02

	Revisions:
		- 20090731@Jamie: Not to view data in range of date, but only one date at once
		- 20091109@Kiwi: Declare @temp table to contain all matches based on @winlostdate and @sporttype	
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		-- 20100819@Lukas: Add new bet type - 1st Money Line (only for Baseball game) - bettypeID = 21
		- 20100917@Henry: Include Number Game
		- 20101204@Johnson: Exclude Number Game
		- 20101204@Johnson: Exclude Number Game
		- 16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
		- 20110824@Elly: - Correct Turnover of sports book since Sep 01, 2011
		- 20110826@Lukas: Modify to get bettype automatically
		- 20111202@Sophia: . Add new range for sportbook from 121 to 999
						   . Remove @NegativeBetEffectiveDate
		- 20120412@Hurri: Get win lost of agent 'BARM'
		- 20120530@Elodie: Change formula of 8RM/BARM winloss
		- 20120626@Elodie: check case of matchid = orid
		- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20130408@Elodie: Add RealLineTotal field for all products that enable virtual currency
		- 20130522@Elodie: Get more fields RealTurnover, VirtualTurnover
		- 20130731@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)				 
		- 20150122@Dom: Apply sport bettype matrix
		- 20150205@Johnson: show more info of 8RM(winlost, comm, turnover) [redmineID: #27216]
		- 20150525@Sophia: Apply Metric Gaming - SuperLive and revise Sport Betype Matrix [#35359]
		- 20150723@Sophia: Exclude data of Bettrade [#38815]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
*/
BEGIN
	
	SET NOCOUNT ON

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC Acc_SportBettypeMatrix_Sel @mode = 5, @ProductId = 1

	DELETE	@SportBettype  
	WHERE	SubProduct IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss')
			OR EventType NOT IN (1,2)


	DECLARE @tmpBettype TABLE (Bettype INT PRIMARY KEY, DisplayOrder INT)
	CREATE TABLE #DepAgent (custid INT PRIMARY KEY)
		
	INSERT INTO #DepAgent 
	SELECT custid
	FROM custInfo with(NOLOCK)
	WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
		AND roleid = 2	
	UNION
	SELECT 5707545--BARM	
		
	Insert into @tmpBettype
	select 1, 1 --'Handicap'
	UNION ALL
	Select 3, 2 --'Over/Under'
	UNION ALL
	select 7, 3 --'1st Half Handicap'
	UNION ALL
	Select 8, 4 -- '1st Half Over/Under',
	UNION ALL
	select 2, 5 -- 'Odd/Even',
	UNION ALL
	select 5, 6 -- '1x2',
	UNION ALL
	Select 4, 7 --'Correct Score',
	UNION ALL
	Select 6, 8 --'Total Goal',
	UNION ALL
	Select 10, 10 -- 'Outright',
	
--	UNION ALL
--	Select 11, 11 --'Total Corners',
--	UNION ALL
--	Select 12, 12 --'1st Odd/Even',
--	UNION ALL
--	Select 13, 13 --'Clean Sheet',
--	UNION ALL
--	Select 14, 14 --'First Goal/Last Goal',
--	UNION ALL
--	Select 15, 15 --'1st 1X2',
--	UNION ALL
--	Select 16, 16 --'HT/FT',
--	UNION ALL 
--	SELECT 20, 20 --'Money Line'
--	UNION ALL
--	SELECT 21, 21 -- '1st Money Line'
	
	INSERT INTO @tmpBettype
		SELECT typeid, typeid
		FROM bettype b WITH(NOLOCK)
		WHERE (typeid > 10 AND typeid < 31) OR typeid BETWEEN 121 AND 999 OR typeid BETWEEN 1301 AND 1334

	
	--Declare @temp table to contain all matches
	DECLARE @Match TABLE (matchid int, type varchar(10), primary key(matchid, type))
	INSERT INTO @Match
	SELECT	m.matchid,
			m.type
	FROM 
		(	select matchid, leagueid, exrisk, 'match' as type from match with (nolock) where eventdate = @winlostdate
			union all
			select orid, leagueid, 0, 'outright' as type from outright with (nolock) where eventdate = @winlostdate
		) m
	INNER JOIN league l with (nolock) ON m.leagueid = l.leagueid
	INNER JOIN sports sp with (nolock) ON l.sporttype = sp.sporttype
	WHERE	sp.sporttype = @sporttype 
			AND ExRisk = 0

	SELECT		
			b.liveindicator,
			bt.Bettype,
			case when dep.custid is null then 1 else 2 end as site,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
			sum((1-tpositiontaking)* ABS(stake) * actualrate) RealTurnover,
			sum((1-tpositiontaking)* ABS(stake) * virtualrate) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @Match m on b.matchid = m.matchid
			INNER JOIN @tmpBettype bt ON b.bettype = bt.Bettype
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
			LEFT JOIN (SELECT custid FROM #DepAgent) dep ON b.recommend = dep.custid
	WHERE	b.winlostdate = @winlostdate
			--AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 1301 and 1334)
			AND s.ProductID = 1
			AND b.matchid > 0 
			--AND status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102,103) 
			AND b.ruben = 1
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120626@Elodie: check case of matchid = orid
	GROUP BY		
			b.liveindicator,
			bt.Bettype,
			bt.DisplayOrder,
			case when dep.custid is null then 1 else 2 end 
	ORDER BY
			b.liveindicator, 
			bt.DisplayOrder,
			site
	
	SELECT	b.liveindicator, 
			1 as ibc,--8RM
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,	
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @Match m on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
	WHERE	b.winlostdate = @winlostdate
			--AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 1301 and 1334)
			AND s.ProductID = 1
			AND b.matchid > 0 
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102,103) 
			AND b.ruben = 1
			AND b.recommend = 52466
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120626@Elodie: check case of matchid = orid
	GROUP BY b.liveindicator	
		
	-- 20120412@Hurri: Get win lost of agent 'BARM'
	SELECT	b.liveindicator, 
			2 as ibc,--8RM
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,	
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @Match m on b.matchid = m.matchid
			INNER JOIN @SportBettype s ON s.bettype = b.bettype
	WHERE	b.winlostdate = @winlostdate
			--AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR bettype BETWEEN 1301 and 1334)
			AND s.ProductID = 1
			AND b.matchid > 0 
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102,103) 
			AND b.ruben = 1
			AND b.recommend = 5707545
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120626@Elodie: check case of matchid = orid
	GROUP BY b.liveindicator
	
	DROP TABLE #DepAgent
	
END	
	
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_OtherSport_Bettype] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_OtherSport_Bettype] TO [vnteam]