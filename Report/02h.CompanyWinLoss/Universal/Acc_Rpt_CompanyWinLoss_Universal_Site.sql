/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/




ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Universal_Site
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @BetType      INT
   , @Site         VARCHAR(50)
   , @IsLive       INT           = 2
AS
/*
Creator: 20160215@Robert
Task:  Casino Integration Improvement - Implement Company Winloss By Products report [#48448]
DB: DBACC/bodb02

Revisions:
	 - 20160222@Robert: Improve Company Win Loss Report - Universal Product
	 - 20161001@Jacob: Integrate new product NG2 - #63460
	 - 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
	 - 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
Parameter's Explanation:
	- @Site: credit, deposit
Example:
EXEC [Acc_Rpt_CompanyWinLoss_Universal_Site] @StartDate='2016-01-01', @EndDate='2020-01-01', @Site = 'Credit', @BetType = 18000


*/

SET NOCOUNT ON;
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
BEGIN
/*----Get Sport Bettype Matrix------
         Check SP Version	 */

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    DECLARE @ProductID    INT;

    SELECT DISTINCT
		 @ProductID = s.ProductID
    FROM dbo.f_SportBettypeMatrix_Sel
	    (0, 0, 0, 2, '', '', 1) AS s
	   INNER JOIN dbo.SportBettypeMatrix AS t WITH (NOLOCK) ON t.BetType = s.BetType
												    AND t.ProductId = s.ProductId
    WHERE s.bettype = @BetType;
--- End Sport Bettype Matrix------
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
			 , a.Sporttype
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND a.ProductId = @ProductID
		 GROUP BY SuperId
			   , a.Sporttype;
END;
BEGIN -- Query


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
	   INNER JOIN #Agent AS dep ON b.recommend = dep.CustId
	   LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
    WHERE b.winlostdate = @StartDate
		AND
		    (@IsLive = 2
			OR b.liveindicator = @IsLive)
		AND b.BetType = @BetType
		AND b.ruben = 1
		AND b.statusID IN(111, 112, 113)
    GROUP BY Site
    ORDER BY RowName;
END;
DROP TABLE #Agent;
DROP TABLE #ExtraPT_Sel;
GO
