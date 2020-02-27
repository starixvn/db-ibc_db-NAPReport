/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_NumberGame_Bettype @StartDate SMALLDATETIME, 
                                                              @EndDate   SMALLDATETIME, 
                                                              @SportType INT, 
                                                              @LeagueId  INT
AS

/*	Creator: Robert.Tran
	Date: 2018-12-18
	Task: Company Winloss Report - Number Game - HP2 SP [Redmine: #104253]
	DB: DBACC/bodb02	

	Revisions:
		- 20181217@Robert: #104253 - NAP Report - Add new sporttype for Happy 5
		- 20190925@Jacob: Group By CN88 (#118824)
		- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)

	Explanation's Param:   

*/

     SET NOCOUNT ON;
     DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME, @Sport INT, @League INT;
     SELECT @FDate = @StartDate, 
            @TDate = @EndDate, 
            @League = @LeagueId, 
            @Sport = @SportType;
    BEGIN  --#SportBetType     

        DECLARE @isTest BIT= 0;
        SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
        CREATE TABLE #SportBetType
                     (BetType     INT, 
                      BetTypeName NVARCHAR(50)
                     );
        INSERT INTO #SportBetType
               SELECT b.typeid, 
                      b.typenamee
               FROM dbo.f_SportBetTypeMatrix_Sel(3, @Sport, 0, 2, '', '', @isTest) AS s
                    INNER JOIN BetType AS b WITH(NOLOCK) ON s.BetType = b.typeid;
    END;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper
                     (CustId INT
                      PRIMARY KEY
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
                        AND cn88.CustId IS NOT NULL
                   THEN 'CN88'
                   WHEN dep.CustId IS NULL
                        AND cn88.CustId IS NULL
                   THEN 'Credit'
                   ELSE 'Deposit'
               END AS RowName, 
               SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss, 
               SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss, 
               -SUM(CASE
                        WHEN b.tpositiontaking = 1
                        THEN 0
                        ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                    END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT, 
               SUM(scomm * actualrate) AS Commission, 
               SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                          WHEN tpositiontaking = 1
                                                                                          THEN 0
                                                                                          ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                      END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome, 
               SUM(CASE
                       WHEN tpositiontaking = 1
                       THEN 0
                       ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * b.stake * CASE
                                                                                          WHEN virtualrate > actualrate
                                                                                          THEN virtualrate
                                                                                          ELSE actualrate
                                                                                      END
                   END) AS RealTurnover
        FROM bettrans AS b WITH(NOLOCK)
             INNER JOIN match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
             INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
        WHERE b.winlostdate = @FDate
              AND m.leagueid = @League
              AND b.ruben = 1
              AND b.statusID IN(111, 112, 113)
        GROUP BY sb.BetType, 
                 sb.BetTypeName,
                 CASE
                     WHEN dep.CustId IS NULL
                          AND cn88.CustId IS NOT NULL
                     THEN 'CN88'
                     WHEN dep.CustId IS NULL
                          AND cn88.CustId IS NULL
                     THEN 'Credit'
                     ELSE 'Deposit'
                 END
        ORDER BY GroupName, 
                 RowName;
    END;
    
	DROP TABLE #SportBetType;
    DROP TABLE #DepositSuper;
GO