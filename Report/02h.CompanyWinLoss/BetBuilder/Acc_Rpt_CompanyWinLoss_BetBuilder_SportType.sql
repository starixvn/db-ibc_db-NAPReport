/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_CompanyWinLoss_BetBuilder_SportType
	@StartDate SMALLDATETIME
	,@EndDate SMALLDATETIME
AS
/*
	Created: 20200722@Roy
	Task : Get data for House Win Loss by Products - drill down Bet Builder: Product > Sport > Bettype
	DB: DBDW.bodb_dwrs

	Revisions:
		20200722@Roy: Incorporate New Basketball Sport for BetBuilder Product - NAP Report (#138082)

	Param's Explanation:
	
	Script: EXEC Acc_Rpt_CompanyWinLoss_BetBuilder_SportType @StartDate='2020-06-30 00:00:00',@EndDate='2020-06-30 00:00:00'
*/
BEGIN
	
	---Create temp tables---
	CREATE TABLE #tmpSportMatches (
		MatchId INT
		,SportType INT
		,SportName NVARCHAR(50)
		)
	
	CREATE TABLE #tmpBetTypes (
		BetType INT
		)
	
	CREATE TABLE #tmpDepSuper (CustId INT)
	
	/*
		Define BetTypes of Bet Builder
		From: f_SportBetTypeMatrix_Sel
		To: #tmpBetTypes ( BetType )
	*/
	DECLARE @isTest BIT = dbo.f_CheckSPVersion(@@PROCID)
	
	INSERT INTO #tmpBetTypes
	SELECT DISTINCT BetType
	FROM dbo.f_SportBetTypeMatrix_Sel(1, 0, 0, 2, 'Bet Builder', '', @isTest)
	/*
		Define Matches of Bet Builder ( join with LEAGUE to get exactly SPORTTYPE )
		From: match, league, SportBettypeMatrix, sports
		To: #tmpSportMatches ( MatchId, SportType, SportName )
	*/
	INSERT INTO #tmpSportMatches
	SELECT m.MatchId
		,s.Sporttype
		,s.Sportname
	FROM match m WITH (NOLOCK)
		INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		INNER JOIN SportBettypeMatrix sm WITH (NOLOCK) ON l.sporttype = sm.SportType
		INNER JOIN sports s WITH (NOLOCK) ON l.sporttype = s.sporttype
	WHERE m.EventDate = @StartDate
		AND sm.SubProduct = 'Bet Builder'
	GROUP BY m.MatchId
		,s.Sporttype
		,s.Sportname
	OPTION (RECOMPILE)
	
	CREATE CLUSTERED INDEX [CIX_match] ON #tmpSportMatches( MatchId )
	/*
		Define Deposit Super user
		From: f_DepSuper_1
		To: #tmpDepSuper ( CustId )
	*/
	INSERT INTO #tmpDepSuper
	SELECT CustId
	FROM f_DepSuper_1('All')
	
	
	SELECT m.SportType AS GroupId
		,m.SportName AS GroupName
		,(CASE 
			WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL
				THEN 'CN88'
			WHEN dep.CustId IS NULL AND cn88.CustId IS NULL
				THEN 'Credit'
			ELSE 'Deposit'
		END) as RowName
		,SUM((winlost - actual_stake) * actualrate) as MemberWinLoss
		,SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinLoss
		,SUM((
				CASE 
					WHEN b.tpositiontaking = 1
						THEN 0
					ELSE (winlost - actual_stake) + b.scomm / (1 - b.tpositiontaking)
					END
				) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) * actualrate) AS ExtraPT
		,SUM(scomm * actualrate) AS Commission
		,SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost + scomm - ( CASE 
																					WHEN tpositiontaking = 1
																						THEN 0
																					ELSE winlost - actual_stake + b.scomm / (1 - b.tpositiontaking)
																					END
																				) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
				) * actualrate) AS RealIncome
		,SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - (CASE 
																			WHEN tpositiontaking = 1
																				THEN 0
																			ELSE (winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
																		END)
				) * virtualrate + ( scomm - ( CASE 
												WHEN tpositiontaking = 1
													THEN 0
												ELSE b.scomm / (1 - b.tpositiontaking)
												END
											) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
				) * actualrate * ( CASE 
									WHEN virtualrate < actualrate
										THEN virtualrate / actualrate
									ELSE 1
								END )
			) as VirtualIncome
		,SUM(( winlost - actual_stake + awinlost + mwinlost + swinlost - ( CASE 
																			WHEN tpositiontaking = 1
																				THEN 0
																			ELSE (winlost - actual_stake) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)
																			END
																		) + ( CASE 
																			WHEN virtualrate < actualrate
																				THEN ( b.scomm - ( CASE 
																									WHEN tpositiontaking = 1
																										THEN 0
																									ELSE b.scomm / (1 - b.tpositiontaking)
																									END
																								) * ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0) )
																			ELSE 0
																			END )
				) * (actualrate - virtualrate)) VarianceIncome
		,SUM(CASE 
				WHEN tpositiontaking = 1
					THEN 0
				ELSE (1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * CASE 
						WHEN virtualrate > actualrate
							THEN virtualrate
						ELSE actualrate
						END
				END) AS RealTurnover
		,SUM(CASE 
				WHEN tpositiontaking = 1
					THEN 0
				ELSE (1 - b.tpositiontaking - ISNULL(CAST(b.epositiontaking AS DECIMAL(9, 8)), 0)) * ABS(b.stake) * virtualrate
				END) AS VirtualTurnover
	FROM bettrans AS b WITH (NOLOCK)
		INNER JOIN #tmpBetTypes AS bt ON b.BetType = bt.BetType
		INNER JOIN #tmpSportMatches AS m WITH (NOLOCK) ON b.MatchId = m.MatchId
		LEFT JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
		LEFT JOIN #tmpDepSuper AS dep ON b.srecommend = dep.CustId
	WHERE b.winlostdate = @StartDate
		AND b.ruben = 1
		AND b.statusID IN ( 111, 112, 113 )
	GROUP BY m.SportType
		,m.SportName
		,(CASE 
				WHEN dep.CustId IS NULL AND cn88.CustId IS NOT NULL
					THEN 'CN88'
				WHEN dep.CustId IS NULL AND cn88.CustId IS NULL
					THEN 'Credit'
				ELSE 'Deposit'
		END)
	ORDER BY GroupName
		,RowName
	OPTION (RECOMPILE)
	
	DROP TABLE #tmpSportMatches
	DROP TABLE #tmpBetTypes
	DROP TABLE #tmpDepSuper
END