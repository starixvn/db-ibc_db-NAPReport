/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Soccer_Major_Minor_LiveStatus_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
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
    BEGIN -- #SportBetType	
	   DECLARE @isTest    BIT = 0;
	   SELECT @isTest = dbo.f_CheckSPVersion
			(@@PROCID);
	   CREATE TABLE #SportBetType(
		   BetType    INT
		 , IsMajor    BIT);
	   INSERT INTO #SportBetType
			SELECT BetType
				, 0
			FROM bodb02.dbo.f_SportBetTypeMatrix_Sel
				(1, 1, 0, 2, '', '', @isTest)
			WHERE SubProduct = ''
				 AND EventType IN(1, 2);

	   UPDATE #SportBetType
			SET
			    IsMajor = 1
	   WHERE BetType IN(1, 2, 3, 5, 6, 7, 8, 12, 15, 24, 25, 28, 121, 122, 123, 126, 151, 301, 302, 303, 304);
    END;

    BEGIN -- #Match
	   CREATE TABLE #Match(
		   MatchId      INT
		 , MatchCode    NVARCHAR(50)
		 , type         VARCHAR(10)
		 , PRIMARY KEY(MatchId, type));
	   INSERT INTO #Match
			SELECT DISTINCT
				  m.MatchId
				, m.MatchCode
				, m.type
			FROM
				(
				    SELECT MatchId
					    , LeagueId
					    , MatchCode
					    , 'match' AS type
				    FROM Match WITH (NOLOCK)
				    WHERE EventDate = @StartDate
				    UNION ALL
				    SELECT orid
					    , LeagueId
					    , MatchCode
					    , 'outright' AS type
				    FROM outright WITH (NOLOCK)
				    WHERE EventDate = @StartDate
				) AS m
			    INNER JOIN league AS l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
			WHERE l.sporttype = 1;
    END;
    BEGIN -- #Data
	   CREATE TABLE #tmp_Data(
		   srecommend         INT
		 , bettype            INT
		 , liveindicator      BIT
		 , MemberWinLoss      MONEY
		 , SMAWinLoss         MONEY
		 , ExtraPT            MONEY
		 , Commission         MONEY
		 , RealIncome         MONEY
		 , VirtualIncome      MONEY
		 , VarianceIncome     MONEY
		 , RealTurnover       MONEY
		 , VirtualTurnover    MONEY);
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
    BEGIN -- Major AND Minor
	   INSERT INTO #tmp_Data
			SELECT srecommend
				, bettype
				, liveindicator
				, SUM((winlost - actual_stake) * actualrate) AS MemberWinLoss
				, SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
				, SUM(CASE
						WHEN b.tpositiontaking = 1
						THEN 0
						ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
					 END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT
				, SUM(scomm * actualrate) AS Commission
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - CASE
																			  WHEN tpositiontaking = 1
																			  THEN 0
																			  ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																		   END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate) AS RealIncome
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	    WHEN tpositiontaking = 1
																	    THEN 0
																	    ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
																	END) * virtualrate + (scomm - CASE
																							    WHEN tpositiontaking = 1
																							    THEN 0
																							    ELSE b.scomm / (1 - b.tpositiontaking)
																							END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * actualrate * CASE
																																  WHEN virtualrate < actualrate
																																  THEN virtualrate / actualrate
																																  ELSE 1
																															   END) AS VirtualIncome
				, SUM((winlost - actual_stake + awinlost + mwinlost + swinlost - CASE
																	    WHEN tpositiontaking = 1
																	    THEN 0
																	    ELSE(winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
																	END + CASE
																			WHEN virtualrate < actualrate
																			THEN b.scomm - CASE
																						    WHEN tpositiontaking = 1
																						    THEN 0
																						    ELSE b.scomm / (1 - b.tpositiontaking)
																						END * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
																			ELSE 0
																		 END) * (actualrate - virtualrate)) AS VarianceIncome
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE
																				  WHEN virtualrate > actualrate
																				  THEN virtualrate
																				  ELSE actualrate
																			   END
					 END) AS RealTurnover
				, SUM(CASE
						WHEN tpositiontaking = 1
						THEN 0
						ELSE(1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
					 END) AS VirtualTurnover
			FROM bettrans AS b WITH (NOLOCK)
			    INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			    INNER JOIN #Match AS m ON b.MatchId = m.MatchId
			WHERE b.winlostdate = @StartDate
				 AND m.type = CASE
							   WHEN b.BetType = 10
							   THEN 'outright'
							   ELSE 'match'
						    END
				 AND b.ruben = 1
				 AND b.statusID IN(111, 112, 113)
			GROUP BY srecommend
				  , bettype
				  , liveindicator OPTION(RECOMPILE);

	   INSERT INTO #Data
			SELECT sb.IsMajor AS GroupId
				, CASE
					 WHEN sb.IsMajor = 1
					 THEN 'Soccer-Major Bet Types'
					 ELSE 'Soccer-Minor Bet Types'
				  END
				, SUM(MemberWinLoss) AS MemberWinLoss
				, SUM(SMAWinLoss) AS SMAWinLoss
				, SUM(ExtraPT) AS ExtraPT
				, SUM(Commission) AS Commission
				, SUM(RealIncome) AS RealIncome
				, SUM(VirtualIncome) AS VirtualIncome
				, SUM(VarianceIncome) AS VarianceIncome
				, SUM(RealTurnover) AS RealTurnover
				, SUM(VirtualTurnover) AS VirtualTurnover
			FROM #tmp_Data AS b
			    INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
			WHERE @IsLive > 1
				 OR b.liveIndicator = @IsLive
			GROUP BY sb.IsMajor
				  , CASE
					   WHEN sb.IsMajor = 1
					   THEN 'Soccer-Major Bet Types'
					   ELSE 'Soccer-Minor Bet Types'
				    END;

	   IF @IsLive = 2
		  BEGIN
			 INSERT INTO #Data
				   SELECT b.liveindicator AS GroupId
					   , CASE b.liveindicator
						    WHEN 1
						    THEN 'Soccer Live'
						    ELSE 'Soccer Non-Live'
						END AS GroupName
					   , SUM(MemberWinLoss) AS MemberWinLoss
					   , SUM(SMAWinLoss) AS SMAWinLoss
					   , SUM(ExtraPT) AS ExtraPT
					   , SUM(Commission) AS Commission
					   , SUM(RealIncome) AS RealIncome
					   , SUM(VirtualIncome) AS VirtualIncome
					   , SUM(VarianceIncome) AS VarianceIncome
					   , SUM(RealTurnover) AS RealTurnover
					   , SUM(VirtualTurnover) AS VirtualTurnover
				   FROM #tmp_Data AS b
					  INNER JOIN #SportBetType AS sb ON sb.BetType = b.BetType
				   GROUP BY liveindicator
						, CASE liveindicator
							 WHEN 1
							 THEN 'Soccer Live'
							 ELSE 'Soccer Non-Live'
						  END;
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
	   ORDER BY GroupName ASC;
    END;

    DROP TABLE #SportBetType;
    DROP TABLE #Data;
    DROP TABLE #tmp_Data;
    DROP TABLE #Match;
END;
GO