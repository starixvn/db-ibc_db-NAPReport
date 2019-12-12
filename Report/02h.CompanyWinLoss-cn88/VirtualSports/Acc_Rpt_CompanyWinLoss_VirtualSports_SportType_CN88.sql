/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_VirtualSports_SportType_CN88
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
    BEGIN --#SportBetType     
	   DECLARE @isTest    BIT = 0;
	   SELECT @isTest = dbo.f_CheckSPVersion
			(@@PROCID);
	   CREATE TABLE #SportBetType(
		   BetType      INT
		 , EventType    INT);
	   INSERT INTO #SportBetType
			SELECT s.BetType
				, s.EventType
			FROM dbo.f_SportBetTypeMatrix_Sel
				(5, 0, 0, 2, '', '', @isTest) AS s
			WHERE s.SubProduct = '';
    END;

    BEGIN -- #Data
	   CREATE TABLE #Data(
		   SportType        INT
		 , MemberWinLoss    MONEY
		 , SMAWinLoss       MONEY
		 , ExtraPT          MONEY
		 , Commission       MONEY
		 , RealIncome       MONEY
		 , RealTurnover     MONEY);
    END;
    BEGIN -- Virtual Soccer
	   INSERT INTO #Data
			SELECT m.sporttype
				, SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
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
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * b.stake * CASE
																			  WHEN virtualrate > actualrate
																			  THEN virtualrate
																			  ELSE actualrate
																		   END
					 END) AS RealTurnover
			FROM bettrans AS b WITH (NOLOCK)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN match AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
			    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			WHERE b.winlostdate = @StartDate
				 AND sb.EventType = 1
				 AND b.MatchId > 0
				 AND b.ruben = 1
				 AND b.statusID IN(111, 112, 113)
			GROUP BY m.sporttype;
    END;
    BEGIN -- Virtual HR
	   INSERT INTO #Data
			SELECT r.SportType AS SportType
				, SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
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
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(b.epositiontaking, 0)) * b.stake * CASE
																			  WHEN virtualrate > actualrate
																			  THEN virtualrate
																			  ELSE actualrate
																		   END
					 END) AS RealTurnover
			FROM bettrans AS b WITH (NOLOCK)
				INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN VSRaceInfo AS r WITH (NOLOCK) ON b.MatchId = r.EventId
			    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			WHERE b.winlostdate = @StartDate
				 AND sb.EventType = 3
				 AND b.MatchId > 0
				 AND b.ruben = 1
				 AND b.statusID IN(111, 112, 113)
			GROUP BY r.sporttype;
    END;
    BEGIN -- Query
	   SELECT s.SportType AS GroupId
		   , s.SportName AS GroupName
		   , d.MemberWinLoss AS MemberWinLoss
		   , d.SMAWinLoss AS SMAWinLoss
		   , -d.ExtraPT AS HeadlineIncome
		   , d.Commission AS Commission
		   , d.RealIncome AS RealIncome
		   , d.RealTurnover AS RealTurnover
	   FROM #Data AS d
		  INNER JOIN Sports AS s WITH (NOLOCK) ON d.SportType = s.SportType
	   ORDER BY GroupName;
    END;

    DROP TABLE #SportBetType;
    DROP TABLE #Data;
END;
GO