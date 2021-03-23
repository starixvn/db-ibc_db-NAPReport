/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_MixParlay_Advance]
	@FromDate	datetime,
	@ToDate		datetime,
	@site		tinyint = 0
AS
/*	Creator: Sophia
	Date: 20111222
	Task: View Detail of Mix Parlay for 2a, 2h reports.
		  Accounting/ report/ 2a,2h/ Link Mix parlay
	DB: DBACC/bodb02

	Revisions: 
		- 20111222@Sophia:
			+ LiveType (Livehomescore):
				0: Non Live : All bets are Dead Ball 
				1: Live: All bets are Live Ball 
				2: Mix Live and Non Live: contains Live and Dead Ball 

			+ SportType (Liveawayscore):
				Sporttype: Sport Name (1: Soccer, 2: Basketball, 3 Football, ...)
				-1: Mixed Sports: soccer and at least 1 other sport
				-2: Mixed Other Sports: other sports, not soccer
				
		- 20121203@Elodie: Get data between @FromDate AND @ToDate
		- 20121217@Lukas: exclude UUS currency
		- 20130805@Johnson: filter by sites
		- 20160826@Percy: Enhance System/Mix Parlay [RedmineID: #63022]
		- 20180629@Franklin: Apply new concept for Virtual & Extra PT [RedmineID: #97163]
		- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
		- 20212203@Jaden: Support SABA789 (#151326)
	Parameter's Explanation:
		-@site:
			0: all sites
			1: credit sites
			2: deposit sites
*/
SET NOCOUNT ON

CREATE TABLE #MixParlay (
			Refno BIGINT,
			LiveType SMALLINT,
			SportType SMALLINT,
			[status] NVARCHAR(20),
			MemberWinLoss FLOAT,
			MemberTurnOver FLOAT,
			SMAWinLoss FLOAT,
			ExtraPT FLOAT,
			Commission FLOAT,
			RealIncome FLOAT,
			RealTurnover FLOAT
			)
