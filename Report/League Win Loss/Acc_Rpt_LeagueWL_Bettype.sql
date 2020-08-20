/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_LeagueWL_Bettype @StartDate SMALLDATETIME,
											 @EndDate SMALLDATETIME,
											 @SportBettype VARCHAR(MAX),
											 @MatchID INT,
											 @LiveIndicator BIT,
											 @IsNoDraw BIT = 0
AS
/*
	Created: Ned.Le@20200424
	Task: View all measures by bettypes
	DB: DBACC.bodb02

	Revisions:
		- 20200424@Ned.Le: NAP Report - Adjustment for League Win Loss (#132846)
		- 20200520@Ned.Le: NAP Report - Enhancement for League Win Loss (#134439)
		- 20200626@Ned.Le: NAP Report - Enhancement for searching a league info on Punter Analysis and League Win Loss Report (#136277)
		- 20200814@Jaden.Tang: NAP Report - Enhancement for League Win Loss (#138955) - New dimensions
								+ Moved one level down (drill down: League > Match > **Bet Type** > ... )

	Param's Explanation:
		- @StartDate: The start date of data to view on report
		- @EndDate: The end date of data to view on report
		- @SportBettype: List of Sporttypes and Bettypes that correspond to each other
		                 Example '1_1,2_1' --> 'Soccer_Handicap,Basketball_Handicap'
		- @MatchID: The specific match to view on report
		- @IsNoDraw: To get the draw tickets to report or not
		             0 - Get draw ticktes to report
					 1 - No get draw ticktes to report

	Example:
		EXEC bodb02.dbo.Acc_Rpt_LeagueWL_Bettype @StartDate='20200620', @EndDate='20200706', 
			@MatchID=36510273, @LiveIndicator=1, @IsNoDraw=0
			, @SportBettype='1_301,1_302,1_303,1_304,1_15,1_125,1_453,1_476,1_459,1_466,1_205,1_201,1_138,1_404,1_464,1_485,1_215,1_188,1_427,1_456,1_457,1_478,1_203,1_471,1_487,1_494,1_30,1_414,1_151,1_410,1_191,1_411,1_182,1_181,1_207,1_489,1_127,1_7,1_204,1_200,1_136,1_403,1_463,1_484,1_213,1_209,1_492,1_180,1_12,1_8,1_211,1_143,1_202,1_474,1_126,1_426,1_177,1_430,1_146,1_433,1_472,1_495,1_405,1_186,1_431,1_185,1_432,1_490,1_17,1_183,1_184,1_428,1_18,1_178,1_28,1_475,1_458,1_465,1_447,1_122,1_381,1_388,1_386,1_196,1_139,1_402,1_462,1_483,1_214,1_198,1_132,1_421,1_148,1_437,1_134,1_439,1_150,1_441,1_189,1_434,1_190,1_435,1_145,1_445,1_451,1_417,1_418,1_26,1_13,1_477,1_496,1_497,1_194,1_470,1_486,1_4,1_413,1_24,1_454,1_449,1_25,1_123,1_804,1_129,1_412,1_179,1_429,1_187,1_162,1_409,1_130,1_161,1_407,1_159,1_406,1_167,1_165,1_174,1_166,1_399,1_398,1_164,1_396,1_395,1_400,1_397,1_173,1_206,1_488,1_806,1_424,1_192,1_193,1_14,1_422,1_423,1_176,1_5,1_124,1_216,1_217,1_801,1_152,1_416,1_467,1_493,1_1,1_140,1_452,1_442,1_142,1_444,1_141,1_443,1_446,1_121,1_382,1_389,1_387,1_195,1_137,1_401,1_461,1_482,1_212,1_197,1_131,1_420,1_147,1_436,1_133,1_438,1_149,1_440,1_16,1_128,1_208,1_491,1_448,1_175,1_221,1_225,1_222,1_22,1_160,1_169,1_803,1_450,1_2,1_157,1_10,1_3,1_135,1_385,1_384,1_376,1_392,1_391,1_394,1_393,1_390,1_383,1_210,1_172,1_415,1_144,1_163,1_468,1_469,1_38,1_170,1_481,1_479,1_455,1_805,1_425,1_27,1_473,1_199,1_6,1_223,1_224,1_226,1_227,1_419,1_460,1_168,1_171,1_408'
*/

