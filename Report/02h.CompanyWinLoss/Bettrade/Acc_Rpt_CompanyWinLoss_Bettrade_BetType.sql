/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_BetType]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_Bettrade_BetType    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_BetType]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME
AS

/*
Creator: Franklin
Date: 2016-02-24
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160224@Franklin: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)

Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Bettrade_BetType] @StartDate='2016-01-01', @EndDate='2020-01-01'
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
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper( CustId INT PRIMARY KEY );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1( 'All' );
    END;
    BEGIN -- Query

        SELECT 0 AS GroupId,
               'Bettrade' AS GroupName,
                             CASE
                                 WHEN dep.CustId IS NULL
                                 THEN 'Credit'
                                 ELSE 'Deposit'
                             END AS RowName,
               SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
               SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
			   -SUM((CASE
                              WHEN b.tpositiontaking = 1
                              THEN 0
                              ELSE(winlost - actual_stake ) + b.scomm / ( 1 - b.tpositiontaking )
                          END) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
               SUM(scomm * actualrate) Commission,
               SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE
                                                                                             WHEN tpositiontaking = 1
                                                                                             THEN 0
                                                                                             ELSE winlost - actual_stake + b.scomm / ( 1 - b.tpositiontaking )
                                                                                         END ) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * ABS(b.stake) * CASE
                                                                                                WHEN virtualrate > actualrate
                                                                                                THEN virtualrate
                                                                                                ELSE actualrate
                                                                                            END
                   END) AS RealTurnover
        FROM bettrans AS b WITH ( NOLOCK )
             INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
        WHERE b.winlostdate = @StartDate
          AND b.ruben = 1
          AND b.statusID IN( 111, 112, 113 )
        GROUP BY CASE
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
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Bettrade_BetType] TO [vnteam];
GO