/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_CashOut_BetType] 
	@StartDate SMALLDATETIME, 
    @EndDate   SMALLDATETIME,
    @IsLive    INT           = 2
AS

/*
Creator: 20170418@Jacob
DB: DBACC/bodb02
Revisions:
	20170418@Jacob: Integrate Cash Out - Redmine:#73419
	2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
	20190925@Jacob: Group By CN88 (#118824)
	20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
	20200320@Cherry: Support Deadball Cash Out (#130302)

Parameter's Explanation:
	- @Site: credit, deposit
Example:
Example:
EXEC [Acc_Rpt_CompanyWinLoss_CashOut_BetType] @StartDate='2016-01-01', @EndDate='2020-01-01', @IsLive=2
*/

    SET NOCOUNT ON;

    CREATE TABLE #DepositSuper
                 (CustId INT
                  PRIMARY KEY
                 );
    INSERT INTO #DepositSuper
           SELECT CustId
           FROM f_DepSuper_1('All');
           
    CREATE TABLE #tmp_Data
                     (LiveStatus      INT, 
                      BetTypeName     VARCHAR(50), 
                      RowName         VARCHAR(50), 
                      MemberWinLoss   MONEY, 
                      SMAWinLoss      MONEY, 
                      ExtraPT         MONEY, 
                      Commission      MONEY, 
                      RealIncome      MONEY, 
                      RealTurnover    MONEY 
                     )
    CREATE TABLE #Data
                     (GroupId         INT, 
                      GroupName       NVARCHAR(50), 
                      RowName         NVARCHAR(50), 
                      MemberWinLoss   MONEY, 
                      SMAWinLoss      MONEY, 
                      ExtraPT         MONEY, 
                      Commission      MONEY, 
                      RealIncome      MONEY, 
                      RealTurnover    MONEY 
                     )
                     
    INSERT INTO #tmp_Data
    SELECT liveindicator, 
          'Cash Out' BetTypeName,
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
          SUM((CASE
                   WHEN b.tpositiontaking = 1
                   THEN 0
                   ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
               END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
          SUM(scomm * actualrate) Commission, 
          SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
                                                                                      WHEN tpositiontaking = 1
                                                                                      THEN 0
                                                                                      ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                  END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) RealIncome, 
          SUM(CASE
                  WHEN tpositiontaking = 1
                  THEN 0
                  ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
                                                                                          WHEN virtualrate > actualrate
                                                                                          THEN virtualrate
                                                                                          ELSE actualrate
                                                                                      END
              END) RealTurnover
    FROM bettrans AS b WITH(NOLOCK)
         LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
         LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
    WHERE b.winlostdate = @StartDate
         AND (@IsLive > 1
              OR b.liveindicator = @IsLive)
         AND b.ruben = 1
         AND b.statusID IN(111, 112, 113)
         AND b.bettype IN (913,914)
    GROUP BY liveindicator, 
            CASE
                WHEN dep.CustId IS NULL
                     AND cn88.CustId IS NOT NULL
                THEN 'CN88'
                WHEN dep.CustId IS NULL
                     AND cn88.CustId IS NULL
                THEN 'Credit'
                ELSE 'Deposit'
            END
            
    OPTION(RECOMPILE)
                        
    INSERT INTO #Data
    SELECT 2 GroupId, 
           b.BetTypeName GroupName, 
           b.RowName AS RowName, 
           SUM(MemberWinLoss) MemberWinLoss, 
           SUM(SMAWinLoss) SMAWinLoss, 
           SUM(ExtraPT) AS ExtraPT, 
           SUM(Commission) Commission, 
           SUM(RealIncome) RealIncome, 
           SUM(RealTurnover) RealTurnover 
    FROM #tmp_Data AS b
    GROUP BY b.BetTypeName, 
            b.RowName
                        
    IF @IsLive = 2
        INSERT INTO #Data
        SELECT LiveStatus AS GroupId,
              CASE LiveStatus
                  WHEN 1
                  THEN 'Cash Out Live'
                  ELSE 'Cash Out Non-Live'
              END AS GroupName, 
              b.RowName AS RowName, 
              SUM(MemberWinLoss) MemberWinLoss, 
              SUM(SMAWinLoss) AS SMAWinLoss, 
              SUM(ExtraPT) AS ExtraPT, 
              SUM(Commission) Commission, 
              SUM(RealIncome) AS RealIncome, 
              SUM(RealTurnover) AS RealTurnover 
        FROM #tmp_Data b
        GROUP BY b.LiveStatus,
                CASE b.LiveStatus
                    WHEN 1
                    THEN 'Cash Out Live'
                    ELSE 'Cash Out Non-Live'
                END, 
                b.RowName

    SELECT d.GroupId GroupId, 
               d.GroupName AS GroupName, 
               d.RowName AS RowName, 
               d.MemberWinLoss AS MemberWinLoss, 
               d.SMAWinLoss AS SMAWinLoss, 
               -d.ExtraPT AS ExtraPT, 
               d.Commission AS Commission, 
               d.RealIncome AS RealIncome, 
               d.RealTurnover AS RealTurnover
    FROM #Data AS d
    ORDER BY GroupName, 
                 RowName
    
	DROP TABLE #DepositSuper
	DROP TABLE #Data
    DROP TABLE #tmp_Data
GO