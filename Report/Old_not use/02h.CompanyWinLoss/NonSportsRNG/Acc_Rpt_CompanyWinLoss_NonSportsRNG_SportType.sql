USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_NonSportsRNG_SportType] @StartDate SMALLDATETIME, 
                                                                      @EndDate   SMALLDATETIME, 
                                                                      @ProductId INT
AS
/*
    Creator: Jaden
    Date: 2020-08-25
    Task: Incorporate saba.club freebet [#140107]
    DB: DBACC/bodb02

    Revisions:
        - 20200825@Jaden: Init SP
        - 20212203@Jaden: Support SABA789 (#151326)
        - 20220119@Ned.Le: Nap Report - House Win Loss by Product - Incorrect figure House Real Income of Vgaming (#167739)

    Remarks:
        Target detail SP (level 2) in "Company winloss by Product" report for product:
            * Saba.Club

    Example:
        EXEC [Acc_Rpt_CompanyWinLoss_NonSportsRNG_SportType] @StartDate='2020-08-18', @EndDate='2020-01-01', 
            @ProductId=42
*/
    SET NOCOUNT ON

    DECLARE @isTest BIT = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #SpecialBettypeGroup (BettypeGroupID SMALLINT, Bettype INT)
	INSERT INTO #SpecialBettypeGroup (BettypeGroupID, Bettype)
	SELECT BettypeGroupID, Bettype FROM DBWH.bodb_Account.dbo.BettypeGroup WHERE BettypeGroupID IN (6, 10)

    CREATE TABLE #SportBetTypeMatrix (BetType   INT, 
                                      SportType INT)
    INSERT INTO #SportBetTypeMatrix (BetType, SportType)
        SELECT DISTINCT BetType, SportType --use distinct to remove "IsLive"
        FROM SportBetTypeMatrix
        WHERE ProductID = @ProductId 
          AND (IsTest = 0 OR IsTest = @isTest)
    
    CREATE TABLE #DepositSuper (CustId INT PRIMARY KEY);
    INSERT INTO #DepositSuper
        SELECT custid FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK);
    
    SELECT  b.productID             AS GroupId, 
            MAX(sport.SportName)    AS GroupName,
            CASE WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL THEN 'CN88'
                 WHEN dep.CustId IS NULL AND cn88.CustId IS NULL     THEN 'Credit'
                 ELSE 'Deposit' END AS RowName, 
            SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
            SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
            -SUM((CASE WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
                            THEN(CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.ContributionStake3rd + b.scomm / (1 - b.tpositiontaking) END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                       WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
                       ELSE(CASE WHEN tpositiontaking = 1 THEN 0
                                 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking) END) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                  END) * actualrate) AS ExtraPT,
            SUM(scomm * actualrate) Commission,
            SUM((CASE WHEN bg.BettypeGroupID = 10 --Contribution Bettype Group
                           THEN b.ContributionStake3rd + awinlost + mwinlost + swinlost + scomm - (CASE WHEN tpositiontaking = 1 THEN 0 ELSE b.ContributionStake3rd + b.scomm / (1 - b.tpositiontaking) END) *
                           ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                      WHEN bg.BettypeGroupID = 6 THEN 0 -- Prize Bettype Group
                      ELSE winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE WHEN tpositiontaking = 1 THEN 0 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking) END) *
                           ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
                 END) * actualrate) AS RealIncome,
            SUM(CASE WHEN tpositiontaking = 1 THEN 0
                     ELSE (1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) 
                          * b.stake 
                          * CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END
                END) AS RealTurnover
    FROM bettransRNG b WITH(NOLOCK)
    INNER JOIN Sports AS sport WITH (NOLOCK) ON sport.SportType  = b.productID
    INNER JOIN #SportBetTypeMatrix AS sb 
        ON sb.BetType = b.gameID AND sb.SportType = b.productID
            --bettransRNG: ProductID is used as a place holder field to identify bet type saba.club free bets (150)
    LEFT JOIN #DepositSuper AS dep WITH (NOLOCK) ON b.srecommend = dep.custid
    LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
    LEFT JOIN #SpecialBettypeGroup bg ON b.gameID = bg.Bettype
    WHERE b.winlostdate = @StartDate
        AND b.statusID IN(111, 112, 113)
    GROUP BY b.productID, 
             CASE WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL THEN 'CN88'
                  WHEN dep.CustId IS NULL AND cn88.CustId IS NULL     THEN 'Credit'
                  ELSE 'Deposit' END 
    ORDER BY GroupId, RowName
    OPTION(RECOMPILE)

    DROP TABLE #DepositSuper
GO