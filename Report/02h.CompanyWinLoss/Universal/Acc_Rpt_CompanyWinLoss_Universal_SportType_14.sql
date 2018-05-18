USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType_14]    Script Date: 5/9/2018 12:43:06 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Acc_Rpt_CompanyWinLoss_Universal_SportType_14    Script Date: 5/2/2018 9:36:29 AM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType_14]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @ProductId INT
AS

/*	
Creator: 20160921@Jacob
Task:  Integrate new product NG2 [#63460]
DB: DBACC/bodb02

Revisions: 
	- 20160921@Jacob: NG2 - Redmine[#63460]
	- 20160923@Percy: Using local variable to prevent bad parameter sniffing [RedmineID: #64573]
	- 20161123@Jacob: Get sport type from bet type - SportBettypeMatrix [RedmineID: #67688]
	- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Universal_SportType_14] @StartDate='2016-11-07', @EndDate='2020-01-01', @ProductId = 23
		
*/


     SET NOCOUNT ON;
     DECLARE @FDate SMALLDATETIME,
             @TDate SMALLDATETIME,
             @ProID INT;
     SELECT @FDate = @StartDate,
            @TDate = @EndDate,
            @ProID = @ProductId;
    BEGIN --#SportBetType     
        DECLARE @isTest BIT = 0;
        SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
        CREATE TABLE #SportBetType( BetType   INT,
                                    SportType INT,
                                    SportName NVARCHAR(100));
        INSERT INTO #SportBetType
               SELECT DISTINCT t.BetType,
                               t.SportType,
                               d.SportName
               FROM dbo.f_SportBetTypeMatrix_Sel( @ProID, 0, 0, 2, '', '', @isTest ) s
                    INNER JOIN dbo.SportBettypeMatrix t WITH ( NOLOCK ) ON t.BetType = s.BetType
                                                                       AND t.ProductId = s.ProductId
                    INNER JOIN dbo.Sports AS d WITH ( NOLOCK ) ON d.SportType = t.SportType;
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper( CustId INT PRIMARY KEY );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM f_DepSuper_1( 'All' );
    END;
    BEGIN ---- Extra PT 
        CREATE TABLE #ExtraPT_Sel( SuperID INT,
								   Sporttype  INT,
                                   ExtraPT DECIMAL(9, 8));
            INSERT INTO #ExtraPT_Sel
               ( SuperID,
			     Sporttype,
                 ExtraPT
               )
               SELECT SuperId, a.Sporttype,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
               WHERE @StartDate BETWEEN FromDate AND Todate
                 AND a.ProductId = @ProID
               GROUP BY SuperId, a.Sporttype;
    END;
    BEGIN -- Query

        SELECT sb.SportType GroupId,
               sb.SportName GroupName,
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
                       ELSE( 1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                                WHEN virtualrate / actualrate - 1 > 0
                                                                                                THEN virtualrate
                                                                                                ELSE actualrate
                                                                                            END
                   END) AS RealTurnover
        FROM bettrans14 AS b WITH ( NOLOCK )
             INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
        WHERE b.winlostdate = @FDate
          AND b.ruben = 1
          AND b.statusID IN( 111, 112, 113 )
        GROUP BY sb.SportType,
                 sb.SportName,
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
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType_14] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType_14] TO [vnteam];
GO