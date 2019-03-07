
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/


ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_BetBuilder_BetType] @StartDate SMALLDATETIME,
                                                                  @EndDate   SMALLDATETIME
AS

/*
Creator: Kean
Date: 2018-08-13
Task:  Improve performance Sp to drilldown MetricGaming [#99524]
DB: DBACC/bodb02

Revisions:
- 20190308@Jacob: Integrate BetBuilder (#109822)
Parameters:

Example:
EXEC [Acc_Rpt_CompanyWinLoss_BetBuilder_BetType] @EndDate='2019-03-03',@StartDate='2019-03-03'

*/

     SET NOCOUNT ON;
         BEGIN --#SportBetType     
             DECLARE @isTest BIT= 0;
             SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
             CREATE TABLE #SportBetType
                          (BetType     INT,
                           BetTypeName NVARCHAR(50)
                          );
             INSERT INTO #SportBetType
                    SELECT BetType,
                           b.typenamee
                    FROM dbo.f_SportBetTypeMatrix_Sel(1, 0, 0, 2, 'Bet Builder', '', @isTest) s
                         INNER JOIN dbo.BetType b WITH (NOLOCK) ON s.BetType = b.typeid;
         END;
         BEGIN ---- Extra PT 
             CREATE TABLE #ExtraPT_Sel
                          (SuperID INT,
                           ExtraPT DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraPT_Sel
                    (SuperID,
                     ExtraPT
                    )
                    SELECT SuperId,
                           SUM(ExtraPT) AS ExtraPT
                    FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
                    WHERE @StartDate BETWEEN FromDate AND Todate
                          AND a.ProductId = 1
                          AND a.SubProduct = 'Bet Builder'
                          AND a.Sporttype = 0
                    GROUP BY SuperId;
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
         BEGIN -- Query

             SELECT sb.BetType AS GroupId,
                    sb.BetTypeName AS GroupName,
                    CASE
                        WHEN dep.CustId IS NULL
                        THEN 'Credit'
                        ELSE 'Deposit'
                    END AS RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                    -SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                    SUM(scomm * actualrate) Commission,
                    SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                                WHEN tpositiontaking = 1
                                                                                                THEN 0
                                                                                                ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                            END) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                    SUM(CASE
                            WHEN tpositiontaking = 1
                            THEN 0
                            ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                    WHEN virtualrate > actualrate
                                                                                                    THEN virtualrate
                                                                                                    ELSE actualrate
                                                                                                END
                        END) AS RealTurnover
             FROM bettrans AS b WITH (NOLOCK)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @StartDate
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY sb.BetType,
                      sb.BetTypeName,
                      CASE
                          WHEN dep.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END
             ORDER BY GroupName,
                      RowName;
         END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #ExtraPT_Sel;
GO