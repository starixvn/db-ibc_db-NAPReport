  ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Bingo_Bettype_Site14]
	@winlostdate	datetime,	
	@site			TINYINT
AS
	/*	Creator: Johnson
		Date: 2013-08-02
		Task: Bingo WinLost Summary report by site
		DB: DBACC/bodb02
		
		Revisions:
			- 20130906@Johnson: get virtual values by virtual rate instead of actual rate			
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
	
	SELECT		
			ag.site,
			sum((winlost-actual_stake)*actualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
			0 RealTurnover,
			0 VirtualTurnover
	FROM	bettrans14 b WITH (NOLOCK)
		INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE	b.winlostdate = @winlostdate
			AND b.bettype = 73
			AND b.matchid in (0, 73) 
			AND b.statusID NOT IN (102, 101,121,103) 
			AND b.ruben = 1		
	GROUP BY ag.site
	ORDER BY ag.site
	
	DROP TABLE #DepAgent
END



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Bingo_Bettype_Site14] TO [bodbAdminNet]