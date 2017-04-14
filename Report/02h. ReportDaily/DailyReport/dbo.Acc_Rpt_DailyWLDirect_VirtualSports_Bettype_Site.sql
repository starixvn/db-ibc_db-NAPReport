ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_VirtualSports_Bettype_Site]
	@winlostdate datetime,
	@sporttype	int,
	@bettype	int,
	@site		tinyint
AS
/*	Creator: Johnson
	Date: 2013-08-01
	Task: Winloss Summary of Virtual sports by site
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
	
	IF @bettype IN  (1231, 1232, 1233, 1237, 1238)
	BEGIN
		SELECT		
				ag.site,
				sum((winlost-actual_stake)*actualrate) WinLost,
				sum((awinlost+mwinlost+swinlost)*actualrate) Position,
				sum(scomm*actualrate) Commission,	
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
				sum((1-tpositiontaking)* stake * actualrate) RealTurnover,
				sum((1-tpositiontaking)* stake * virtualrate) VirtualTurnover
		FROM	bettrans b WITH (NOLOCK)
				INNER JOIN VSRaceInfo r ON r.EventID = b.matchid
				INNER JOIN #DepAgent ag ON b.recommend = ag.custid
		WHERE
				winlostdate = @winlostdate
				AND b.bettype = @bettype
				AND b.matchid > 0 			
				AND b.statusID NOT IN (101, 102, 103) --('VOID', 'REJECT','REFUND') 
				AND b.ruben = 1			
				and r.sporttype = @sporttype
		GROUP BY ag.site
		ORDER BY ag.site	
	END
	ELSE BEGIN	
		SELECT		
				ag.site,
				sum((winlost-actual_stake)*actualrate) WinLost,
				sum((awinlost+mwinlost+swinlost)*actualrate) Position,
				sum(scomm*actualrate) Commission,	
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) RealLineTotal,
				sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) VirtualLineTotal,
				sum((1-tpositiontaking)* stake * actualrate) RealTurnover,
				sum((1-tpositiontaking)* stake * virtualrate) VirtualTurnover
		FROM	bettrans b WITH (NOLOCK)
				INNER JOIN match m on b.matchid = m.matchid
				INNER JOIN #DepAgent ag ON b.recommend = ag.custid
		WHERE
				winlostdate = @winlostdate
				AND b.bettype = @bettype
				AND b.matchid > 0 			
				AND b.statusID NOT IN (101, 102, 103) --('VOID', 'REJECT','REFUND') 
				AND b.ruben = 1
				and m.sporttype = @sporttype
		GROUP BY ag.site
		ORDER BY ag.site
	END
	
	DROP TABLE #DepAgent
END



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_VirtualSports_Bettype_Site] TO [bodbAdminNet]

