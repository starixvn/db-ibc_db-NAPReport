
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

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
                    FROM f_DepSuper_1('All');
         END;
         BEGIN   -- Extra PT

             CREATE TABLE #ExtraPT_Sel
                          (SuperID INT,
                           ExtraPT DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraPT_Sel
                    (SuperID,
                     ExtraPT
                    )
                    SELECT SuperId,
                           SUM(ExtraPT) AS ExtraPT
                    FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
                    WHERE @FDate BETWEEN FromDate AND Todate
                          AND a.ProductId = 3
                    GROUP BY SuperId;
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
                    FROM [match] m WITH (NOLOCK)
                         INNER JOIN league l WITH (nolock) ON m.leagueid = l.leagueId
                    WHERE m.sporttype = @Sport
                          AND l.sporttype = @Sport;
         END;
         BEGIN -- Query


             SELECT m.leagueid AS GroupId,
                    m.leaguename AS GroupName,
                    CASE
                        WHEN dep.CustId IS NULL
                        THEN 'Credit'
                        ELSE 'Deposit'
                    END AS RowName,
                    SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss,
                    SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss,
                    -SUM(CASE
                             WHEN b.tpositiontaking = 1
                             THEN 0
                             ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                         END * ISNULL(e.ExtraPT, 0) * actualrate) AS ExtraPT,
                    SUM(scomm * actualrate) AS Commission,
                    SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
                                                                                               WHEN tpositiontaking = 1
                                                                                               THEN 0
                                                                                               ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
                                                                                           END * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome,
                    SUM(CASE
                            WHEN tpositiontaking = 1
                            THEN 0
                            ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
                                                                                               WHEN virtualrate > actualrate
                                                                                               THEN virtualrate
                                                                                               ELSE actualrate
                                                                                           END
                        END) AS RealTurnover
             FROM bettrans AS b WITH (NOLOCK)
                  INNER JOIN #Match AS m WITH (nolock) ON b.MatchId = m.MatchId
                  LEFT JOIN #DepositSuper AS dep ON b.srecommend = dep.CustId
                  LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @FDate
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY m.leagueid,
                      m.leaguename,
                      CASE
                          WHEN dep.CustId IS NULL
                          THEN 'Credit'
                          ELSE 'Deposit'
                      END
             ORDER BY GroupName,
                      RowName;
         END;
     DROP TABLE #Match;
     DROP TABLE #DepositSuper;
     DROP TABLE #ExtraPT_Sel;
         
