ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Sporttype_Bettype_Site14]
	@winlostdate	datetime,
	@SportType		int = 1,
	@liveindicator	bit,
	@bettype		int,
	@site			int,
	@isHedge		bit =0
AS

	/*	Creator: Johnson
		Date: 2013-07-31
		Task: Report winlost summary 
		DB: DBACC/bodb02 
		
		Revisions:
			-20160630@Sophia: Enhance Performance [Redmind: #59190]
		
		Parameter's Explanation:
			- @site: 1: credit
					2: deposit
			- @isHedge: match hedge			
	*/
SET NOCOUNT ON
	--Declare @temp table to contain all matches
	DECLARE @Match TABLE (matchid int)
	CREATE TABLE #DepAgent (custid int primary key , site varchar(50))
	
	IF @Site = 2 --- Deposit 
	BEGIN 

		INSERT INTO #DepAgent (custid, site)
		SELECT	c.custid, site
		FROM	customer c WITH(NOLOCK)
		WHERE	srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
				AND roleid = 2								
		UNION ALL
		SELECT 5707545,'BEST-ODDS'  --BARM
	END 
	ELSE ---Credit
	BEGIN 

		INSERT INTO #DepAgent (custid, site)
		SELECT	c.custid, site
		FROM	customer c WITH(NOLOCK)
		WHERE	NOT EXISTS (SELECT custid FROM f_DepSuper_1('All') d WHERE c.srecommend = d.CustID )
				AND roleid = 2	
				AND c.custid NOT IN (52466,5707545)--8RM, BARM				
		UNION ALL
		SELECT 52466,'XYZBET'--8RM
	END 

	  		
	IF @bettype = 10 
	BEGIN 
		INSERT INTO @Match
		SELECT	m.matchid
		FROM 
			(	
				SELECT	orid as matchid , leagueid, 'outright' as type 
				FROM	dbo.outright14 WITH (NOLOCK)  
				WHERE	eventdate = @winlostdate
			) m
		INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		WHERE	l.sporttype = @sporttype 			 

	END 
	ELSE 
	BEGIN 
		INSERT INTO @Match
		SELECT	matchid
		FROM	dbo.match14 WITH (NOLOCK) 
		WHERE
			eventdate = @winlostdate		
			AND sporttype = @sporttype 	
			AND exrisk = 0
			AND 1 = case when @isHedge = 1 and matchcode like '%Hedge%' then 1 
					when @isHedge = 0 and matchcode not like '%Hedge%' then 1 else 0 end					
		 
	END 
		
			
	SELECT ag.site,
		sum((winlost-actual_stake)*virtualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
		sum(scomm*virtualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
		sum((1-tpositiontaking)* ABS(stake) * actualrate) RealTurnover,
		sum((1-tpositiontaking)* ABS(stake) * virtualrate) VirtualTurnover
	FROM bettrans14 b with(NOLOCK)
		INNER JOIN @Match m ON b.matchid = m.matchid
		INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE winlostdate = @winlostdate
		AND b.bettype = @bettype				
		AND b.statusID NOT IN (101, 102,103) 
		AND b.ruben = 1
		AND b.liveindicator = @liveindicator
	GROUP BY site
	ORDER BY site
	
	DROP TABLE #DepAgent
	
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Sporttype_Bettype_Site14] TO [bodbAdminNet]
