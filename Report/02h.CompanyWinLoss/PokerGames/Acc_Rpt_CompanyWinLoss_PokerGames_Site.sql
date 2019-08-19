/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_PokerGames_Site
      @StartDate SMALLDATETIME,
      @EndDate   SMALLDATETIME,
      @BetType   INT,
      @Site      VARCHAR(50),
      @IsLive    INT = 2
AS

/*
Creator: 20180824@Cherry
Task:  Poker Games Integration - Implement Company Winloss By Products report [#97830]
DB: DBACC/bodb02

Revisions:
- 20180831@Kean: Integrate Insurance Of Poker Games (#97830)
- 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
- 20190121@Franklin: Integrate Poker Games (#107706)
- 20190925@Jacob: Group By CN88 (#118824)
Parameter's Explanation:
	- @Site: credit, deposit

Example:
EXEC [Acc_Rpt_CompanyWinLoss_PokerGames_Site] @StartDate='2018-08-21', @EndDate='2018-08-21', @Site = 'Credit', @BetType = 1404

*/

     SET NOCOUNT ON;
    BEGIN

        -- #Agent


        CREATE TABLE #Agent( CustId INT PRIMARY KEY,
                             Site   VARCHAR(50));
        IF @Site = 'Deposit'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND EXISTS(
                                     SELECT 1
                                     FROM Dep_CustSuper AS dep WITH ( NOLOCK )
                                     WHERE c.srecommend = dep.CustId );
            END;
        ELSE
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND NOT EXISTS(
                                         SELECT 1
                                         FROM Dep_CustSuper dep WITH ( NOLOCK )
                                         WHERE c.srecommend = dep.CustId );
            END;
    END;
    BEGIN

/*----Get Sport Bettype Matrix------
         Check SP Version	 */

        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( ProductID INT,
                                    BetType   INT,
                                    RefTable  INT );
        INSERT INTO #SportBetType
               SELECT ProductID,
                      BetType,
                      RefTable
               FROM bodb02.dbo.f_SportBetTypeMatrix_Sel( 0, 0, @BetType, 2, '', '', @isTest );

        --- End Sport Bettype Matrix------

    END;
    BEGIN

        ---- Extra PT

        CREATE TABLE #ExtraPT_Sel( SuperID   INT,
                                   Sporttype INT,
                                   ExtraPT   DECIMAL(9, 8));
        INSERT INTO #ExtraPT_Sel
               ( SuperID,
                 Sporttype,
                 ExtraPT
               )
               SELECT SuperId,
                      a.Sporttype,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH ( NOLOCK )
                    INNER JOIN #SportBetType sbt ON a.ProductId = sbt.ProductID
               WHERE @StartDate BETWEEN FromDate AND Todate
               GROUP BY SuperId,
                        a.Sporttype;

        -- Extra Comm

        CREATE TABLE #ExtraComm_Sel( SuperID   INT,
                                     Sporttype INT,
                                     ExtraComm DECIMAL(9, 8));
        INSERT INTO #ExtraComm_Sel
               ( SuperID,
                 Sporttype,
                 ExtraComm
               )
               SELECT SuperId,
                      a.Sporttype,
                      SUM(ExtraCommRate) AS ExtraComm
               FROM bodb02.dbo.Acc_GroupExtraCommRateSetting AS a WITH ( NOLOCK )
                    INNER JOIN #SportBetType sbt ON a.ProductId = sbt.ProductID
               WHERE @StartDate BETWEEN FromDate AND Todate
               GROUP BY SuperId,
                        a.Sporttype;
    END;
    BEGIN
        CREATE TABLE #Data( RowName       NVARCHAR(50),
                            MemberWinLoss MONEY,
                            SMAWinLoss    MONEY,
                            ExtraPT       MONEY,
                            Commission    MONEY,
                            RealIncome    MONEY,
                            RealTurnover  MONEY );
    END;
        IF EXISTS

        -- bettrans

        ( SELECT 1
          FROM #SportBetType
          WHERE RefTable NOT IN( 1, 2 )
            AND BetType = @BetType )
            BEGIN
                INSERT INTO #Data
                       SELECT Site,
                              SUM(( winlost - actual_stake ) * actualrate),
                              SUM(( awinlost + mwinlost + swinlost ) * actualrate),
                              SUM((( -b.oddsspread ) * ISNULL(c.ExtraComm, 0) + ( ISNULL(b.transid2, 0) * 1.0 / 10000 ) * ISNULL(e.ExtraPT, 0)) * actualrate),
                              SUM(scomm * actualrate),
                              SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( -b.oddsspread ) * ISNULL(c.ExtraComm, 0) - ( ISNULL(b.transid2, 0) * 1.0 / 10000 ) * ISNULL(e.ExtraPT, 0)) * actualrate),
                              0
                       FROM bettrans AS b WITH ( NOLOCK )
                            INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
                            LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
                            LEFT JOIN #ExtraComm_Sel AS c ON c.SuperID = b.srecommend
                       WHERE b.winlostdate = @StartDate
                         AND ( @IsLive = 2
                            OR b.liveindicator = @IsLive
                             )
                         AND b.BetType = @BetType
                         AND b.ruben = 1
                         AND b.statusID IN( 111, 112, 113 )
                       GROUP BY Site;
            END;
                IF EXISTS

                -- bettransRNG

                ( SELECT 1
                  FROM #SportBetType
                  WHERE RefTable = 1
                    AND BetType = @BetType )
                    BEGIN
                        INSERT INTO #Data
                               SELECT dep.Site,
                                      SUM(( winlost - actual_stake ) * actualrate),
                                      SUM(( awinlost + mwinlost + swinlost ) * actualrate),
                                      SUM(CASE
                                              WHEN tpositiontaking = 1
                                              THEN 0
                                              ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                          END * ISNULL(e.ExtraPT, 0) * actualrate),
                                      SUM(scomm * actualrate),
                                      SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                                                WHEN tpositiontaking = 1
                                                                                                                THEN 0
                                                                                                                ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                                            END * ISNULL(e.ExtraPT, 0)) * actualrate),
                                      SUM(CASE
                                              WHEN tpositiontaking = 1
                                              THEN 0
                                              ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                                  WHEN virtualrate > actualrate
                                                                                                                  THEN virtualrate
                                                                                                                  ELSE actualrate
                                                                                                              END
                                          END) AS RealTurnover
                               FROM bettransRNG AS b WITH ( NOLOCK )
                                    INNER JOIN #Agent AS dep ON b.recommend = dep.custid
                                    INNER JOIN #SportBetType AS sb ON sb.BetType = b.gameId
                                    LEFT JOIN #ExtraPT_Sel AS e ON b.srecommend = e.superID
                                    LEFT JOIN #ExtraComm_Sel AS c ON c.SuperID = b.srecommend
                               WHERE b.winlostdate = @StartDate
                                 AND b.gameId = @BetType
                                 AND b.statusID IN( 111, 112, 113 )
                               GROUP BY dep.Site
                               OPTION( RECOMPILE );
                    END;
    BEGIN

        -- Query

        SELECT d.RowName,
               d.MemberWinLoss,
               d.SMAWinLoss,
               -d.ExtraPT AS ExtraPT,
               d.Commission,
               d.RealIncome,
               d.RealTurnover
        FROM #Data AS d
        ORDER BY RowName;
    END;
        DROP TABLE #Agent;
        DROP TABLE #ExtraPT_Sel;
        DROP TABLE #ExtraComm_Sel;
        DROP TABLE #SportBetType;
        DROP TABLE #Data;
GO
