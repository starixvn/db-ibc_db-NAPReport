ALTER PROCEDURE [dbo].[Acc_Rpt_LeagueWL_Details]
	@winlostdate	DATETIME, 
	@leagueid		INT, 
	@sporttype		INT, 
	@bettype		INT, 
	@liveindicator	BIT, 
	@IsHedge		BIT,
	@WinLost_8RM	MONEY OUTPUT,
	@WinLost_BARM	MONEY = 0 OUTPUT
AS
/*	Creator: KhoaTran
		Date: 2009-10-31
		Task: view winlost of company by sporttype ==> leagues ==> bettype ==> details
		DB: DB06.bodb02	
			
		History:			
		- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20110516@Lukas: re-arrange bettype
		- 20110822@Elly: - Correct Turnover of sports book since Sep 01, 2011
		- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
		- 20120423@Hurri: Remove @NegativeBetEffectiveDate='2011-09-01'
		- 20120530@Elodie: Change formula of 8RM/BARM winloss
		- 20120628@Elodie: Expand the size of match code to varchar(50)

		Explanation's Param:
			- @winlostdate : the date want to view report   
			- @leagueid	   : leagueid	
			- @sporttype   : sporttype
			- @bettype     : bettype
			- @liveindicator: liveindicator
			- @IsHedge     : ishedge
			- @WinLost_8RM :out source
			- @WinLost_BARM: winlost for outsource (We use agent 'BARM' to put all outsoucing transactions which follow BA danger customers)
*/
	
