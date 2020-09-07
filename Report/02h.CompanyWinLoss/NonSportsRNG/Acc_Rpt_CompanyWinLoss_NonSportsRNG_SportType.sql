/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

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

    Remarks:
        Target detail SP (level 2) in "Company winloss by Product" report for product:
            * Saba.Club

    Example:
        EXEC [Acc_Rpt_CompanyWinLoss_NonSportsRNG_SportType] @StartDate='2020-08-18', @EndDate='2020-01-01', 
            @ProductId=42
*/
    SET NOCOUNT ON

    DECLARE @isTest BIT = dbo.f_CheckSPVersion(@@PROCID)

    CREATE TABLE #SportBetTypeMatrix (BetType   INT, 
                                      SportType INT)
    INSERT INTO #SportBetTypeMatrix (BetType, SportType)
        SELECT DISTINCT BetType, SportType --use distinct to remove "IsLive"
        FROM SportBetTypeMatrix
        WHERE ProductID = @ProductId 
          AND IsTest    = @isTest
    
    SELECT  b.productID             AS GroupId, 
            MAX(sport.SportName)    AS GroupName,
            CASE WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL THEN 'CN88'
                 WHEN dep.CustId IS NULL AND cn88.CustId IS NULL     THEN 'Credit'
                 ELSE 'Deposit' END AS RowName, 
            SUM((winlost - actual_stake) * actualrate) MemberWinLoss, 
            SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss, 
            - SUM(CASE WHEN b.tpositiontaking = 1 THEN 0
                       ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking) END
                  * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) 
                  * actualrate) AS ExtraPT, 
            SUM(scomm * actualrate) Commission, 
            SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm 
                - CASE WHEN tpositiontaking = 1 THEN 0
                       ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking) END
                * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) 
                * actualrate) AS RealIncome, 
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
    LEFT JOIN Dep_CustSuper AS dep WITH (NOLOCK) ON b.srecommend = dep.custid
    LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
    WHERE b.winlostdate = @StartDate
        AND b.statusID IN(111, 112, 113)
    GROUP BY b.productID, 
             CASE WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL THEN 'CN88'
                  WHEN dep.CustId IS NULL AND cn88.CustId IS NULL     THEN 'Credit'
                  ELSE 'Deposit' END 
    ORDER BY GroupId, RowName
    OPTION(RECOMPILE)
GO