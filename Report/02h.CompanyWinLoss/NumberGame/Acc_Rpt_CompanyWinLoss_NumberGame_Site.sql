
/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_NumberGame_Site @StartDate SMALLDATETIME,
                                                           @EndDate   SMALLDATETIME,
                                                           @LeagueId  INT,
                                                           @BetType   INT,
                                                           @Site      VARCHAR(50)
AS

/*	Creator: Robert.Tran
	Date: 2018-12-18
	Task: Company Winloss Report - Number Game - HP2 SP [Redmine: #104253]
	DB: DBACC/bodb02	

	Revisions:
- 20181217@Robert: #104253 - NAP Report - Add new sporttype for Happy 5
- 20190925@Jacob: Group By CN88 (#118824)

	Explanation's Param:   

*/

     SET NOCOUNT ON;
         BEGIN -- #Agent
             CREATE TABLE #Agent
                          (CustId INT
                           PRIMARY KEY,
                           Site   VARCHAR(50)
                          );
             IF @Site = 'CN88'
                 BEGIN
                     INSERT INTO #Agent
                            SELECT c.CustId,
                                   Site
                            FROM customer AS c WITH (NOLOCK)
                                 INNER JOIN CS_CustSuper cn88 WITH (NOLOCK) ON c.srecommend = cn88.CustId
                            WHERE c.RoleID = 2;
                 END;
                 ELSE
             IF @Site = 'Deposit'
                 BEGIN
                     INSERT INTO #Agent
                            SELECT c.CustId,
                                   Site
                            FROM customer AS c WITH (NOLOCK)
                                 INNER JOIN Dep_CustSuper AS dep WITH (NOLOCK) ON c.srecommend = dep.CustId
                            WHERE c.RoleID = 2
                                  AND c.CustId NOT IN(52466, 5707545);
                     INSERT INTO #Agent
                            SELECT 5707545,
                                   'BEST-ODDS';
                 END;
                 ELSE
                 BEGIN
                     INSERT INTO #Agent
                     SELECT c.CustId,
                            Site
                     FROM customer AS c WITH (NOLOCK)
                          LEFT JOIN Dep_CustSuper AS dep WITH (NOLOCK) ON c.srecommend = dep.CustId
                          LEFT JOIN CS_CustSuper cn88 WITH (NOLOCK) ON c.srecommend = cn88.CustId
                     WHERE c.RoleID = 2
                           AND c.CustId NOT IN(52466, 5707545)
                          AND dep.CustId IS NULL
                          AND cn88.CustId IS NULL
                     SELECT 52466,
                            'XYZBET';--8RM;
                 END;
         END;
         BEGIN -- Get Sport Bettype Matrix
             DECLARE @isTest BIT= 0;
             SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
             DECLARE @ProductID INT;
             SELECT DISTINCT
                    @ProductID = s.ProductID
             FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', 1) AS s
                  INNER JOIN dbo.SportBettypeMatrix AS t WITH (NOLOCK) ON t.BetType = s.BetType
                                                                          AND t.ProductId = s.ProductId
             WHERE s.bettype = @BetType;
         END;
         BEGIN -- Extra PT

             CREATE TABLE #ExtraPT_Sel
                          (SuperID   INT,
                           Sporttype INT,
                           ExtraPT   DECIMAL(9, 8)
                          );
             INSERT INTO #ExtraPT_Sel
                    (SuperID,
                     Sporttype,
                     ExtraPT
                    )
                    SELECT SuperId,
                           a.Sporttype,
                           SUM(ExtraPT) AS ExtraPT
                    FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
                    WHERE @StartDate BETWEEN FromDate AND Todate
                          AND a.ProductId = @ProductID
                    GROUP BY SuperId,
                             a.Sporttype;
         END;
         BEGIN  -- Query


             SELECT Site AS RowName,
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
                  INNER JOIN match AS m WITH (nolock) ON b.MatchId = m.MatchId
                  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
                  LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
             WHERE b.winlostdate = @StartDate
                   AND m.leagueid = @LeagueId
                   AND b.BetType = @BetType
                   AND b.ruben = 1
                   AND b.statusID IN(111, 112, 113)
             GROUP BY Site
             ORDER BY RowName;
         END;
     DROP TABLE #Agent;
     DROP TABLE #ExtraPT_Sel;
GO