BEGIN

	SET NOCOUNT ON

	BEGIN /*split the array @SportBettype into a temp table*/
		CREATE TABLE #tmpSportBettypeMatrix (SportType SMALLINT,
											 BetType SMALLINT)

		;WITH CTE_SportBettypeMatrix AS (
			SELECT CAST(LEFT(val, CHARINDEX('_', val)-1) AS INT) AS SportType,
				   CAST(SUBSTRING(val, CHARINDEX('_', val)+1, 6) AS INT) AS BetType
			FROM bodb02.dbo.strSplit_str(@SportBettype, ',')
			WHERE LEN(val) > 0
		)
		INSERT INTO #tmpSportBettypeMatrix (SportType, BetType)
		SELECT cte.SportType, cte.BetType
		FROM CTE_SportBettypeMatrix cte
	END

	DECLARE @SportType INT
    BEGIN /*get sport type from @MatchID*/
        SELECT @SportType = sporttype 
        FROM (
            SELECT l.sporttype
            FROM bodb02.dbo.league l WITH (NOLOCK)
            INNER JOIN bodb02.dbo.match m WITH (NOLOCK)
                ON l.leagueid = m.leagueid
            WHERE m.matchid = @MatchID AND m.eventdate = @StartDate
            UNION ALL 
            SELECT l.sporttype
            FROM bodb02.dbo.league l WITH (NOLOCK)
            INNER JOIN bodb02.dbo.outright o WITH (NOLOCK)
                ON l.leagueid = o.leagueid
            WHERE o.orid = @MatchID AND o.eventdate = @StartDate
        ) t
        OPTION (RECOMPILE)
    END

	BEGIN /*get a list of Supers by site type*/
		CREATE TABLE #super (SuperID   INT PRIMARY KEY, 
                             SiteType  CHAR(7))

		INSERT INTO #super
			SELECT DISTINCT 
				   s.srecommend AS SuperID,
				   CASE WHEN cn88.CustId IS NOT NULL THEN 'CN88'
				 		WHEN dep.custid  IS NOT NULL THEN 'Deposit'
						ELSE 'Credit' END AS SiteType
			FROM bodb02..Customer AS s WITH(NOLOCK)
			LEFT JOIN bodb02..Dep_CustSuper AS dep WITH(NOLOCK) 
				ON s.srecommend = dep.CustId
			LEFT JOIN bodb02..CS_CustSuper cn88 WITH(NOLOCK) 
				ON s.srecommend = cn88.CustId
			WHERE s.RoleID = 2 -- always get Site info from Agent
	END

	BEGIN /*build staging data by agent-super-bettype dimension*/
		CREATE TABLE #agentSuperBettype (AgentID				INT,
							   			 SuperID				INT,
							   			 Bettype				INT,
							   			 MemberWinLoss			MONEY,
							   			 SMAWinLoss				MONEY,
							   			 ExtraPT				MONEY,
							   			 Commission				MONEY,
							   			 RealIncome				MONEY,
							   			 VirtualIncome			MONEY,
							   			 VarianceIncome			MONEY,
							   			 RealTurnover			MONEY,
							   			 VirtualTurnover		MONEY,
							   			 SummaryLineIdentifier  TINYINT)
		
		--+ Soccer, Other Sports
		INSERT INTO #agentSuperBettype (AgentID,
							  			SuperID,
							  			Bettype,
							  			MemberWinLoss,
							  			SMAWinLoss,
							  			ExtraPT,
							  			Commission,
							  			RealIncome,
							  			VirtualIncome,
							  			VarianceIncome,
							  			RealTurnover,
							  			VirtualTurnover)
			SELECT  sd.recommend  AS AgentID,
					sd.srecommend AS SuperID,
					sd.BetType 	  AS BetType,
					SUM((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
					SUM((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
					SUM((CASE WHEN sd.tpositiontaking = 1 THEN 0
							ELSE (sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking) END) 
						* ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) 
						* sd.actualrate
						) AS ExtraPT,
					SUM(sd.scomm * sd.actualrate) AS Commission,
					SUM((
							sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost + sd.scomm 
							- CASE WHEN sd.tpositiontaking = 1 THEN 0
								ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking) END 
							* ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
						) 
						* sd.actualrate
						) AS RealIncome,
					SUM((
							sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost 
							- CASE WHEN sd.tpositiontaking = 1 THEN 0
								ELSE (sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) END
						) * sd.virtualrate 
						+ (
							sd.scomm 
							- CASE WHEN sd.tpositiontaking = 1 THEN 0
								ELSE sd.scomm / (1 - sd.tpositiontaking) END 
							* ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
						) 
						* sd.actualrate 
						* (CASE WHEN sd.virtualrate < sd.actualrate THEN sd.virtualrate / sd.actualrate ELSE 1 END)
						) AS VirtualIncome,
					SUM((
							sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost -
							CASE WHEN sd.tpositiontaking = 1 THEN 0
								ELSE(sd.winlost - sd.actual_stake) * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
							END 
							+ CASE WHEN sd.virtualrate < sd.actualrate 
									THEN (sd.scomm - 
											(CASE WHEN tpositiontaking = 1 THEN 0 ELSE sd.scomm / (1 - sd.tpositiontaking) END) 
											* ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
								ELSE 0
							END
						) 
						* (sd.actualrate - sd.virtualrate)) AS VarianceIncome,
					SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
							ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
								* ABS(sd.stake)
								* CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
								* CASE WHEN @IsNoDraw = 1 THEN CASE WHEN  (sd.bettype < 999 
																				OR sd.bettype BETWEEN 1301 AND 1399 
																				OR sd.bettype BETWEEN 9001 AND 9399) 
																			AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914)
																			AND sd.bettype NOT BETWEEN 81 AND 120
																			AND ABS(sd.modds) = 0.25
																			AND sd.statusID IN (112, 113)
																	THEN 0.5
																	ELSE 1 END
										ELSE 1 END
						END) AS RealTurnover, 
					SUM(CASE WHEN sd.tpositiontaking = 1 THEN 0
							ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
								* ABS(sd.stake)
								* CASE WHEN @IsNoDraw = 1 THEN CASE WHEN 	(sd.bettype < 999 
																				OR sd.bettype BETWEEN 1301 AND 1399 
																				OR sd.bettype BETWEEN 9001 AND 9399) 
																			AND sd.bettype NOT IN (29, 38, 911, 912, 913, 914 )
																			AND sd.bettype NOT BETWEEN 81 AND 120
																			AND ABS(sd.modds) = 0.25
																			AND sd.statusID IN (112, 113)
																	THEN 0.5
																	ELSE 1 END
										ELSE 1 END
								* sd.virtualrate
						END) AS VirtualTurnover
			FROM bodb02.dbo.bettrans sd (NOLOCK)
			INNER JOIN #tmpSportBettypeMatrix mtrix
				ON mtrix.BetType = sd.bettype AND mtrix.SportType = @SportType
			WHERE sd.winlostdate = @StartDate
				AND sd.matchid = @MatchID
				AND sd.liveindicator = @LiveIndicator
				AND sd.ruben = 1
				AND sd.statusID IN (111, 112, 113)
				AND sd.currency NOT IN (20, 27, 28)
				AND (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND sd.statusID NOT IN (111)))
			GROUP BY sd.recommend, sd.srecommend, sd.BetType
			OPTION (RECOMPILE)
	
        --+ RM summary
        INSERT INTO #agentSuperBettype (SummaryLineIdentifier,
                              			MemberWinLoss,
                              			SMAWinLoss,
                              			ExtraPT,
                              			Commission,
                              			RealIncome,
                              			VirtualIncome,
                              			VarianceIncome,
                              			RealTurnover,
                              			VirtualTurnover)
            SELECT  CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 1 -- dummy for 'Soccer 8RM'
                         WHEN @SportType > 1 AND t.AgentId = 52466   THEN 2 -- dummy for 'Other Sports 8RM'
                         WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 3 -- dummy for 'Soccer BARM'
                         WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 4 -- dummy for 'Other Sports BARM'
                         ELSE 0 END AS SummaryLineIdentifier,
                    - SUM(MemberWinLoss) AS MemberWinLoss,
                    - SUM(SMAWinLoss) AS SMAWinLoss,
                    SUM(ExtraPT) AS ExtraPT,
                    SUM(Commission) AS Commission,
                    - SUM(RealIncome) AS RealIncome,
                    - SUM(VirtualIncome) AS VirtualIncome,
                    - SUM(VarianceIncome) AS VarianceIncome,
                    SUM(RealTurnover) AS RealTurnover, 
                    SUM(VirtualTurnover) AS VirtualTurnover
            FROM #agentSuperBettype t
            WHERE t.AgentId IN (52466, 5707545)
            GROUP BY CASE WHEN @SportType = 1 AND t.AgentId = 52466   THEN 1
                          WHEN @SportType > 1 AND t.AgentId = 52466   THEN 2
                          WHEN @SportType = 1 AND t.AgentId = 5707545 THEN 3
                          WHEN @SportType > 1 AND t.AgentId = 5707545 THEN 4
                          ELSE 0 END
	END

	/*final aggregation by bet type and site types, display result*/
	SELECT  Bettype AS BetTypeID,
			MAX(bt.typenamee) AS BetTypeName,
			CASE WHEN t.SummaryLineIdentifier = 1 THEN 'Soccer 8RM'
				 WHEN t.SummaryLineIdentifier = 2 THEN 'Other Sports 8RM'
				 WHEN t.SummaryLineIdentifier = 3 THEN 'Soccer BARM'
				 WHEN t.SummaryLineIdentifier = 4 THEN 'Other Sports BARM'
				 ELSE super.SiteType
			END AS SiteType,
		    SUM(MemberWinLoss) AS MemberWinLoss,
            SUM(SMAWinLoss) AS SMAWinLoss,
            - SUM(ExtraPT) AS ExtraPT,
            SUM(Commission) AS Commission,
            SUM(RealIncome) AS RealIncome,
            SUM(VirtualIncome) AS VirtualIncome,
            SUM(VarianceIncome) AS VarianceIncome,
            SUM(RealTurnover) AS RealTurnover, 
            SUM(VirtualTurnover) AS VirtualTurnover
	FROM #agentSuperBettype t
	LEFT JOIN bodb02.dbo.bettype bt WITH (NOLOCK)
		ON t.Bettype = bt.typeid
	LEFT JOIN #super AS super
		ON t.SuperID = super.SuperID
	GROUP BY Bettype, t.SummaryLineIdentifier
			,CASE WHEN t.SummaryLineIdentifier = 1 THEN 'Soccer 8RM'
				  WHEN t.SummaryLineIdentifier = 2 THEN 'Other Sports 8RM'
				  WHEN t.SummaryLineIdentifier = 3 THEN 'Soccer BARM'
				  WHEN t.SummaryLineIdentifier = 4 THEN 'Other Sports BARM'
				  ELSE super.SiteType
			 END
	ORDER BY CASE WHEN BetType = 1		THEN 1		--Handicap
				  WHEN BetType = 301	THEN 2		--% Handicap
				  WHEN BetType = 3		THEN 3		--Over/Under
				  WHEN BetType = 302	THEN 4		--% Over/Under
				  WHEN BetType = 7		THEN 5		--1st Half Handicap
				  WHEN BetType = 303	THEN 6		--1H % Handicap
				  WHEN BetType = 8		THEN 7		--1st Half Over/Under
				  WHEN BetType = 304	THEN 8		--1H % Over/Under
				  WHEN BetType = 2		THEN 9		--Odd/Even
				  WHEN BetType = 5		THEN 10		--1X2
				  WHEN BetType = 4		THEN 11		--Correct Score
				  WHEN BetType = 6		THEN 12		--Total Goal
				  WHEN BetType = 10		THEN 13		--Outright
				  ELSE 
				  	CASE WHEN t.SummaryLineIdentifier > 0 THEN 99 ELSE 14 END
			 END -- first priority bet type group
			 , BetTypeName --then order by name
			 , 3 ASC -- then order "SiteType" NULL first
			 , t.SummaryLineIdentifier

	DROP TABLE #agentSuperBettype
END
GO
