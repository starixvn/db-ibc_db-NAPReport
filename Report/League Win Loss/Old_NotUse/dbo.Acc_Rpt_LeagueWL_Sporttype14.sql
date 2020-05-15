
ALTER PROCEDURE [dbo].[Acc_Rpt_LeagueWL_Sporttype14]
@winlostdate	datetime, 
@WinLost_8RM	money OUTPUT,
@WinLost_BARM	money = 0 OUTPUT
AS
/*	Creator: KhoaTran
		Date: 2009-10-31
		Task: view winlost of company by sporttype and leagues
		DB: DB06.bodb02	
			
		History:			
		- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20100611@Henry: Change mix-parlay match from 0 to 9
		- 20110822@Elly: - Correct Turnover of sports book since Sep 01, 2011
		- 20110516@Lukas: re-arrange bettype
		- 20111202@Sophia: . Add new range for sportbook from 121 to 999
						   . Remove @NegativeBetEffectiveDate
		- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
		- 20120530@Elodie: Change formula of 8RM/BARM winloss
		- 20120628@Elodie: check case of matchid = orid
		- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20150526@Sophia: Apply Sport Bettype Matrix [#34486]
		- 20150723@Sophia: Exclude data of Bettrade [#38815]
		- 20160125@Robert: Cricket - Integrate to Accounting Reports [#50274]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
		
		Explanation's Param:
			- @winlostdate: the date want to view report
			- @WinLost_8RM: winlost out source
			- @WinLost_BARM: winlost for outsource (We use agent 'BARM' to put all outsoucing transactions which follow BA danger customers)
			
*/
	
BEGIN
SET NOCOUNT ON
	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT, SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode = 5, @ProductID = 1

	DELETE	@SportBettype  
	WHERE	(SubProduct IN ('BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss'))

		
	--Declare @temp table to contain all matches based on @winlostdate
	DECLARE @Match TABLE (matchid INT, sporttype smallint, leagueid int, type varchar(10), primary key(matchid, type))

	INSERT INTO @Match 
	SELECT	m.matchid, 
			l.sporttype,
			l.leagueid, 
			m.type
	FROM (
			SELECT matchid, leagueid, 'match' as type  FROM dbo.match14 WITH (NOLOCK) WHERE eventdate = @winlostdate
			UNION ALL
			SELECT orid, leagueid, 'outright' as type FROM dbo.outright14 WITH (NOLOCK) WHERE eventdate = @winlostdate
		)m	
	INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid	
	WHERE l.sporttype<=99

SELECT * FROM 
(
	SELECT
			
			m.sporttype,			
			0 Bettype,
			m.leagueid,			
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
			sum((1-tpositiontaking)*virtualrate* ABS(b.stake)) Turnover
	FROM	dbo.bettrans14 b WITH (NOLOCK)
		INNER JOIN @SportBettype s 
			ON s.Bettype = b.bettype
		INNER JOIN @Match m 
			ON b.matchid = m.matchid			
	WHERE	b.winlostdate = @winlostdate
			---AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR bettype BETWEEN 1301 and 1334) 
			AND b.matchid > 0 
			AND b.ruben = 1	
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120628@Elodie: check case of matchid = orid																
			AND m.sporttype <> 50
	GROUP BY						
			m.sporttype,				
			m.leagueid

	UNION ALL
	
		SELECT
			
			m.sporttype,			
			b.Bettype,
			m.leagueid,			
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
			sum((1-tpositiontaking)*virtualrate* ABS(b.stake)) Turnover
	FROM	dbo.bettrans14 b WITH (NOLOCK)
		INNER JOIN @SportBettype s 
			ON s.Bettype = b.bettype
		INNER JOIN @Match m 
			ON b.matchid = m.matchid			
	WHERE	b.winlostdate = @winlostdate
			---AND (b.bettype < 31 OR b.bettype BETWEEN 121 AND 999 OR bettype BETWEEN 1301 and 1334) 
			AND b.matchid > 0 
			AND b.ruben = 1	
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END -- 20120628@Elodie: check case of matchid = orid																
			AND m.sporttype = 50
	GROUP BY						
			m.sporttype,	
			b.Bettype,			
			m.leagueid

	UNION ALL
	
	SELECT 
			 100, 9, 0,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
			sum((1-tpositiontaking)*virtualrate*ABS(stake)) Turnover
	FROM	dbo.bettrans14 WITH (NOLOCK)
	WHERE
			winlostdate = @winlostdate
			AND bettype = 9
			--AND matchid = 0 
			AND matchid = 9
			AND ruben = 1
			--AND status NOT IN ('VOID', 'REJECT','REFUND') 
			AND statusID NOT IN (101, 102, 103) 				
) wl
	Order By wl.sporttype, wl.Bettype, wl.leagueid			

	SELECT	@WinLost_8RM = -isnull(sum((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*virtualrate), 0) 
	FROM	dbo.bettrans14 b WITH (NOLOCK)
	WHERE 
			recommend = 52466 and
			winlostdate = @winlostdate and
			bettype < 19001 and
			matchid >=0 and 
			ruben=1 and
			--status NOT IN ('VOID', 'REJECT','DONE','REFUND')
			 b.statusID NOT IN (101, 102, 103) 
			 
	-- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
	SELECT	@WinLost_BARM = -isnull(sum((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*virtualrate), 0) 
	FROM	dbo.bettrans14 b WITH (NOLOCK)
	WHERE 
			recommend = 5707545 and
			winlostdate = @winlostdate and
			bettype < 19001 and
			matchid >=0 and 
			ruben=1 and
			--status NOT IN ('VOID', 'REJECT','DONE','REFUND')
			 b.statusID NOT IN (101, 102, 103)
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_LeagueWL_Sporttype14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LeagueWL_Sporttype14] TO [vnteam]