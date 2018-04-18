USE [bodb02]
GO
IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Game_Product_14]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_Product_14];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Game_Product_14] @StartDate  SMALLDATETIME,
                                                             @EndDate    SMALLDATETIME,
                                                             @CasinoType INT
AS

/*
Creator: Franklin
Date: 2016-02-22
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
	- 20160222@Franklin: Initialize Company Win Loss Report
	- 20160720@Sophia: . Revise SP
					   . Not use @EndDate because we get only one day on (bettrans/bettrans14 range)
	- 20160112@Percy: Change Extra PT formula [RedmineID: #70208].
	- 20171013@Franklin: ExtraPT Setting - DB Restructure (#84802)
	- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)

Example:
EXEC [Acc_Rpt_CompanyWinLoss_Game_Product_14] @EndDate='2020-01-01',@StartDate='2017-01-05', @CasinoType = 1
*/

     SET NOCOUNT ON;

	 DECLARE @EffectedDate DATETIME; -- 20160112@Percy: Applying date of changing extra PT formula [RedmineID: #70208]
	 SELECT  @EffectedDate = '2017-01-19';

     BEGIN --#SportBetType     
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (ProductID   INT,
          ProductName NVARCHAR(50),
          BetType     INT,
          RefTable    INT
         );
         INSERT INTO #SportBetType
                SELECT s.ProductID,
                       CASE
                           WHEN s.ProductID = 4
                           THEN 'SLI'
                           WHEN s.ProductID = 6
                           THEN 'MBC - RNG Casino'
                           ELSE p.ProductName
                       END,
                       s.BetType,
                       s.RefTable
                FROM dbo.f_SportBetTypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
                     INNER JOIN Products p WITH (NOLOCK) ON p.ProductID = s.ProductID
                WHERE s.CasinoType = @CasinoType;
     END;
     BEGIN -- #DepositSuper

         CREATE TABLE #DepositSuper
         (CustId INT PRIMARY KEY
         );
         INSERT INTO #DepositSuper
                SELECT CustId
                FROM f_DepSuper_1('All');
     END;
     BEGIN --#ExtraPT
         CREATE TABLE #ExtraPT
         (ProductID INT,
          SuperID   INT,
          ExtraPT   DECIMAL(9, 8)
         );
         INSERT INTO #ExtraPT
                SELECT ProductID,
                       SuperId,
                       SUM(ExtraPT) AS ExtraPT
                FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
                WHERE @StartDate BETWEEN FromDate AND Todate
                GROUP BY ProductID,
                         SuperId;
     END;
     BEGIN -- #Data

         CREATE TABLE #Data
         (GroupId       INT,
          GroupName     NVARCHAR(50),
          RowName       NVARCHAR(50),
          MemberWinLoss MONEY,
          SMAWinLoss    MONEY,
          Commission    MONEY,
          RealIncome    MONEY,
          RealTurnover  MONEY,
          ExtraPT       MONEY,
		  NewExtraPT    MONEY
         );
     END;
     IF EXISTS -- BetTrans
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable NOT IN(1, 2)
     )
         BEGIN
             INSERT INTO #Data
                    SELECT sb.ProductId AS GroupId,
                           sb.ProductName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName,
                           SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover,
                           SUM((winlost - actual_stake) * actualrate * ISNULL(e.ExtraPT, 0)) AS ExtraPT,
						   SUM((CASE
                                   WHEN tpositiontaking = 1
                                   THEN winlost - actual_stake
                                   ELSE winlost - actual_stake + scomm / (1 - tpositiontaking)
                               END * ISNULL(e.ExtraPT, 0)) * actualrate) AS NewExtraPT
                    FROM bettrans14 AS b WITH (NOLOCK)
                         INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                         LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                         LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                 AND sb.ProductId = e.ProductId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable NOT IN(1, 2)
                         AND b.ruben = 1
                         AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.ProductId,
                             sb.ProductName,
                             CASE
                                 WHEN dep.CustId IS NULL
                                 THEN 'Credit'
                                 ELSE 'Deposit'
                             END;
         END;
     IF EXISTS -- bettransRNG
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 1
     )
         BEGIN
             INSERT INTO #Data
                    SELECT sb.ProductId AS GroupId,
                           sb.ProductName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((CASE WHEN b.gameId IN (2198, 2398, 2998) THEN b.ContributionRate*b.BetStake + awinlost + mwinlost + swinlost + scomm
									 WHEN b.gameId IN (2199, 2399, 2999) THEN 0
									 ELSE winlost - actual_stake  + awinlost + mwinlost + swinlost + scomm 
								END) * actualrate) AS RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover,
                           SUM((winlost - actual_stake) * actualrate * ISNULL(e.ExtraPT, 0)) AS ExtraPT,
						   SUM((CASE WHEN b.gameId IN (2199, 2399, 2999) THEN 0
								     WHEN tpositiontaking = 1 AND b.gameId IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake 
									 WHEN tpositiontaking = 1 AND b.gameId NOT IN (2198, 2398, 2998) THEN winlost - actual_stake 
									 WHEN tpositiontaking <> 1 AND b.gameId IN (2198, 2398, 2998) THEN b.ContributionRate * b.BetStake  + scomm / (1 - tpositiontaking)
									 ELSE winlost - actual_stake + scomm / (1 - tpositiontaking) 
                                END * ISNULL(e.ExtraPT, 0)) * actualrate) AS NewExtraPT
                    FROM bettransRnG14 b WITH (NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                 AND sb.ProductId = e.ProductId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 1
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.ProductId,
                             sb.ProductName,
                             CASE
                                 WHEN dep.CustId IS NULL
                                 THEN 'Credit'
                                 ELSE 'Deposit'
                             END;
         END;
     IF EXISTS -- bettransLC
     (
         SELECT 1
         FROM #SportBetType
         WHERE RefTable = 2
     )
         BEGIN -- 

             INSERT INTO #Data
                    SELECT sb.ProductId AS GroupId,
                           sb.ProductName AS GroupName,
                           CASE
                               WHEN dep.CustId IS NULL
                               THEN 'Credit'
                               ELSE 'Deposit'
                           END AS RowName,
                           SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                           SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
                           SUM(scomm * actualrate) Commission,
                           SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                           SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover,
                           SUM((winlost - actual_stake) * actualrate * ISNULL(e.ExtraPT, 0)) AS ExtraPT,
						   SUM((CASE
                                   WHEN tpositiontaking = 1
                                   THEN winlost - actual_stake
                                   ELSE winlost - actual_stake + scomm / (1 - tpositiontaking)
                               END * ISNULL(e.ExtraPT, 0)) * actualrate) AS NewExtraPT
                    FROM bettransLC14 b WITH (NOLOCK)
                         INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
                         LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
                         LEFT JOIN #ExtraPT e ON b.srecommend = e.superID
                                                 AND sb.ProductId = e.ProductId
                    WHERE b.winlostdate = @StartDate
                          AND sb.RefTable = 2
                          AND b.statusID IN(111, 112, 113)
                    GROUP BY sb.ProductId,
                             sb.ProductName,
                             CASE
                                 WHEN dep.CustId IS NULL
                                 THEN 'Credit'
                                 ELSE 'Deposit'
                             END;
         END;
     BEGIN -- Query

         SELECT d.GroupId AS GroupId,
                d.GroupName AS GroupName,
                d.RowName AS RowName,
                d.MemberWinLoss AS MemberWinLoss,
                d.SMAWinLoss AS SMAWinLoss,
                d.Commission AS Commission,
                d.RealIncome AS RealIncome,
                d.RealTurnover AS RealTurnover,
                CASE WHEN @StartDate < @EffectedDate THEN -d.ExtraPT ELSE -d.NewExtraPT END AS ExtraPT,
                CASE WHEN @StartDate < @EffectedDate THEN d.RealIncome - d.ExtraPT ELSE d.RealIncome - d.NewExtraPT END AS AfterExtraPT
         FROM #Data AS d
         ORDER BY GroupName,
                  RowName;
     END;
     DROP TABLE #SportBetType;
     DROP TABLE #DepositSuper;
     DROP TABLE #Data;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_Product_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Game_Product_14] TO [vnteam];
GO