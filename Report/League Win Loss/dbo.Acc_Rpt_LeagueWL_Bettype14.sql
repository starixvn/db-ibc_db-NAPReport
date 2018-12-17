/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_LeagueWL_Bettype14]
	@winlostdate	DATETIME,
	@leagueid INT,
	@sporttype INT
AS

/*	Creator: KhoaTran
		Date: 2009-10-31
		Task: view winlost of company by bettype
		DB: DB06.bodb02	
			
		Revisions:			
		-- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
		-- 20100820@Lukas: Add new bet type: 1st Money Line (only for baseball game) bettypeID = 21
		- 20110824@Elly: - Correct Turnover of sports book since Sep 01, 2011
		-- 20110826@Lukas: Modify to get bettype automatically
		-- 20111202@Sophia: . Add new range for sportbook from 121 to 999
							. Remove @NegativeBetEffectiveDate
		-- 20120412@Hurri: Get win lost of agent 'BARM'
		-- 20120530@Elodie: Change formula of 8RM/BARM winloss
		-- 20120628@Elodie: Check case of matchid = orid
							Expand the size of match code to varchar(50)
		-- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		-- 20121112@Elodie: Use stake field to calculate TurnOver instead of actual_stake
		-- 20150526@Sophia: Apply Sport Bettype Matrix [#34486]	
		-- 20150723@Sophia: Exclude data of Bettrade [#38815]	
		-- 20150922@Jim: offer MO	
		-- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		- 20170831@Cherry: Extend data type of Sporttype (#73545)
		- 20181214@Jacob: Include ESports Bet Type #100635
		Explanation's Param:
			- @winlostdate: the date want to view report
			- @leagueid   : the leagueid want to view report
			- @sporttype  : the sporttype want to view report
*/

SET NOCOUNT ON
BEGIN	

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT, SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode = 5, @ProductID = 1

	DELETE	@SportBettype  
	WHERE	(SubProduct IN ('BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss'))
	
	 
	--Declare @temp table to contain all matches based on @winlostdate
	DECLARE @Match TABLE (matchid INT, sporttype INT, leagueid INT, matchcode VARCHAR(50), type varchar(10), primary key(matchid, type))
	INSERT INTO @Match 
	SELECT	m.matchid, 
			l.sporttype,
			l.leagueid,
			m.matchcode,
			m.type
	FROM (
			SELECT matchid, leagueid, matchcode, 'match' as type  FROM match14 WITH (NOLOCK) WHERE eventdate = @winlostdate
			UNION ALL
			SELECT orid, leagueid, matchcode, 'outright' as type FROM outright14 WITH (NOLOCK) WHERE eventdate = @winlostdate
		)m	
	INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid	
	WHERE l.leagueid = @leagueid
	AND l.sporttype = @sporttype

Declare @tmpBettype table (	Bettype	INT primary key, DisplayOrder	int)

	Insert INTo @tmpBettype
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

--	UNION ALL
--	SELECT 11,  11 --'Total Corners',
--	UNION ALL
--	SELECT 12,  12 --'1st Odd/Even',
--	UNION ALL
--	SELECT 13,  13 --'Clean Sheet',
--	UNION ALL
--	SELECT 14, 14 --'First Goal/Last Goal', 
--	UNION ALL
--	SELECT 15, 15 --'1st 1X2', 
--	UNION ALL
--	SELECT 16,  16 --'HT/FT',
--	UNION ALL
--	SELECT 20,  20 -- 'Money Line',
--	UNION ALL 
--	SELECT 22, 22 -- 'Next Goal',
--	UNION ALL
--	SELECT 21, 21 -- '1st Money Line'

	INSERT INTO @tmpBettype
		SELECT typeid, typeid
		FROM bettype b WITH(NOLOCK)
		INNER JOIN @SportBettype s 
				ON b.typeid = s.Bettype
		WHERE (typeid > 10 AND typeid < 31)OR (typeid BETWEEN 121 AND 999 and b.typeid NOT IN (301,302,303,304)) OR typeid BETWEEN 1301 AND 1334 OR typeid BETWEEN 9001 AND 9399

	SELECT		
			b.liveindicator,
			bt.Bettype,
			CASE WHEN m.matchcode like '%hedge%' THEN ' (hedge)' ELSE '' END isHedge,
			SUM((winlost-actual_stake)*virtualrate) WinLost,
			SUM((awinlost+mwinlost+swinlost)*virtualrate) Position,
			SUM(scomm*virtualrate) Commission,	
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
			SUM((1-tpositiontaking)*virtualrate*ABS(stake)) Turnover
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN @Match m on b.matchid = m.matchid			
			INNER JOIN @tmpBettype bt ON b.bettype = bt.Bettype
			INNER JOIN @SportBettype s ON b.bettype = s.Bettype	
	WHERE
			b.winlostdate = @winlostdate
			---AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 1301 AND 1334) 
			AND b.matchid > 0 
			--AND b.status NOT IN ('VOID', 'REJECT', 'Refund') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND b.ruben = 1		
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120628@Elodie: check case of matchid = orid				
	GROUP BY		
			b.liveindicator,
			bt.Bettype, 
			CASE WHEN m.matchcode like '%hedge%' THEN ' (hedge)' ELSE '' END ,	
			bt.DisplayOrder
		
	ORDER BY
			b.liveindicator, bt.DisplayOrder

	SELECT	b.liveindicator, -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*virtualrate) Winlost8RM
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN @Match m on b.matchid = m.matchid	
			INNER JOIN @SportBettype s ON b.bettype = s.Bettype				 
	WHERE
			b.winlostdate = @winlostdate
			---AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 1301 AND 1334) 
			AND b.matchid > 0 
			--AND status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND b.ruben = 1					
			and recommend = 52466
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120628@Elodie: check case of matchid = orid				
	GROUP BY b.liveindicator

	-- 20120412@Hurri: Get win lost of agent 'BARM'
	SELECT	b.liveindicator, -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*virtualrate) WinlostBARM
	FROM	bettrans14 b WITH (NOLOCK)
			INNER JOIN @Match m on b.matchid = m.matchid	
			INNER JOIN @SportBettype s ON b.bettype = s.Bettype				 
	WHERE
			b.winlostdate = @winlostdate
			---AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 1301 AND 1334) 
			AND b.matchid > 0 
			--AND status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND b.ruben = 1					
			and recommend = 5707545
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120628@Elodie: check case of matchid = orid				
	GROUP BY b.liveindicator
END

GO
