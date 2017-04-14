IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_FishingWorld_BetType]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_FishingWorld_BetType];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_FishingWorld_BetType] @StartDate SMALLDATETIME,
                                                                     @EndDate   SMALLDATETIME,
                                                                     @ProductId INT           = 24,
                                                                     @SportType INT           = 0,
                                                                     @IsLive    INT           = 2
AS


/*
Creator: Jacob
Date: 2016-12-01
Task:  Integrate Fishing World Product [#67757]
DB: DBACC/bodb02

Revisions:
- 20161201@Jacob: Integrate Fishing World Product [#67757]
   
Parameters:
@ProductId: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_BetType]
@SportType: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_BetType]
@IsLive: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_BetType]

Example:
EXEC [Acc_Rpt_CompanyWinLoss_FishingWorld_BetType] @EndDate='2020-01-01',@StartDate='2016-11-28'
*/

     SET NOCOUNT ON;
     BEGIN --#SportBetType     
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType     INT,
          BetTypeName NVARCHAR(50)
         );
         INSERT INTO #SportBetType
                SELECT BetType,
                       b.typenamee
                FROM dbo.f_SportBetTypeMatrix_Sel(24, 0, 0, 2, '', '', @isTest) s
                     INNER JOIN BetType b WITH (NOLOCK) ON b.typeid = s.BetType;
     END;
     BEGIN -- #DepositSuper

         CREATE TABLE #DepositSuper
         (CustId INT PRIMARY KEY
         );
         INSERT INTO #DepositSuper
                SELECT CustId
                FROM f_DepSuper_1('All');
     END;
     BEGIN -- Query

         SELECT sb.BetType AS GroupId,
                sb.BetTypeName AS GroupName,
                CASE
                    WHEN dep.CustId IS NULL
                    THEN 'Credit'
                    ELSE 'Deposit'
                END AS RowName,
                SUM((winlost - actual_stake) * actualrate) MemberWinLoss,
                SUM((awinlost + mwinlost + swinlost) * actualrate) SMAWinLoss,
                SUM(scomm * actualrate) Commission,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) RealIncome,
                SUM((1 - tpositiontaking) * ABS(stake) * actualrate) RealTurnover
         FROM bettransRNG b WITH (NOLOCK)
              INNER JOIN #SportBetType sb ON sb.BetType = b.gameID
              LEFT JOIN #DepositSuper dep ON b.srecommend = dep.custid
         WHERE b.winlostdate = @StartDate
               AND b.statusID IN(111, 112, 113)
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
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_FishingWorld_BetType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_FishingWorld_BetType] TO [vnteam];
GO