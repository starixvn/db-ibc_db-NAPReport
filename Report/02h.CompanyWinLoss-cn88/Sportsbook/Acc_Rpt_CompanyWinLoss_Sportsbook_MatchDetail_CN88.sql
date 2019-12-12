/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Sportsbook_MatchDetail_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @SportType    SMALLINT      = 1
   , @BetType      INT           = 1
   , @IsHedge      INT           = 2
   , @IsLive       INT           = 2
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
    BEGIN -- #Match
	   CREATE TABLE #Match(
		   MatchId      INT
		 , MatchCode    NVARCHAR(50)
		 , IsNeutral    BIT
		 , EventDate    DATETIME
		 , LeagueId     INT
		 , HomeId       INT
		 , AwayId       INT);
	   INSERT INTO #Match
			SELECT m.MatchId
				, m.MatchCode
				, m.IsNeutral
				, m.EventDate
				, m.LeagueId
				, m.HomeId
				, m.AwayId
			FROM Match AS m WITH (NOLOCK)
			WHERE m.sporttype = @SportType
				 AND EventDate = @StartDate
				 AND
					(@IsHedge = 2
					 OR @IsHedge = 1
					 AND m.MatchCode LIKE '%hedge%'
					 OR @IsHedge = 0
					 AND m.MatchCode NOT LIKE '%hedge%');
    END;
    BEGIN -- #Data	
	   CREATE TABLE #Data(
		   MatchId            INT
		 , MatchCode          VARCHAR(100)
		 , IsNeutral          BIT
		 , EventDate          DATETIME
		 , LeagueId           INT
		 , HomeId             INT
		 , AwayId             INT
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
    BEGIN -- INSERT INTO #Data
	   INSERT INTO #Data
			SELECT b.MatchId
				, m.MatchCode
				, ISNULL(m.IsNeutral, 0) AS IsNeutral
				, m.EventDate
				, m.LeagueId
				, m.HomeId
				, m.AwayId
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
			FROM bettrans AS b WITH (nolock)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
			WHERE b.winlostdate = @StartDate
				 AND b.BetType = @BetType
				 AND
					(@IsLive > 1
					 OR b.liveindicator = @IsLive)
				 AND b.ruben = 1
				 AND statusID IN(111, 112, 113)
			GROUP BY b.MatchId
				  , m.MatchCode
				  , m.IsNeutral
				  , m.HomeId
				  , m.AwayId
				  , m.EventDate
				  , m.LeagueId OPTION(RECOMPILE);
    END;

    BEGIN -- Query
	   SELECT d.MatchId
		   , d.MatchCode
		   , d.IsNeutral
		   , d.EventDate
		   , @SportType AS SportType
		   , d.LeagueId
		   , d.HomeId
		   , d.AwayId
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
	   ORDER BY LeagueId
			, MatchCode;
    END;

    DROP TABLE #Match;
    DROP TABLE #Data;
END;
GO