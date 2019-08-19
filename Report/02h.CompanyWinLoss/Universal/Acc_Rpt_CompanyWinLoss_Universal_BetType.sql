
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Universal_BetType] @StartDate SMALLDATETIME,
                                                                 @EndDate   SMALLDATETIME,
                                                                 @ProductId INT,
                                                                 @SportType INT           = 0,
                                                                 @IsLive    INT           = 2
AS

/*
Creator: 20160222@Franklin
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160222@Franklin: Initialize Company Win Loss Report - Universal
- 20160923@Percy: Add params @Sporttype to support by Sporttype [RedmineID: #63460]
- 20160923@Percy: Using local variable to prevent bad parameter sniffing [RedmineID: #64573]
- 20170825@Franklin: Integrate Lucky 3 (#78214)
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20190925@Jacob: Group By CN88 (#118824)	
Example:
EXEC [Acc_Rpt_CompanyWinLoss_Universal_BetType] @StartDate='2016-09-13', @EndDate='2020-01-01', @ProductId = 15, @SportType = 0

*/

     SET NOCOUNT ON;
     DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME, @ProID INT, @Sport INT;
     SELECT @FDate = @StartDate,
            @TDate = @EndDate,
            @ProID = @ProductId,
            @Sport = @SportType;
         BEGIN --#SportBetType
             DECLARE @isTest BIT= 0;
             SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
             CREATE TABLE #SportBetType
                          (BetType     INT,
                           BetTypeName NVARCHAR(50)
                          );
             INSERT INTO #SportBetType
                    SELECT b.typeid,
                           b.typenamee
                    FROM dbo.f_SportBetTypeMatrix_Sel(@ProID, @Sport, 0, 2, '', '', @isTest) s
                         INNER JOIN BetType b WITH (NOLOCK) ON s.BetType = b.typeid;
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
                          (SuperID   INT,
                           Sporttype INT,
                           ExtraPT   DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraPT_Sel
                    (SuperID,
                     Sporttype,
                     ExtraPT
                    )
                    SELECT SuperId,
                           Sporttype,
                           SUM(ExtraPT) AS ExtraPT
                    FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
                    WHERE @StartDate BETWEEN FromDate AND Todate
                          AND a.ProductId = @ProID
                    GROUP BY SuperId,
                             Sporttype;
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
                            ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                               WHEN virtualrate > actualrate
                                                                                               THEN virtualrate
                                                                                               ELSE actualrate
                                                                                           END
                        END) AS RealTurnover
             FROM bettrans AS b WITH (NOLOCK)
                  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
                  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @FDate
                   AND (@IsLive = 2
                        OR b.liveindicator = @IsLive)
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
     DROP TABLE #ExtraPT_Sel;
GO