BEGIN
SET NOCOUNT ON

	--DECLARE @NegativeBetEffectiveDate datetime
	--SET @NegativeBetEffectiveDate='2011-09-01'

	--Declare @temp table to contain all matches based on @winlostdate exclude outright
	DECLARE @Match TABLE (matchid INT PRIMARY KEY, sporttype smallint, leagueid INT, matchcode varchar(50), HomeId INT, Awayid INT, isNeutral BIT)

	IF @IsHedge = 1
	BEGIN
		INSERT INTO @Match 
		SELECT	m.matchid, 
				l.sporttype,
				l.leagueid,
				m.matchcode,
				m.homeid,
				m.awayid,
				ISNULL(m.isNeutral,0)
		FROM 
		match m WITH (NOLOCK) 		
		INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid			
		WHERE eventdate = @winlostdate
		AND matchcode like '%hedge%' 
		AND l.SportType = @SportType
		AND l.leagueid = @leagueid					
	END
	ELSE
	BEGIN
		INSERT INTO @Match 
		SELECT	m.matchid, 
				l.sporttype,
				l.leagueid,
				m.matchcode,
				m.homeid,
				m.awayid,
				ISNULL(m.isNeutral,0)
		FROM 
		match m WITH (NOLOCK) 		
		INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid			
		WHERE eventdate = @winlostdate
		AND matchcode NOT like '%hedge%' 
		AND l.SportType = @SportType
		AND l.leagueid = @leagueid					
	END



	--Declare @temp table to contain all matches based on @winlostdate for outright
	DECLARE @Outright_Tmp TABLE (orid INT PRIMARY KEY, sporttype smallint, leagueid INT, matchcode varchar(20), TeamId INT)
	INSERT INTO @Outright_Tmp 
	SELECT	o.orid, 
			l.sporttype,
			l.leagueid,
			ISNULL(o.matchcode,''),
			o.TeamId
	FROM 
	outright o WITH (NOLOCK) 			
	INNER JOIN league l WITH (NOLOCK) ON o.leagueid = l.leagueid		
	WHERE eventdate = @winlostdate
	AND l.SportType = @SportType
	AND l.leagueid = @leagueid					

	--Declare @temp table to contain all matches based on @winlostdate FOR WINLOST_8RM
	DECLARE @Match_8RM TABLE (matchid INT PRIMARY KEY, sporttype smallint, leagueid int)
	INSERT INTO @Match_8RM 
	SELECT	m.matchid, 
			l.sporttype,
			l.leagueid
	FROM (
			SELECT matchid, leagueid  FROM match WITH (NOLOCK) WHERE eventdate = @winlostdate
			UNION ALL
			SELECT orid, leagueid FROM outright WITH (NOLOCK) WHERE eventdate = @winlostdate
		)m	
	INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid		
	WHERE  l.SportType = @SportType
	AND l.leagueid = @leagueid	

	IF @bettype <> 10
		BEGIN
			SELECT
					m.matchcode,
					m.HomeId,
					m.AwayId,
					b.liveindicator,
					b.BetType , 
					m.leagueid,					
					SUM((winlost-actual_stake)*virtualrate) WinLost,
					SUM((awinlost+mwinlost+swinlost)*virtualrate) Position,
					SUM(scomm*virtualrate) Commission,
					SUM((1-tpositiontaking)*ABS(b.stake)*virtualrate) Turnover,
					SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
					ISNULL(m.isNeutral, CONVERT(BIT,0)) AS IsNeutral
			FROM 
					bettrans b WITH (nolock)
					INNER JOIN @Match m ON b.matchid = m.matchid
			WHERE
					winlostdate = @winlostdate
					AND b.bettype < 19001
					AND b.matchid > 0
					--AND status NOT IN ('VOID', 'REJECT', 'Refund') 
					AND b.statusID NOT IN (101, 102, 103) 
					AND b.ruben = 1								
					AND b.BetType = @Bettype
					AND b.liveindicator = @liveindicator											
			GROUP BY
					m.matchcode,
					m.HomeId,
					m.AwayId,
					b.liveindicator,
					b.bettype, 
					m.leagueid,
					m.isNeutral
			ORDER BY 
					b.liveindicator,
					b.BetType, 
					m.leagueid,
					m.matchcode, 
					m.HomeId
			
				
	END
	ELSE
	BEGIN
		SELECT
				o.matchcode,
				o.TeamId AS HomeId,
				0 AS AwayId,
				0 liveindicator,
				b.BetType , 
				o.leagueid,
				SUM((winlost-actual_stake)*virtualrate) WinLost,
				SUM((awinlost+mwinlost+swinlost)*virtualrate) Position,
				SUM(scomm*virtualrate) Commission,
				SUM((1-tpositiontaking)*ABS(b.stake)*virtualrate) Turnover,
				SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
				CONVERT(BIT,0) AS IsNeutral
		FROM
				bettrans b WITH (nolock)
				INNER JOIN @Outright_Tmp o ON b.matchid = o.orid
				
		WHERE
				winlostdate = @winlostdate
				--AND b.status NOT IN ('VOID', 'REJECT', 'Refund') 
				AND b.statusID NOT IN (101, 102, 103) 
				AND b.ruben = 1	
				AND b.matchid > 0 				
				AND b.bettype = 10				
		GROUP BY
				o.matchcode,
				o.TeamId,
				b.bettype, 
				o.leagueid
		ORDER BY 
				b.BetType, 
				o.leagueid,
				o.matchcode, 
				HomeId
	END	

	SELECT	@WinLost_8RM = -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*virtualrate) 
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @Match_8RM m ON
			b.matchid = m.matchid
	WHERE
			b.winlostdate = @winlostdate
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND b.ruben = 1
			AND b.matchid > 0			
			AND b.liveindicator = @liveindicator		
			AND b.recommend = 52466		
			AND b.BetType = @Bettype
				
	-- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
	SELECT	@WinLost_BARM = -SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm)*virtualrate) 
	FROM	bettrans b WITH (NOLOCK)
			INNER JOIN @Match_8RM m ON
			b.matchid = m.matchid
	WHERE
			b.winlostdate = @winlostdate
			--AND b.status NOT IN ('VOID', 'REJECT','REFUND') 
			AND b.statusID NOT IN (101, 102, 103) 
			AND b.ruben = 1
			AND b.matchid > 0			
			AND b.liveindicator = @liveindicator		
			AND b.recommend = 5707545		
			AND b.BetType = @Bettype
END



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_LeagueWL_Details] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LeagueWL_Details] TO [vnteam]