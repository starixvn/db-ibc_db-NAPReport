/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02];
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Parlay_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
AS
/*	
    Creator: Robert
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #116083]
	DB: DBACC/bodb02	
		
	Revisions:
		- 20190710@Robert: 	NAP Report - Implement new report to match with CN88's need [#116083]
		- 20191212@Ned.Le:  Support to get Extra PT from Extra PT column [#125286]
	Explanation's Param:	
*/
BEGIN
    SET NOCOUNT ON;

    BEGIN -- #Data
	   CREATE TABLE #Data(
		   GroupId            INT
		 , GroupName          NVARCHAR(50)
		 , MemberWinLoss      MONEY
		 , SMAWinLoss         MONEY
		 , ExtraPT            MONEY
		 , Commission         MONEY
		 , RealIncome         MONEY
		 , VirtualIncome      MONEY
		 , VarianceIncome     MONEY
		 , RealTurnover       MONEY
		 , VirtualTurnover    MONEY);
    END;
    BEGIN -- Query
	   INSERT INTO #Data
			SELECT CASE
					 WHEN bettype = 9
						 OR bettype = 29
						 AND betteam = '1'
					 THEN 9
					 ELSE 29
				  END AS GroupId
				, CASE
					 WHEN bettype = 9
						 OR bettype = 29
						 AND betteam = '1'
					 THEN 'Mix Parlay'
					 ELSE 'System Parlay'
				  END AS GroupName
				, SUM((winlost - actual_stake) * actualrate) AS MemberWinlost
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
					 END * ISNULL(b.epositiontaking, 0) * actualrate) AS ExtraPT
				, SUM(scomm * actualrate) AS Commission
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																			  WHEN tpositiontaking = 1
																			  THEN 0
																			  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		   END * ISNULL(b.epositiontaking, 0)) * actualrate) AS RealIncome
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	    WHEN tpositiontaking = 1
																	    THEN 0
																	    ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																	END) * virtualrate + (scomm - CASE
																							    WHEN tpositiontaking = 1
																							    THEN 0
																							    ELSE b.scomm / (1 - b.tpositiontaking)
																							END * ISNULL(b.epositiontaking, 0)) * actualrate * CASE
																																  WHEN virtualrate < actualrate
																																  THEN virtualrate / actualrate
																																  ELSE 1
																															   END) AS VirtualIncome
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	    WHEN tpositiontaking = 1
																	    THEN 0
																	    ELSE(winlost - actual_stake) * ISNULL(b.epositiontaking, 0)
																	END + CASE
																			WHEN virtualrate < actualrate
																			THEN b.scomm - CASE
																						    WHEN tpositiontaking = 1
																						    THEN 0
																						    ELSE b.scomm / (1 - b.tpositiontaking)
																						END * ISNULL(b.epositiontaking, 0)
																			ELSE 0
																		 END) * (actualrate - virtualrate)) AS VarianceIncome
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * CASE
																				  WHEN virtualrate > actualrate
																				  THEN virtualrate
																				  ELSE actualrate
																			   END
					 END) AS RealTurnover
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * ABS(b.stake) * virtualrate
					 END) AS VirtualTurnover
			FROM bettrans AS b WITH (NOLOCK)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			WHERE b.winlostdate = @StartDate
				 AND BetType IN(9, 29)
				 AND b.ruben = 1
				 AND b.statusID IN(111, 112, 113)
			GROUP BY CASE
					   WHEN bettype = 9
						   OR bettype = 29
						   AND betteam = '1'
					   THEN 9
					   ELSE 29
				    END
				  , CASE
					   WHEN bettype = 9
						   OR bettype = 29
						   AND betteam = '1'
					   THEN 'Mix Parlay'
					   ELSE 'System Parlay'
				    END;
    END;
    BEGIN -- Query
	   SELECT d.GroupId AS GroupId
		   , d.GroupName AS GroupName
		   , d.MemberWinLoss AS MemberWinLoss
		   , d.SMAWinLoss AS SMAWinLoss
		   , -d.ExtraPT AS HeadlineIncome
		   , d.Commission AS Commission
		   , d.RealIncome AS RealIncome
		   , d.VirtualIncome AS VirtualIncome
		   , d.VarianceIncome AS VarianceIncome
		   , d.RealTurnover AS RealTurnover
		   , d.VirtualTurnover AS VirtualTurnover
	   FROM #Data AS d
	   ORDER BY GroupName DESC;
    END;

    DROP TABLE #Data;
END;
GO