IF @site = 0
BEGIN
	INSERT INTO #MixParlay (
						Refno,
						LiveType,
						SportType,
						[status],
						MemberWinLoss,
						MemberTurnOver,
						SMAWinLoss,
						ExtraPT,
						Commission,
						RealIncome,
						RealTurnover)
	SELECT 
			Refno, livehomescore as LiveType, liveawayscore AS SportType, [status], 
			(winlost - actual_stake) * actualrate MemberWinLoss, -- Member WinLoss
			stake * actualrate MemberTurnOver, -- Member Turnover
			(awinlost + mwinlost + swinlost) * actualrate SMAWinLoss, -- SMA WinLoss
			-(CASE WHEN tpositiontaking = 1 THEN 0
                     ELSE( winlost - actual_stake ) + scomm / ( 1 - tpositiontaking )
                END * ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT,
			scomm * actualrate Commission,	
			(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE WHEN tpositiontaking = 1 THEN 0
                                                                                           ELSE winlost - actual_stake + scomm / ( 1 - tpositiontaking )
                                                                                      END ) * ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate AS RealIncome, -- Real House Income
			(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE( 1 - tpositiontaking - ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(stake) * CASE
                                                                                            WHEN virtualrate > actualrate
                                                                                            THEN virtualrate
                                                                                            ELSE actualrate
                                                                                        END
                    END) AS RealTurnover -- Real House Turnover
	FROM	bettrans WITH (NOLOCK)
	WHERE
			ruben=1 AND
			bettype IN (9, 29) AND matchid IN (9, 29) AND -- prevent page split
			N'1' = CASE WHEN bettype = 29 THEN betteam ELSE N'1' END AND
			winlostdate between @FromDate AND @ToDate and
			statusID NOT IN (101,102,103) AND
			currency <> 20
END
ELSE BEGIN
	CREATE TABLE #DepAgent (custid int primary key)
	
	INSERT INTO #DepAgent (custid)
	SELECT c.custid
	FROM custinfo c WITH(NOLOCK)
		LEFT JOIN (select custid from Dep_CustSuper with (NOLOCK) where [site] <> 'Saba789') dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid)
	SELECT 52466 WHERE @site = 1--8RM
	UNION
	SELECT 5707545 WHERE @site =2 --BARM
		
	INSERT INTO #MixParlay (
						Refno,
						LiveType,
						SportType,
						[status],
						MemberWinLoss,
						MemberTurnOver,
						SMAWinLoss,
						ExtraPT,
						Commission,
						RealIncome,
						RealTurnover)
	SELECT 
			Refno, livehomescore AS LiveType, liveawayscore AS SportType, [status], 
			(winlost - actual_stake) * actualrate AS MemberWinLoss, -- Member WinLoss
			stake * actualrate AS MemberTurnOver, -- Member Turnover
			(awinlost + mwinlost + swinlost) * actualrate AS SMAWinLoss, -- SMA WinLoss
			-(CASE WHEN tpositiontaking = 1 THEN 0
				   ELSE( winlost - actual_stake ) + scomm / ( 1 - tpositiontaking )
                END  * ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT,
			scomm * actualrate AS Commission,	
			( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE WHEN tpositiontaking = 1 THEN 0
                                                                                           ELSE winlost - actual_stake + scomm / ( 1 - tpositiontaking )
                                                                                      END ) * ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate AS RealIncome, -- Real House Income
			(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE( 1 - tpositiontaking - ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(stake) * CASE
                                                                                            WHEN virtualrate > actualrate
                                                                                            THEN virtualrate
                                                                                            ELSE actualrate
                                                                                        END
                    END) AS RealTurnover -- Real House Turnover
	FROM	bettrans WITH (NOLOCK)
		INNER JOIN #DepAgent ag ON bettrans.recommend = ag.custid
	WHERE
			ruben=1 AND
			bettype IN (9, 29) AND matchid IN (9, 29) AND -- prevent page split
			N'1' = CASE WHEN bettype = 29 THEN betteam ELSE N'1' END AND
			winlostdate between @FromDate AND @ToDate and
			statusID NOT IN (101,102,103) AND
			currency <> 20
	
	DROP TABLE #DepAgent
END

CREATE NONCLUSTERED INDEX IX_Refno_SportType ON #MixParlay (Refno, SportType)

UPDATE #MixParlay
SET SportType = -1
WHERE SportType = 3

CREATE TABLE #OtherSport (Refno BIGINT, SportType SMALLINT)
INSERT INTO #OtherSport (Refno)
SELECT Refno FROM #MixParlay WHERE SportType = 2

CREATE NONCLUSTERED INDEX IX_Refno ON #OtherSport (Refno)

UPDATE os
SET os.SportType = dbo.f_GetSportParlayByRefno(os.Refno)
FROM #OtherSport os

DECLARE @max_sporttype INT
SELECT  @max_sporttype = MAX(Sporttype) FROM dbo.Sports WITH(NOLOCK)

; WITH Result AS (
	SELECT
		9 AS bettype, LiveType, ISNULL(os.SportType, mp.SportType) SportType, [status],
		SUM(mp.MemberWinLoss) MemberWinLoss, 
		SUM(mp.MemberTurnOver) MemberTurnOver,
		SUM(mp.SMAWinloss) SMAWinLoss,
		SUM(mp.ExtraPT) ExtraPT,
		SUM(mp.Commission) Commission,
		SUM(mp.RealIncome) RealIncome,
		SUM(mp.RealTurnover) RealTurnover
	FROM #MixParlay mp
		LEFT JOIN #OtherSport os ON mp.Refno = os.Refno
	GROUP BY LiveType, ISNULL(os.SportType, mp.SportType), [status]
),
Sport AS (
	SELECT SportType, SportName, 1 AS RN FROM dbo.Sports WITH(NOLOCK) WHERE SportType = 1
	UNION SELECT SportType, SportName, ROW_NUMBER() OVER(ORDER BY SportName) + 1 AS RN FROM dbo.Sports WITH(NOLOCK) WHERE SportType <> 1
	UNION SELECT -1, 'Mixed Sports', @max_sporttype + 1
	UNION SELECT -2, 'Mixed Other Sports', @max_sporttype + 2
)
SELECT
	r.*
FROM Result r
	INNER JOIN Sport s ON r.SportType = s.SportType
ORDER BY s.RN, r.LiveType, r.[status]

DROP TABLE #MixParlay
DROP TABLE #OtherSport
GO
