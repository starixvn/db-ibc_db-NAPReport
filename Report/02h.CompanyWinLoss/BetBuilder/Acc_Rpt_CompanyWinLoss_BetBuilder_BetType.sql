/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_BetBuilder_BetType] @StartDate SMALLDATETIME, 
                                                                  @EndDate   SMALLDATETIME,
																  @SportType SMALLINT
AS

/*
Creator: Jacob
Date: 2019-03-13
Task:  Integrate BetBuilder (#109822)
DB: DBACC/bodb02

Revisions:
- 20190313@Jacob: Integrate BetBuilder (#109822)
- 20190925@Jacob: Group By CN88 (#118824)
- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
- 20200722@Roy: Incorporate New Basketball Sport for BetBuilder Product - NAP Report (#138082)
Parameters:

Example:
EXEC Acc_Rpt_CompanyWinLoss_BetBuilder_BetType @StartDate='2020-07-23 00:00:00', @EndDate='2020-07-23 00:00:00', @SportType = 2

*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType 
		DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (BetType     SMALLINT
                      ,BetTypeName NVARCHAR(50)
                     );
        INSERT INTO #SportBetType
				SELECT s.BetType, 
                      b.typenamee
				FROM dbo.f_SportBetTypeMatrix_Sel(1, 0, 0, 2, 'Bet Builder', '', @isTest) s
                    INNER JOIN dbo.BetType b WITH(NOLOCK) ON s.BetType = b.typeid
				GROUP BY s.BetType
						,b.typenamee;
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper
                     (CustId INT
                      PRIMARY KEY
                     );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1('All');
    END;
	BEGIN -- #tmpMatches
        CREATE TABLE #tmpMatches (
			MatchId INT PRIMARY KEY
			)
		INSERT INTO #tmpMatches
        SELECT m.MatchId
		FROM match m WITH (NOLOCK)
			INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid
			INNER JOIN SportBettypeMatrix sm WITH (NOLOCK) ON l.sporttype = sm.sporttype
		WHERE sm.SubProduct = 'Bet Builder'		
			AND sm.sporttype = @SportType
			AND m.EventDate = @StartDate
		GROUP BY m.MatchId
		OPTION (RECOMPILE)
    END;
    BEGIN -- Query

        SELECT sb.BetType AS GroupId, 
               sb.BetTypeName AS GroupName,
               CASE
                   WHEN dep.CustId IS NULL
                        AND cn88.CustId IS NOT NULL
                   THEN 'CN88'
                   WHEN dep.CustId IS NULL
                        AND cn88.CustId IS NULL
                   THEN 'Credit'
                   ELSE 'Deposit'
               END AS RowName, 
               SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
               SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
               -SUM((CASE
                        WHEN b.tpositiontaking = 1
                        THEN 0
                        ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                    END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
               SUM(scomm * actualrate) Commission, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                           WHEN tpositiontaking = 1
                                                                                           THEN 0
                                                                                           ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                       END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                  WHEN tpositiontaking = 1
                                                                                  THEN 0
                                                                                  ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                              END) * virtualrate + (scomm - (CASE
                                                                                                                 WHEN tpositiontaking = 1
                                                                                                                 THEN 0
                                                                                                                 ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                             END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
                                                                                                                                                             WHEN virtualrate < actualrate
                                                                                                                                                             THEN virtualrate / actualrate
                                                                                                                                                             ELSE 1
                                                                                                                                                         END) VirtualIncome, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
                                                                                  WHEN tpositiontaking = 1
                                                                                  THEN 0
                                                                                  ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                                                                              END + CASE
                                                                                        WHEN virtualrate < actualrate
                                                                                        THEN(b.scomm - (CASE
                                                                                                            WHEN tpositiontaking = 1
                                                                                                            THEN 0
                                                                                                            ELSE b.scomm / (1 - b.tpositiontaking)
                                                                                                        END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0))
                                                                                        ELSE 0
                                                                                    END) * (actualrate - virtualrate)) VarianceIncome, 
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                               WHEN virtualrate > actualrate
                                                                                               THEN virtualrate
                                                                                               ELSE actualrate
                                                                                           END
                   END) AS RealTurnover, 
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
                   END) AS VirtualTurnover
        FROM bettrans AS b WITH(NOLOCK)
			 INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			 INNER JOIN #tmpMatches AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
        WHERE b.winlostdate = @StartDate
              AND b.ruben = 1
              AND b.statusID IN(111, 112, 113)
        GROUP BY sb.BetType, 
                 sb.BetTypeName,
                 CASE
                     WHEN dep.CustId IS NULL
                          AND cn88.CustId IS NOT NULL
                     THEN 'CN88'
                     WHEN dep.CustId IS NULL
                          AND cn88.CustId IS NULL
                     THEN 'Credit'
                     ELSE 'Deposit'
                 END
        ORDER BY GroupName, 
                 RowName;
    END;

    DROP TABLE #SportBetType;
    DROP TABLE #DepositSuper;
	DROP TABLE #tmpMatches;
GO