IF EXISTS( SELECT *
           FROM sys.objects
           WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_Site]')
             AND type IN( N'P', N'PC' ))
DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_Site];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_Site]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @Site      NVARCHAR(50)
AS

/*
Creator: 20160215@Robert
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions: 	 
    - 20160222@Robert: Improve Company Win Loss Report - Bettrade Product
    - 20160818@Jacob: Integrate bettype-904 (BT-Winloss) - Redmine:#62630		
    - 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Parameter's Explanation:
	- @Site: credit, deposit	
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Bettrade_Site] @StartDate='2016-08-24', @EndDate='2020-01-01', @Site = 'Deposit'
*/

     SET NOCOUNT ON;
    BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( BetType INT );
        INSERT INTO #SportBetType
               SELECT BetType
               FROM dbo.f_SportBetTypeMatrix_Sel( 1, 0, 0, 2, 'BT-Comm', '', @isTest )
               UNION
               SELECT BetType
               FROM dbo.f_SportBetTypeMatrix_Sel( 1, 0, 0, 2, 'BT-Winloss', '', @isTest );
    END;
    BEGIN -- #Agent

        CREATE TABLE #Agent( CustId INT PRIMARY KEY,
                             Site   NVARCHAR(50));
        IF @Site = 'Deposit'
            BEGIN
                INSERT INTO #Agent
                       SELECT c.CustId,
                              Site
                       FROM customer AS c WITH ( NOLOCK )
                       WHERE c.RoleID = 2
                         AND EXISTS( 
                                     SELECT 1
                                     FROM f_DepSuper_1( 'All' ) dep
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
                                         FROM f_DepSuper_1( 'All' ) dep
                                         WHERE c.srecommend = dep.CustId );
            END;
    END;
    BEGIN ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( SuperID INT,
                                   ExtraPT DECIMAL(9, 8));
        INSERT INTO #ExtraPT_Sel
               ( SuperID,
                 ExtraPT
               )
               SELECT SuperId,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
                 AND a.ProductId = 1
                 AND a.SubProduct IN( 'BT-Comm', 'BT-Winloss' )
				 AND a.Sporttype = 0
               GROUP BY SuperId;
    END;
    BEGIN -- Query

        SELECT Site AS RowName,
               SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
               SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
               SUM(scomm * actualrate) Commission,
               SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                             WHEN tpositiontaking = 1
                                                                                             THEN 0
                                                                                             ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                         END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                WHEN virtualrate / actualrate - 1 > 0
                                                                                                THEN virtualrate
                                                                                                ELSE actualrate
                                                                                            END
                   END) AS RealTurnover
        FROM bettrans AS b WITH ( NOLOCK )
             INNER JOIN #SportBetType sb ON b.BetType = sb.BetType
             INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
             LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
        WHERE b.winlostdate = @StartDate
          AND b.ruben = 1
          AND b.statusID IN( 111, 112, 113 )
        GROUP BY Site
        ORDER BY RowName;
    END;
        DROP TABLE #Agent;
        DROP TABLE #SportBetType;
        DROP TABLE #ExtraPT_Sel;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_Site] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_Site] TO [vnteam];
GO