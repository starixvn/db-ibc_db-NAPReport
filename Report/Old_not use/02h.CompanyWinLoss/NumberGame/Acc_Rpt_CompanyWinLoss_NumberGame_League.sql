USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_NumberGame_League @StartDate SMALLDATETIME, 
                                                             @EndDate   SMALLDATETIME, 
                                                             @SportType INT
AS

/*	Creator: Robert.Tran
	Date: 2016-05-11
	Task: Company Winloss Report - Number Game - HP2 SP [Redmine: #104253]
	DB: DBACC/bodb02	

	Revisions:
		- 20181217@Robert: #104253 - NAP Report - Add new sporttype for Happy 5
		- 20190925@Jacob: Group By CN88 (#118824)
		- 20191212@Ned.Le: Support to get Extra PT from Extra PT column (#125286)
          - 20212203@Jaden: Support SABA789 (#151326)
          
	Explanation's Param:   

*/

     SET NOCOUNT ON;
     DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME, @Sport INT;
     SELECT @FDate = @StartDate, 
            @TDate = @EndDate, 
            @Sport = @SportType;
    BEGIN -- #DepositSuper

        CREATE TABLE #DepositSuper
                     (CustId INT
                      PRIMARY KEY
                     );
        INSERT INTO #DepositSuper
               SELECT CustId
               FROM DBWH.bodb_Account.dbo.vw_Dep_CustSuper WITH (NOLOCK)
    END;
    BEGIN -- #Match
        CREATE TABLE #Match
                     (MatchId    INT, 
                      LeagueId   INT, 
                      LeagueName NVARCHAR(500) NULL
                     );
        INSERT INTO #Match
               SELECT MatchId, 
                      l.LeagueId, 
                      l.LeagueName
               FROM [match] m WITH(NOLOCK)
                    INNER JOIN league l WITH(NOLOCK) ON m.leagueid = l.leagueId
               WHERE m.sporttype = @Sport
                     AND l.sporttype = @Sport;
    END;
    BEGIN -- Query

        SELECT m.leagueid AS GroupId, 
               m.leaguename AS GroupName,
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
             INNER JOIN #Match AS m WITH(NOLOCK) ON b.MatchId = m.MatchId
             LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
             LEFT JOIN CS_CustSuper AS cn88 WITH(NOLOCK) ON b.srecommend = cn88.CustId
        WHERE b.winlostdate = @FDate
              AND b.ruben = 1
              AND b.statusID IN(111, 112, 113)
        GROUP BY m.leagueid, 
                 m.leaguename,
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
    
	DROP TABLE #Match;
    DROP TABLE #DepositSuper;
GO