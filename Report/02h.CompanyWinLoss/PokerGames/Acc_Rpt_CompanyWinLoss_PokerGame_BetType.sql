/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_PokerGames_BetType]
       @StartDate SMALLDATETIME,
       @EndDate   SMALLDATETIME,
       @ProductId INT = 33,
       @SportType INT = 0,
       @IsLive    INT = 2
AS

/*	
Creator: 20180824@Cherry
Task:  Poker Games Integration - Implement Company Winloss By Products report [#97830]
DB: DBACC/bodb02

Revisions: 
	 
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_PokerGames_BetType] @StartDate='2018-08-21', @EndDate='2018-08-21', @ProductId = 33, @SportType = 0
		
*/

    BEGIN
        SET NOCOUNT ON;
        DECLARE @FDate SMALLDATETIME,
                @TDate SMALLDATETIME

        SELECT @FDate = @StartDate,
               @TDate = @EndDate

        BEGIN --#SportBetType     
            DECLARE @isTest BIT = 0;
            SELECT @isTest = dbo.f_CheckSPVersion( @@PROCID );
            CREATE TABLE #SportBetType( BetType     INT,
                                        BetTypeName NVARCHAR(50));
            INSERT INTO #SportBetType
                   SELECT b.typeid,
                          b.typenamee
                   FROM dbo.f_SportBetTypeMatrix_Sel( @ProductId, @SportType, 0, 2, '', '', @isTest ) s
                        INNER JOIN BetType b WITH ( NOLOCK ) ON s.BetType = b.typeid;
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
               SELECT SuperId,Sporttype,
                      SUM(ExtraPT) AS ExtraPT
               FROM bodb02.dbo.Acc_GroupExtraPTSetting a WITH ( NOLOCK )
                   WHERE @StartDate BETWEEN FromDate AND Todate
                     AND a.ProductId = 33
                GROUP BY SuperId,Sporttype;
        END;
        BEGIN -- Query

            SELECT sb.BetType AS GroupId,
                   sb.BetTypeName AS GroupName,
                                     CASE
                                         WHEN dep.CustId IS NULL
                                         THEN 'Credit'
                                         ELSE 'Deposit'
                                     END AS RowName,
                   SUM(( winlost - actual_stake ) * actualrate) AS MemberWinLoss,
                   SUM(( awinlost + mwinlost + swinlost ) * actualrate) AS SMAWinLoss,
				   -SUM((-b.oddsspread) * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                   SUM(scomm * actualrate) Commission,
                   SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (-b.oddsspread) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                   0 AS RealTurnover
            FROM bettrans AS b WITH ( NOLOCK )
                 INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
                 LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                 LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
            WHERE b.winlostdate = @FDate
              AND ( @IsLive = 2
                 OR b.liveindicator = @IsLive
                  )
              AND b.ruben = 1
              AND b.statusID IN( 111, 112, 113 )
            GROUP BY sb.BetType,
                     sb.BetTypeName,
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
    END;
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_PokerGames_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_PokerGames_BetType] TO [vnteam];
GO