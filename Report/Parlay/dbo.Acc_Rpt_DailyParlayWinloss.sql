/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

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
		- 20180629@Franklin: Apply new concept for Virtual & Extra PT [RedmineID: #97163]
		- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
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
			SUM((winlost-actual_stake)*actualrate) MemberWinLoss, -- Member WinLoss
			SUM(stake*actualrate) MemberTurnOver, -- Member Turnover
			COUNT(1) BetCount,
			SUM((awinlost+mwinlost+swinlost)*actualrate) SMAWinLoss, -- SMA WinLoss
			-SUM(( CASE
                         WHEN tpositiontaking = 1
                         THEN 0
                         ELSE( winlost - actual_stake ) + scomm / ( 1 - tpositiontaking )
                     END ) * ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT,
			SUM(scomm*actualrate) Commission,	
			SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE WHEN tpositiontaking = 1 THEN 0
                                                                                           ELSE winlost - actual_stake + scomm / ( 1 - tpositiontaking )
                                                                                      END ) * ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) RealIncome, -- Real House Income
			SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE( 1 - tpositiontaking - ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(stake) * CASE
                                                                                            WHEN virtualrate > actualrate
                                                                                            THEN virtualrate
                                                                                            ELSE actualrate
                                                                                        END
                    END) RealTurnover -- Real House Turnover
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
			SUM((winlost-actual_stake)*actualrate) MemberWinLoss, -- Member WinLoss
			SUM(stake*actualrate) MemberTurnOver, -- Member Turnover
			COUNT(1) BetCount,
			SUM((awinlost+mwinlost+swinlost)*actualrate) SMAWinLoss, -- SMA WinLoss
			-SUM(( CASE
                         WHEN tpositiontaking = 1
                         THEN 0
                         ELSE( winlost - actual_stake ) + scomm / ( 1 - tpositiontaking )
                     END ) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT,
			SUM(scomm*actualrate) Commission,	
			SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE WHEN tpositiontaking = 1 THEN 0
                                                                                           ELSE winlost - actual_stake + scomm / ( 1 - tpositiontaking )
                                                                                      END ) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) RealIncome, -- Real House Income
			SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE( 1 - tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(stake) * CASE
                                                                                            WHEN virtualrate > actualrate
                                                                                            THEN virtualrate
                                                                                            ELSE actualrate
                                                                                        END
                    END) RealTurnover -- Real House Turnover
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
