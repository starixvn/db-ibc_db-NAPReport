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
				
		-20121203@Elodie: Get data between @FromDate AND @ToDate
		- 20121217@Lukas: exclude UUS currency
		- 20130805@Johnson: filter by sites
		- 20160826@Percy: Enhance System/Mix Parlay [RedmineID: #63022]
	Parameter's Explanation:
		-@site:
			0: all sites
			1: credit sites
			2: deposit sites
*/
SET NOCOUNT ON

CREATE TABLE #MixParlay (Refno BIGINT, LiveType SMALLINT, SportType SMALLINT, [status] NVARCHAR(20), WinLost FLOAT, turnoverp FLOAT, Position FLOAT, Commission FLOAT, LineTotal FLOAT, Turnover FLOAT, ExtraPT FLOAT)
BEGIN ---- Extra PT 
    DECLARE @datestart DATE = @FromDate
    DECLARE @dateend DATE = @ToDate
    DECLARE @onDate DATE = @datestart
     
    CREATE TABLE #ExtraPT_Sel( OnDate DATETIME, SuperID INT,
							    ExtraPT DECIMAL(9, 8));
       
    WHILE (@onDate <= @dateend)
    BEGIN
	INSERT INTO #ExtraPT_Sel (OnDate, SuperID, ExtraPT)
			 SELECT @onDate, SuperId,
				    SUM(ExtraPT) AS ExtraPT
			 FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
			 WHERE @onDate BETWEEN FromDate AND Todate
				AND a.ProductId = 1
				AND a.Sporttype = 0
				AND a.SubProduct = ''
			 GROUP BY SuperId,Sporttype;

	SELECT @onDate = DATEADD(DD, 1, @onDate)
    END
    CREATE UNIQUE CLUSTERED INDEX PK_tblExtraPT ON #ExtraPT_Sel(OnDate,SuperID)
END;
IF @site = 0
BEGIN
	INSERT INTO #MixParlay
	SELECT 
			Refno, livehomescore as LiveType, liveawayscore AS SportType, [status], 
			(winlost-actual_stake)*actualrate WinLost, -- Member WinLoss
			stake*actualrate turnoverp, -- Member Turnover
			(awinlost+mwinlost+swinlost)*actualrate Position, -- SMA WinLoss
			scomm*actualrate Commission,	
			( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
																	   END ) - ( CASE
																			    WHEN tpositiontaking = 1
																			    THEN 0
																			    ELSE scomm * ISNULL(e.ExtraPT, 0) / 1 - bettrans.tpositiontaking
																			 END )) * actualrate LineTotal, -- Real House Income
			CASE
                   WHEN tpositiontaking = 1
                   THEN 0
                   ELSE( 1 - tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(stake) * CASE
                                                                                        WHEN virtualrate > actualrate
                                                                                        THEN virtualrate
                                                                                        ELSE actualrate
                                                                                    END
                END Turnover, -- Real House Turnover	
                CASE
                     WHEN tpositiontaking = 1
                     THEN 0
                     ELSE( winlost - actual_stake ) + scomm / ( 1 - tpositiontaking )
                END * ISNULL(e.ExtraPT, 0) * actualrate AS ExtraPT
	FROM	bettrans WITH (NOLOCK)
	LEFT JOIN #ExtraPT_Sel e ON e.SuperID = srecommend AND e.OnDate = winlostdate
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
		LEFT JOIN (select custid from f_DepSuper_1('All')) dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid)
	SELECT 52466 WHERE @site = 1--8RM
	UNION
	SELECT 5707545 WHERE @site =2 --BARM
		
	INSERT INTO #MixParlay
	SELECT 
			Refno, livehomescore as LiveType, liveawayscore AS SportType, [status], 
			(winlost-actual_stake)*actualrate WinLost, -- Member WinLoss
			stake*actualrate turnoverp, -- Member Turnover
			(awinlost+mwinlost+swinlost)*actualrate Position, -- SMA WinLoss
			scomm*actualrate Commission,	
			( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                         WHEN tpositiontaking = 1
                                                                                         THEN 0
                                                                                         ELSE( winlost - actual_stake ) * ISNULL(e.ExtraPT, 0)
																	   END ) - ( CASE
																			    WHEN tpositiontaking = 1
																			    THEN 0
																			    ELSE scomm * ISNULL(e.ExtraPT, 0) / 1 - bettrans.tpositiontaking
																			 END )) * actualrate LineTotal, -- Real  House Income
			CASE
                   WHEN tpositiontaking = 1
                   THEN 0
                   ELSE( 1 - tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(stake) * CASE
                                                                                        WHEN virtualrate > actualrate
                                                                                        THEN virtualrate
                                                                                        ELSE actualrate
                                                                                    END
                END Turnover, -- Real House Turnover
                CASE
				 WHEN tpositiontaking = 1
				 THEN 0
				 ELSE( winlost - actual_stake ) + scomm / ( 1 - tpositiontaking )
                END  * ISNULL(e.ExtraPT, 0) * actualrate AS ExtraPT
	FROM	bettrans WITH (NOLOCK)
		LEFT JOIN #ExtraPT_Sel e ON e.SuperID = srecommend AND e.OnDate = winlostdate
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
		SUM(WinLost) WinLost, SUM(turnoverp) turnoverp, SUM(Position) Position, SUM(Commission) Commission, SUM(LineTotal) LineTotal, SUM(Turnover) Turnover, SUM(ExtraPT) ExtraPT
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
DROP TABLE #ExtraPT_Sel

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MixParlay_Advance] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MixParlay_Advance] TO [vnteam]