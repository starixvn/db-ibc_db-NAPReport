IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType]')
          AND type IN(N'P', N'PC')
)
    DROP PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType];
GO
CREATE PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType] @StartDate SMALLDATETIME,
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
Example: 
EXEC [Acc_Rpt_CompanyWinLoss_Universal_SportType] @StartDate='2016-11-07', @EndDate='2020-01-01', @ProductId = 23
		
*/


     SET NOCOUNT ON;
     DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME, @ProID INT;
     SELECT @FDate = @StartDate,
            @TDate = @EndDate,
            @ProID = @ProductId;
     BEGIN --#SportBetType     
         DECLARE @isTest BIT= 0;
         SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
         CREATE TABLE #SportBetType
         (BetType   INT,
          SportType INT,
          SportName NVARCHAR(100)
         );
         INSERT INTO #SportBetType
                SELECT DISTINCT
                       t.BetType,
                       t.SportType,
                       d.SportName
                FROM dbo.f_SportBetTypeMatrix_Sel(@ProID, 0, 0, 2, '', '', @isTest) s
                     INNER JOIN dbo.SportBettypeMatrix t WITH (NOLOCK) ON t.BetType = s.BetType
                                                                          AND t.ProductId = s.ProductId
                     INNER JOIN dbo.Sports AS d WITH (NOLOCK) ON d.SportType = t.SportType;
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

         SELECT sb.SportType GroupId,
                sb.SportName GroupName,
                CASE
                    WHEN dep.CustId IS NULL
                    THEN 'Credit'
                    ELSE 'Deposit'
                END AS RowName,
                SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                SUM(scomm * actualrate) Commission,
                SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS RealIncome,
                SUM((1 - tpositiontaking) * ABS(stake) * actualrate) AS RealTurnover
         FROM bettrans AS b WITH (NOLOCK)
              INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
              LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
         WHERE b.winlostdate = @FDate
               AND b.ruben = 1
               AND b.statusID IN(111, 112, 113)
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
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType] TO [bodbAdminNet];
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Universal_SportType] TO [vnteam];
GO