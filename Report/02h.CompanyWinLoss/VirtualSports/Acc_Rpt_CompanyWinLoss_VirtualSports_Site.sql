/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/




ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_VirtualSports_Site
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @SportType    SMALLINT
   , @BetType      INT
   , @Site         VARCHAR(20)
AS
/*Creator:
Jacob;
Date: 2016-03-01
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
- 20160301@Jacob: Initialize Company Win Loss Report
- 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
- 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
- 20190925@Jacob: Group By CN88 (#118824)
Example:
EXEC [Acc_Rpt_CompanyWinLoss_VirtualSports_Site] @StartDate='2016-01-01', @EndDate='2020-01-01', @SportType = 180, @BetType = 1203, @Site = 'Credit'
*/

SET NOCOUNT ON;
BEGIN --@EventType

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    DECLARE @EventType    INT;
    SELECT @EventType = s.EventType
    FROM dbo.f_SportBetTypeMatrix_Sel
	    (5, @SportType, @BetType, 2, '', '', @isTest) AS s;
END;
BEGIN -- #Agent


    CREATE TABLE #Agent(
	    CustId    INT
	    PRIMARY KEY
	  , Site      VARCHAR(50));
    IF @Site = 'Deposit'
	   BEGIN
		  INSERT INTO #Agent
			    SELECT c.CustId
				    , Site
			    FROM customer AS c WITH (NOLOCK)
			    WHERE c.RoleID = 2
					AND EXISTS
							 (
								SELECT 1
								FROM Dep_CustSuper AS dep WITH (NOLOCK)
								WHERE c.srecommend = dep.CustId
							 );
	   END;
	   ELSE
	   BEGIN
		  INSERT INTO #Agent
		  SELECT c.CustId
			  , Site
		  FROM customer AS c WITH (NOLOCK)
		  WHERE c.RoleID = 2
			   AND NOT EXISTS
						   (
							  SELECT 1
							  FROM Dep_CustSuper AS dep WITH (NOLOCK)
							  WHERE c.srecommend = dep.CustId
						   );
	   END;
END;
BEGIN ---- Extra PT

    CREATE TABLE #ExtraPT_Sel(
	    SuperID      INT
	  , Sporttype    INT
	  , ExtraPT      DECIMAL(9, 8));
    INSERT INTO #ExtraPT_Sel(SuperID
					  , Sporttype
					  , ExtraPT)
		 SELECT SuperId
			 , Sporttype
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND a.ProductId = 5
		 GROUP BY SuperId
			   , Sporttype;
END;
IF @EventType = 1 -- Virtual Soccer

    BEGIN
	   SELECT Site AS                                                                                                             RowName
		   , SUM((winlost - actual_stake) * actualrate) AS                                                                       MemberWinLoss
		   , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                                               SMAWinLoss
		   , -SUM(CASE
				    WHEN b.tpositiontaking = 1
				    THEN 0
				    ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
				END * ISNULL(e.ExtraPT, 0) * actualrate) AS                                                                    ExtraPT
		   , SUM(scomm * actualrate) AS                                                                                          Commission
		   , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																		WHEN tpositiontaking = 1
																		THEN 0
																		ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																	 END * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome
		   , SUM(CASE
				   WHEN tpositiontaking = 1
				   THEN 0
				   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
																		WHEN virtualrate > actualrate
																		THEN virtualrate
																		ELSE actualrate
																	 END
			    END) AS                                                                                                         RealTurnover
	   FROM bettrans AS b WITH (NOLOCK)
		  INNER JOIN match AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
		  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
		  LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
	   WHERE b.winlostdate = @StartDate
		    AND b.BetType = @BetType
		    AND m.sporttype = @SportType
		    AND b.MatchId > 0
		    AND b.ruben = 1
		    AND b.statusID IN(111, 112, 113)
	   GROUP BY Site
	   ORDER BY RowName;
    END;
    ELSE -- Virtual HR
    BEGIN
	   SELECT Site AS                                                                                                               RowName
		   , SUM((winlost - actual_stake) * actualrate) AS                                                                         MemberWinLoss
		   , SUM((awinlost + mwinlost + swinlost) * actualrate) AS                                                                 SMAWinLoss
		   , -SUM((CASE
					WHEN b.tpositiontaking = 1
					THEN 0
					ELSE(winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
				 END) * ISNULL(e.ExtraPT, 0) * actualrate) AS                                                                    ExtraPT
		   , SUM(scomm * actualrate)                                                                                               Commission
		   , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - (CASE
																		 WHEN tpositiontaking = 1
																		 THEN 0
																		 ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																	  END) * ISNULL(e.ExtraPT, 0)) * actualrate) AS RealIncome
		   , SUM(CASE
				   WHEN tpositiontaking = 1
				   THEN 0
				   ELSE(1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0)) * b.stake * CASE
																		WHEN virtualrate > actualrate
																		THEN virtualrate
																		ELSE actualrate
																	 END
			    END) AS                                                                                                           RealTurnover
	   FROM bettrans AS b WITH (NOLOCK)
		  INNER JOIN VSRaceInfo AS r WITH (NOLOCK) ON r.EventId = b.MatchId
		  INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
		  LEFT JOIN #ExtraPT_Sel e ON e.SuperID = b.srecommend
	   WHERE b.winlostdate = @StartDate
		    AND b.BetType = @BetType
		    AND r.sporttype = @SportType
		    AND b.MatchId > 0
		    AND b.ruben = 1
		    AND b.statusID IN(111, 112, 113)
	   GROUP BY Site
	   ORDER BY RowName;
    END;
DROP TABLE #Agent;
DROP TABLE #ExtraPT_Sel;
GO
