USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyParlayWinloss]
	@FromDate datetime,
	@ToDate datetime,
	@site	tinyint = 0 
AS
/*	Creator: Elodie
	Date: 20121016
	Task: Daily parlay winloss report
	DB: DBACC/bodb02

	Revisions: 		
		- 20121203@Elodie: Get data between @FromDate AND @ToDate
		- 20121217@Lukas: exclude UUS currency
		- 20130402@Dom.Cao: add turnoverp
		- 20130805@Johnson: filter by site
		- 20160826@Percy: Enhance System/Mix Parlay [RedmineID: #63022]
	Parameter's Explanation:
		- Combinations: Bettrans.betcheck is stored the number of selection by format 'm4', 'm3' ...
		- LiveType (Livehomescore):
			0: Non Live : All bets are Dead Ball 
			1: Live: All bets are Live Ball 
			2: Mix Live and Non Live: contains Live and Dead Ball
		- @site:
			0: all sites
			1: credit sites
			2: deposit sites

*/
SET NOCOUNT ON 

IF @site = 0
BEGIN 
	SELECT 
			CASE bettype
				WHEN  9 THEN CASE WHEN RAND() + 1 > 0 AND betcheck in ('m2','m3','m4','m5') THEN betcheck ELSE 'm6' END
				WHEN 29 THEN CASE WHEN RAND() + 1 > 0 AND CONVERT(INT, hdp2) < 6 THEN 'm' + CONVERT(VARCHAR(10), CONVERT(INT, hdp2)) ELSE 'm6' END END AS Combinations, 
			livehomescore as LiveType,
			[status], 
			sum((winlost-actual_stake)*actualrate) WinLost,
			SUM(stake*actualrate) turnoverp,
			count(1) BetCount,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
			sum((1-tpositiontaking)*(ABS(stake)*actualrate)) Turnover	
	FROM	bettrans WITH (NOLOCK)
	WHERE
			ruben=1 AND
			bettype IN (9, 29) AND matchid IN (9, 29) AND -- prevent page split
			N'1' = CASE WHEN bettype = 29 THEN betteam ELSE N'1' END AND
			winlostdate between @FromDate AND @ToDate and 
			statusID NOT IN (101,102,103) AND
			currency <> 20
	GROUP BY  CASE bettype
				WHEN  9 THEN CASE WHEN RAND() + 1 > 0 AND betcheck in ('m2','m3','m4','m5') THEN betcheck ELSE 'm6' END
				WHEN 29 THEN CASE WHEN RAND() + 1 > 0 AND CONVERT(INT, hdp2) < 6 THEN 'm' + CONVERT(VARCHAR(10), CONVERT(INT, hdp2)) ELSE 'm6' END END, livehomescore, [status]
	ORDER BY  CASE bettype
				WHEN  9 THEN CASE WHEN RAND() + 1 > 0 AND betcheck in ('m2','m3','m4','m5') THEN betcheck ELSE 'm6' END
				WHEN 29 THEN CASE WHEN RAND() + 1 > 0 AND CONVERT(INT, hdp2) < 6 THEN 'm' + CONVERT(VARCHAR(10), CONVERT(INT, hdp2)) ELSE 'm6' END END, livehomescore, [status]
END
ELSE
BEGIN
	CREATE TABLE #DepAgent (custid int primary key)
	
	INSERT INTO #DepAgent (custid)
	SELECT c.custid
	FROM custinfo c WITH(NOLOCK)
		LEFT JOIN (select custid from f_DepSuper_1('All')) dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid)
	SELECT 52466 WHERE @site = 1--8RM
	UNION
	SELECT 5707545 WHERE @site =2 --BARM
			
	SELECT 
			CASE bettype
				WHEN  9 THEN CASE WHEN RAND() + 1 > 0 AND betcheck in ('m2','m3','m4','m5') THEN betcheck ELSE 'm6' END
				WHEN 29 THEN CASE WHEN RAND() + 1 > 0 AND CONVERT(INT, hdp2) < 6 THEN 'm' + CONVERT(VARCHAR(10), CONVERT(INT, hdp2)) ELSE 'm6' END
				END AS Combinations, 
			livehomescore as LiveType,
			[status], 
			sum((winlost-actual_stake)*actualrate) WinLost,
			SUM(stake*actualrate) turnoverp,
			count(1) BetCount,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
			sum((1-tpositiontaking)*(ABS(stake)*actualrate)) Turnover	
	FROM	bettrans b WITH (NOLOCK)
		INNER JOIN #DepAgent ag ON b.recommend = ag.custid
	WHERE
			ruben=1 AND
			bettype IN (9, 29) AND matchid IN (9, 29) AND -- prevent page split
			N'1' = CASE WHEN bettype = 29 THEN betteam ELSE N'1' END AND
			winlostdate between @FromDate AND @ToDate and 
			statusID NOT IN (101,102,103) AND
			currency <> 20
	GROUP BY  CASE bettype
				WHEN  9 THEN CASE WHEN RAND() + 1 > 0 AND betcheck in ('m2','m3','m4','m5') THEN betcheck ELSE 'm6' END
				WHEN 29 THEN CASE WHEN RAND() + 1 > 0 AND CONVERT(INT, hdp2) < 6 THEN 'm' + CONVERT(VARCHAR(10), CONVERT(INT, hdp2)) ELSE 'm6' END END, livehomescore, [status]
	ORDER BY  CASE bettype
				WHEN  9 THEN CASE WHEN RAND() + 1 > 0 AND betcheck in ('m2','m3','m4','m5') THEN betcheck ELSE 'm6' END
				WHEN 29 THEN CASE WHEN RAND() + 1 > 0 AND CONVERT(INT, hdp2) < 6 THEN 'm' + CONVERT(VARCHAR(10), CONVERT(INT, hdp2)) ELSE 'm6' END END, livehomescore, [status]
	
	DROP TABLE #DepAgent
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyParlayWinloss] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyParlayWinloss] TO [vnteam] 