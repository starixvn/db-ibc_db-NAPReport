/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/




ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_FishingWorld_Site
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @BetType      INT
   , @Site         VARCHAR(50)
   , @IsLive       INT           = 2
AS
/*
Creator: Jacob
Date: 2016-12-01
Task:  Integrate Fishing World Product [#67757]
DB: DBACC/bodb02

Revisions:
    20161201@Jacob: Integrate Fishing World Product [#67757]
    - 2018.04.19@Franklin: Apply new concept for turnover, virtual win loss and Extra PT (#85003)
    - 20181018@Robert: Fix performance issue on House Win Loss by Product [#103309]
Parameters:
    @IsLive: Jacob add this dummy parameter to make it consistent with [Acc_Rpt_CompanyWinLoss_Universal_Site]

Example:
EXEC [Acc_Rpt_CompanyWinLoss_FishingWorld_Site] @BetType = 1011,@EndDate='2020-01-01',@Site = 'Credit',@StartDate='2016-11-27'
*/

SET NOCOUNT ON;
BEGIN -- #SportBetType

    DECLARE @isTest    BIT = 0;
    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    CREATE TABLE #SportBetType(
	    BetType     INT
	  , RefTable    INT);
    INSERT INTO #SportBetType
		 SELECT BetType
			 , RefTable
		 FROM bodb02.dbo.f_SportBetTypeMatrix_Sel
			 (0, 0, @BetType, 2, '', '', @isTest);
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
	    SuperID    INT
	  , ExtraPT    DECIMAL(9, 8));
    INSERT INTO #ExtraPT_Sel(SuperID
					  , ExtraPT)
		 SELECT SuperId
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND a.ProductId = 24
		 GROUP BY SuperId;
END;
BEGIN -- Query


    SELECT dep.Site AS                                                                                                         RowName
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
    FROM bettransRNG AS b WITH (NOLOCK)
	   INNER JOIN #Agent AS dep ON b.recommend = dep.custid
	   LEFT JOIN #ExtraPT_Sel AS e ON e.SuperID = b.srecommend
    WHERE b.winlostdate = @StartDate
		AND b.gameId = @BetType
		AND b.statusID IN(111, 112, 113)
    GROUP BY dep.Site
    ORDER BY RowName;
END;
DROP TABLE #SportBetType;
DROP TABLE #Agent;
DROP TABLE #ExtraPT_Sel;
GO
