/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE Acc_Rpt_Letstalk_MarginBySport_Lic
	@Winlostdate SMALLDATETIME,
	@BaseCurrency VARCHAR(10) = 'CNY'
AS
/*	
	Created: 20221206@Roy
	Task: temp SP for SB Performance By Sport Lic
	DB: DBACC.bodb02
	
	Revision:
		20221206@Roy: Email/Letstalk Reports - Incorporate Saba E-Sports PinGoal (#181261)
		
	Param Explanation:
		IsSaba = 0: Normal,
		IsSaba = 1: Saba Virtual Sports,
		IsSaba = 2: Saba PinGoal (Soccer, Basketball, E-Sports)		 
	   
*/
BEGIN	
	SET NOCOUNT ON 
	 
	------Get Sport Bettype Matrix------	
	CREATE TABLE  #Bettype (Bettype INT PRIMARY KEY)
	INSERT INTO #Bettype
	SELECT  Bettype FROM bodb02.dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', 0)
	WHERE  ProductID = 1 
			AND Bettype NOT BETWEEN 801 and 806 
			AND bettype NOT BETWEEN 901 and 904
			AND Bettype <> 38 
	 
	----- End get sport bettype  
	
	------Get Sporttype------	
	CREATE TABLE  #Sports (Sporttype INT, SportName VARCHAR(50), OrderId INT IDENTITY (1,1))
	INSERT INTO #Sports (Sporttype, SportName)	
	SELECT 	Sporttype, SportName
	FROM 	bodb02.dbo.Sports WITH (NOLOCK)
    WHERE 	Sporttype IN (1, 2, 5, 43, 50)	
	
	INSERT INTO #Sports (Sporttype, SportName)	
	SELECT 	0 AS Sporttype, 'Other Sports' AS SportName	 
	UNION  
	SELECT 	-29 AS Sporttype, 'Parlay' AS SportName	 
	 
	----- End get Sporttype  
	
	----- Get Saba League ---------
	CREATE TABLE #SabaVirtualSportsLeague (LeagueId INT, SabaType TINYINT)

	INSERT INTO #SabaVirtualSportsLeague
	SELECT  l.leagueid,
			CASE
				WHEN l.LeagueGroupId = 113 AND l.SportType = 1 THEN 2 --Saba Soccer PinGoal
				WHEN l.LeagueGroupId = 122 AND l.SportType = 2 THEN 2 --Saba Basketball PinGoal
				WHEN l.LeagueGroupId = 151 AND l.SportType = 43 THEN 2 --Saba E-Sports PinGoal
				--WHEN l.LeagueGroupId IN (42, 74, 108) AND l.SportType = 1 THEN -3 -- Saba Soccer
				--WHEN l.LeagueGroupId IN (42) AND l.SportType = 2 THEN -5 -- Saba Basketball
				--WHEN l.LeagueGroupId IN (42) AND l.SportType = 50 THEN -8 -- Saba Cricket
			ELSE 1  ---SabaType = 1: Saba Virtual Sports, SabaType = 2: Saba PinGoal
			END AS SabaType
	FROM 	dbo.League l WITH (NOLOCK)
	WHERE  	l.LeagueGroupID IN (41, 42, 74, 108, 113, 122, 151)
		
	----- End get Saba League 
		
	------Get Match ------	
	CREATE TABLE #Match
                     (MatchId   INT, 
                      type      VARCHAR(10), 
                      SportType INT, 
					  IsSaba	TINYINT
                      PRIMARY KEY(MatchId, type)
                     );
		INSERT INTO #Match
		SELECT DISTINCT 
			  m.MatchId, 
			  m.type, 
			  m.sporttype,
			  m.IsSaba
		FROM
		   (
				SELECT MatchId, 
					  'match' AS type,
					  m.Sporttype,
					  CASE WHEN l.LeagueId IS NULL THEN 0 ELSE SabaType END AS IsSaba
				FROM Match m WITH(NOLOCK)
				LEFT JOIN #SabaVirtualSportsLeague l 
					ON l.LeagueId = m.leagueid 
				WHERE EventDate = @WinlostDate
				UNION ALL
				SELECT orid,  
					  'outright' AS type,
					  ll.Sporttype,
					  CASE WHEN l.LeagueId IS NULL THEN 0 ELSE SabaType END AS IsSaba
				FROM outright o WITH(NOLOCK)
				INNER JOIN league ll WITH (NOLOCK) 
					ON ll.leagueID = o.LeagueId		
				LEFT JOIN #SabaVirtualSportsLeague l 
					ON l.LeagueId = o.leagueid 							
				WHERE o.EventDate = @WinlostDate
				UNION ALL
				SELECT 29 AS MatchId,
					   'Parlay' AS type,						   
					   -29 AS Sporttype,
						0 AS IsSaba						   
		   ) m           
	------End Get Match ------	
		

	------Get Base currency CNY ------- 
		CREATE TABLE #ExchangeOANDA(
				ExchangeDate    DATE
			  , ExchangeID      INT
			  , BaseCurrencyRate  FLOAT);

			INSERT INTO #ExchangeOANDA(ExchangeDate
								, ExchangeID
								, BaseCurrencyRate)
				 SELECT ExchangeDate
					 , ExchangeID
					 , BaseCurrencyRate
				 FROM bodb02.dbo.LA_f_ExchangeDailySel
					 (@Winlostdate, @Winlostdate, @BaseCurrency);
			
	------End of get Base currency CNY -------
	
	-------------- Get Charge Info -------------------
	
		----- Get Supers List -----
		CREATE TABLE #Supers (Custid INT, Site VARCHAR(20), PartyId INT)
				
		INSERT INTO #Supers (CustId, Site, PartyId)
		SELECT c.Custid, c.Site, ISNULL(p.PartyId,0) AS PartyId
		FROM dbo.Dep_CustSuper c WITH (NOLOCK) 	
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeName = c.site	
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.OldRefID = l.LicenseeID AND p.PartyType = 1  
		LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID AND pd.IsDeposit = 1 
		WHERE  c.Site NOT IN ('Saba789')
			AND c.currency <> 20 
			
		-- Get party list 
		DECLARE @PartyIds VARCHAR(MAX), @ProductCodes VARCHAR(MAX)
		
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(10), p.PartyId) 
		FROM (SELECT DISTINCT PartyId FROM #Supers) p 

		-- Get product list		
		SELECT @ProductCodes = 'SB,BA'

		-- Get charge rate
		CREATE TABLE #PartyChargeInfo (ChargeId INT, PartyId INT, Product3rdId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		
		INSERT INTO #PartyChargeInfo (ChargeId, PartyId, Product3rdId, FromDate, ToDate, Rate)					
		SELECT DISTINCT ci.ChargeId, ci.PartyId, ci.ProductId AS Product3rdId, ci.FromDate, ci.ToDate, ci.DI_Rate AS Rate 
		FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIds, @Winlostdate, @Winlostdate, @ProductCodes,'OA', 1) ci 
		WHERE ci.DI_Rate > 0
			AND ci.ChargeType = 1 
 
		
		CREATE TABLE #PartyChargeByCurrencyInfo (ChargeId INT, CurrencyId INT, Rate FLOAT)

		INSERT INTO #PartyChargeByCurrencyInfo (ChargeId, CurrencyId, Rate)		 
	    SELECT pc.ChargeId, pc.CurrencyId, pc.Rate
		FROM #PartyChargeInfo ci
			INNER JOIN bodb_Licensee.dbo.LA_ChargeRateByCurrency pc WITH (NOLOCK) ON ci.ChargeId = pc.ChargeId
		 
	---- End Get Charge Info ----	
	
	--------------------------------------------------------------------------------------------------------- 
		CREATE TABLE #wl 
		(	
			PartyID			INT,			
			Currency		INT,
			Product3rdId	INT,
			Sporttype  		SMALLINT, 			
			LiveIndicator	BIT,
			IsSaba 			TINYINT	,			
			TurnOver		MONEY,
			Winlost			MONEY,
			OddsSpreadAdj	MONEY,
			BAComm 			MONEY
		) 	 
		INSERT INTO #wl ( PartyID, Currency, Product3rdId, Sporttype, LiveIndicator, IsSaba, TurnOver, winlost, OddsSpreadAdj,BAComm)
		SELECT  s.PartyID, b.Currency, 
				CASE WHEN ba.TransID IS NOT NULL THEN 3 ELSE 0 END AS Product3rdId,
				CASE WHEN m.Sporttype IN (1, 2, 5, 43, 50, -29) THEN m.Sporttype ELSE 0 END AS Sporttype, 
				b.LiveIndicator,		
				m.IsSaba,		
				---Base currency
				SUM (   CASE WHEN b.StatusID = 111 THEN 0 ELSE 
						CASE WHEN ABS(modds) = 0.25 AND b.Bettype <> 29 THEN ABS(Stake) / 2 ELSE  ABS(Stake) END END						
						* CASE WHEN @BaseCurrency = '' THEN b.actualrate ELSE e.BaseCurrencyRate END
					)	 AS TurnOver,
				SUM(
						(ISNULL(winlost,0)-ISNULL(actual_stake,0)) 
						* CASE WHEN @BaseCurrency = '' THEN b.actualrate ELSE e.BaseCurrencyRate END	
					) AS winlost,
				SUM (CASE WHEN bettype = 999 THEN awinlost ELSE 0 END ) AS OddsSpreadAdj,
				SUM (Comm) AS BAComm 
 		FROM dbo.bettrans b WITH (NOLOCK)
		LEFT JOIN #ExchangeOANDA e ON e.ExchangeId = b.Currency		
		INNER JOIN #Supers s ON s.Custid = b.srecommend
		INNER JOIN #Match AS m 
			ON 	b.MatchId = m.MatchId
			AND m.type = CASE b.BetType WHEN 10 THEN 'outright'
										WHEN 29 THEN 'Parlay'
										ELSE 'Match'                           
                         END		
		LEFT JOIN bodb_Licensee.dbo.LicenseeBATransaction_Active ba WITH (NOLOCK)
			ON 	ba.TransID = b.TransID
		WHERE   b.Winlostdate = @WinlostDate
			AND b.statusid IN (111, 112, 113)		
			AND b.bettype < 19001
			AND b.MatchID >= 0
			AND b.Recommend NOT IN (52466,5707545)  --- Exclude 8RM, BARM			
			AND EXISTS (SELECT 1 FROM #Bettype bt WHERE bt.Bettype = b.Bettype)
		GROUP BY  
				s.PartyID, b.Currency, CASE WHEN ba.TransID IS NOT NULL THEN 1 ELSE 0 END,
				CASE WHEN m.Sporttype IN (1, 2, 5, 43, 50, -29) THEN m.Sporttype ELSE 0 END, 
				CASE WHEN ba.TransID IS NOT NULL THEN 3 ELSE 0 END,
				b.LiveIndicator, m.IsSaba
				 				   
		-----------------------------------------------------------------------------------------------
		----- Get Data -----
		SELECt  a.SportName, a.LiveIndicator, a.IsSaba, a.Turnover, - a.Margin as Margin, -a.HouseWinlost as HouseWinlost
		FROM  (
				SELECT	s.orderId, s.SportName, w.LiveIndicator, w.IsSaba, 
						SUM (w.TurnOver * ISNULL(lc.Rate, p.Rate)) AS TurnOver, 
						CASE 	WHEN SUM (w.TurnOver * ISNULL(lc.Rate, p.Rate)) = 0 
								THEN 0 
								ELSE SUM ((- w.winlost - w.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate) - w.OddsSpreadAdj - BAComm)/SUM (w.TurnOver * ISNULL(lc.Rate, p.Rate)) * 100 
								END AS Margin,
						SUM ((- w.winlost - w.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate) - w.OddsSpreadAdj - BAComm) AS HouseWinlost
				FROM 	#wl w 
				INNER JOIN #Sports s ON s.Sporttype = w.sporttype				
				LEFT JOIN #PartyChargeInfo p 
					ON 	p.PartyId = w.PartyId 
					AND p.Product3rdId = w.Product3rdId					
				LEFT JOIN #PartyChargeByCurrencyInfo lc 
					ON 	p.ChargeId = lc.ChargeId 
					AND w.Currency = lc.CurrencyId	
				GROUP BY s.orderId, s.SportName, w.LiveIndicator, w.IsSaba

				UNION 

				SELECT	0 AS orderId, 'All Sports' AS SportName, 2 AS LiveIndicator, w.IsSaba, 
						SUM (w.TurnOver * ISNULL(lc.Rate, p.Rate)) AS TurnOver, 
						CASE 	WHEN SUM (w.TurnOver * ISNULL(lc.Rate, p.Rate)) = 0 
								THEN 0 
								ELSE SUM ((- w.winlost - w.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate) - w.OddsSpreadAdj- BAComm)/SUM (w.TurnOver * ISNULL(lc.Rate, p.Rate)) * 100 
								END AS Margin,
						SUM ((- w.winlost - w.OddsSpreadAdj) * ISNULL(lc.Rate, p.Rate) - w.OddsSpreadAdj- BAComm) AS HouseWinlost
				FROM 	#wl w  
				LEFT JOIN #PartyChargeInfo p 
					ON 	p.PartyId = w.PartyId 
					AND p.Product3rdId = w.Product3rdId					
				LEFT JOIN #PartyChargeByCurrencyInfo lc 
					ON 	p.ChargeId = lc.ChargeId 
					AND w.Currency = lc.CurrencyId	
				GROUP BY w.IsSaba 
				HAVING  SUM (w.TurnOver) IS NOT NULL 
				) A
		ORDER BY A.OrderId

	DROP TABLE #Bettype
    DROP TABLE #Sports
	DROP TABLE #WL	
	DROP TABLE #Match
	DROP TABLE #Supers
	DROP TABLE #SabaVirtualSportsLeague 
	DROP TABLE #PartyChargeInfo
	DROP TABLE #PartyChargeByCurrencyInfo
	DROP TABLE #ExchangeOANDA
		
END
