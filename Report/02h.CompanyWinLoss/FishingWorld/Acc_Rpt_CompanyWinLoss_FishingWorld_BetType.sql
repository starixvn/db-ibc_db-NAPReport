
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_FishingWorld_BetType] @StartDate SMALLDATETIME,
                                                                    @EndDate   SMALLDATETIME,
                                                                    @ProductId INT           = 24,
                                                                    @SportType INT           = 0,
                                                                    @IsLive    INT           = 2
AS

/*
Creator: Jacob
Date: 2016-12-01
Task:  Integrate Fishing World Product [#67757]
DB: DBACC/bodb02

Revisions:
- 20161201@Jacob: Integrate Fishing World Product [#67757]
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)

Parameters:
@ProductId: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_BetType]
@SportType: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_BetType]
@IsLive: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_BetType]

Example:
EXEC [Acc_Rpt_CompanyWinLoss_FishingWorld_BetType] @EndDate='2020-01-01',@StartDate='2016-11-28'
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
                    FROM dbo.f_SportBetTypeMatrix_Sel(24, 0, 0, 2, '', '', @isTest) s
                         INNER JOIN BetType b WITH (NOLOCK) ON b.typeid = s.BetType;
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
         BEGIN -- Extra PT
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
                          AND a.ProductId = 24
                    GROUP BY SuperId;
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
                    SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
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
                                                                                            END) * ISNULL(e.ExtraPT, 0)) * actualrate) RealIncome,
                    SUM(CASE
                            WHEN tpositiontaking = 1
                            THEN 0
                            ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                               WHEN virtualrate > actualrate
                                                                                               THEN virtualrate
                                                                                               ELSE actualrate
                                                                                           END
                        END) RealTurnover
             FROM bettransRNG b WITH (NOLOCK)
                  INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                  LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                  LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
                  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @StartDate
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
     DROP TABLE #ExtraPT_Sel;
GO
