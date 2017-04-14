  ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_LiveCasino_Bettype_Site14]
	@winlostdate DATETIME,
	@bettype	INT,
	@site		TINYINT
 AS
	/*
		Creator: Johnson
		Date: 2013-08-02
		Task: Report winlost summary for live casino by site
		DB: DBACC/bodb02 
		
		Revisions:
			- 20130906@Johnson: get virtual values by virtual rate instead of actual rate			
			- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
		Parameter's Explanation:
			- @site: 1: credit
					2: deposit	
	*/
BEGIN	
	SET NOCOUNT ON
	CREATE TABLE #DepAgent (custid int primary key , site varchar(50))
	
	INSERT INTO #DepAgent (custid, site)
	SELECT c.custid, site
	FROM customer c WITH(NOLOCK)
		LEFT JOIN (select custid from f_DepSuper_1('All')) dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid, site)
	SELECT 52466,'XYZBET' WHERE @site = 1--8RM
	UNION
	SELECT 5707545,'BEST-ODDS' WHERE @site =2 --BARM
		
	SELECT	ag.site,
		sum((winlost-actual_stake)*actualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
		sum((1-tpositiontaking)*stake*actualrate) RealTurnover,
		sum((1-tpositiontaking)*stake*virtualrate) VirtualTurnover
	FROM	bettrans14 b WITH (NOLOCK)
		INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE	b.winlostdate = @winlostdate
			AND (b.bettype = @bettype AND bettype NOT BETWEEN 2401 and 2499) -- exclude AllBet
			AND b.ruben = 1		
			AND b.statusID not in (101,102,103,121)			
	GROUP BY site
	
	UNION ALL -- AllBet Data
	
	SELECT	ag.site,
		sum((winlost-actual_stake)*actualrate) WinLost,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
		sum((1-tpositiontaking)*stake*actualrate) RealTurnover,
		sum((1-tpositiontaking)*stake*actualrate) VirtualTurnover
	FROM	bettransLC14 b WITH (NOLOCK)
		INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE	b.winlostdate = @winlostdate
			AND b.gameID = @bettype			
			AND b.statusID not in (0,1,101,102,103,121)
			AND productID = 211 -- AllBet data
	GROUP BY site
	ORDER BY site

	DROP TABLE #DepAgent
END

	
	
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_LiveCasino_Bettype_Site14] TO [bodbAdminNet]
	