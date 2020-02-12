/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_CompanyWinLoss_Products_CN88
	@StartDate    SMALLDATETIME
   , @EndDate      SMALLDATETIME
   , @Headline	  INT
AS
/*	
    Creator: Robert
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #116083]
	DB: DBACC/bodb02	
		
	Revisions:
		20190710@Robert: 	NAP Report - Implement new report to match with CN88's need [#116083]
		20200214@Cherry: Add filter by Headline Group (#127822)
	Explanation's Param:	
		@Headline = 0 : All, 
				  = 1 : TPG,
				  = 2 : XPG
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @EffectedDate    DATETIME = '2017-01-19'
		, @isTest          BIT      = 0;

    SELECT @isTest = dbo.f_CheckSPVersion
		 (@@PROCID);
    CREATE TABLE #SportBettype(
	    ProductID     INT
	  , Bettype       INT
	  , EventType     INT
	  , SubProduct    VARCHAR(500)
	  , RefTable      TINYINT
	  , CasinoType    TINYINT);
    INSERT INTO #SportBettype(ProductID
					   , Bettype
					   , EventType
					   , SubProduct
					   , RefTable
					   , CasinoType)
		 SELECT ProductID
			 , Bettype
			 , EventType
			 , SubProduct
			 , RefTable
			 , CasinoType
		 FROM dbo.f_SportBettypeMatrix_Sel
			 (0, 0, 0, 2, '', '', @isTest)
		 WHERE LEN(SubProduct) = 0
			  AND ProductID IN(1, 3, 5, 8, 27, 28); -- Sportsbook, Number Game, Virtual Sports, RNG Keno, Virtual Sports 2, Lottery
    CREATE TABLE #tmp_src(
	    srecommend                       INT
	  , bettype                          INT
	  , Sporttype                        INT
	  , winlost_actualrate               MONEY
	  , SMAWinloss                       MONEY
	  , commission_actualrate            MONEY
	  , HouseWinloss_actualrate          MONEY
	  , HouseWinloss_virtualrate         MONEY
	  , HouseWinloss_variance            MONEY
	  , grosscomm_actualrate             DECIMAL(19, 6)
	  , grosscomm_virtualrate            DECIMAL(19, 6)
	  , grosscomm_variance               DECIMAL(19, 6)
	  , ProductId                        INT
	  , CasinoType                       TINYINT
	  , turnover_actualrate              MONEY
	  , turnover_virtualrate             MONEY
	  , stake_actualrate                 MONEY
	  , stake_virtualrate                MONEY
	  , WinlossForExtraPT_actualrate     MONEY
	  , WinlossForExtraPT_virtualrate    MONEY);
    CREATE TABLE #src(
	    srecommend                       INT
	  , Sporttype                        INT
	  , winlost_actualrate               MONEY
	  , SMAWinloss                       MONEY
	  , commission_actualrate            MONEY
	  , HouseWinloss_actualrate          MONEY
	  , HouseWinloss_virtualrate         MONEY
	  , HouseWinloss_variance            MONEY
	  , grosscomm_actualrate             MONEY
	  , grosscomm_virtualrate            MONEY
	  , grosscomm_variance               MONEY
	  , ProductId                        INT
	  , CasinoType                       TINYINT
	  , turnover_actualrate              MONEY
	  , turnover_virtualrate             MONEY
	  , stake_actualrate                 MONEY
	  , stake_virtualrate                MONEY
	  , WinlossForExtraPT_actualrate     MONEY
	  , WinlossForExtraPT_virtualrate    MONEY);

    CREATE TABLE #Result(
	    DisplayOrder           INT
	  , ProductId              INT
	  , ProductName            NVARCHAR(50)
	  , winlost                MONEY
	  , Position               MONEY
	  , Commission             MONEY
	  , RealHouseWinloss       MONEY
	  , VirtualHouseWinloss    MONEY
	  , VarianceIncome         MONEY
	  , RealTurnover           MONEY
	  , VirtualTurnover        MONEY
	  , ExtraPT                MONEY
	  , NewExtraPT             MONEY);
---- Extra PT 
    CREATE TABLE #ExtraPT_Sel(
	    ProductID     INT
	  , Sporttype     INT
	  , SubProduct    VARCHAR(100)
	  , SuperID       INT
	  , ExtraPT       DECIMAL(9, 8));
    INSERT INTO #ExtraPT_Sel(ProductID
					  , Sporttype
					  , SubProduct
					  , SuperID
					  , ExtraPT)
		 SELECT ProductID
			 , SportType
			 , SubProduct
			 , SuperId
			 , SUM(ExtraPT) AS ExtraPT
		 FROM bodb02.dbo.Acc_GroupExtraPTSetting AS a WITH (NOLOCK)
		 WHERE @StartDate BETWEEN FromDate AND Todate
			  AND SuperId IN
						  (
							 SELECT CustId
							 FROM CS_CustSuper WITH (NOLOCK)
						  )
			  AND LEN(SubProduct) = 0
		 GROUP BY ProductID
			   , SportType
			   , SubProduct
			   , SuperId;

    CREATE TABLE #Match(
	    MatchId      INT
	  , sporttype    SMALLINT
	  , type         TINYINT);--, primary key(MatchId, type))
    INSERT INTO #Match
		 SELECT m.MatchId
			 , s.sporttype
			 , m.type
		 FROM
			 (
				SELECT MatchId
					, LeagueId
					, exrisk
					, MatchCode
					, 0 AS type --'match'
				FROM match WITH (NOLOCK)
				WHERE EventDate = @StartDate
				UNION ALL
				SELECT orid
					, LeagueId
					, 0
					, MatchCode
					, 1 AS type --'outright'
				FROM outright WITH (NOLOCK)
				WHERE EventDate = @StartDate
			 ) AS m
			INNER JOIN league AS l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
			INNER JOIN Sports AS s WITH (NOLOCK) ON l.sporttype = s.sporttype;
    CREATE CLUSTERED INDEX CIX_MatchID ON #Match(MatchID, Type);
    
    CREATE TABLE #tmp_XPG_SuperID(SuperID INT)
		  
	INSERT INTO #tmp_XPG_SuperID(SuperID)
	SELECT SuperId
	FROM bodb02.dbo.f_GetHeadlineNoPT()
	
--------------------------------------------------------------------------------
---1. Sportsbook only and outright
    INSERT INTO #tmp_src(srecommend
				   , bettype
				   , SportType
				   , winlost_actualrate
				   , SMAWinloss
				   , commission_actualrate
				   , HouseWinloss_actualrate
				   , HouseWinloss_virtualrate
				   , HouseWinloss_variance
				   , grosscomm_actualrate
				   , grosscomm_virtualrate
				   , grosscomm_variance
				   , ProductId
				   , turnover_actualrate
				   , turnover_virtualrate
				   , stake_actualrate
				   , stake_virtualrate
				   , WinlossForExtraPT_actualrate
				   , WinlossForExtraPT_virtualrate)
		 SELECT srecommend
			 , b.bettype
			 , CASE
				  WHEN m.sporttype = 44
				  THEN 44
				  WHEN m.Sporttype = 1
				  THEN 1
				  ELSE 2
			   END AS SportType
			 , SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
			 , SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss
			 , SUM(scomm * actualrate) AS commission_actualrate
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS HouseWinloss_actualrate
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate + scomm * CASE
																					   WHEN b.virtualrate < b.actualrate
																					   THEN b.virtualrate
																					   ELSE b.actualrate
																				    END) AS HouseWinloss_virtualrate
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + CASE
																	WHEN b.virtualrate < b.actualrate
																	THEN b.scomm
																	ELSE 0
																 END) * (actualrate - virtualrate)) AS HouseWinloss_variance
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE b.scomm / (1 - b.tpositiontaking)
				  END * b.actualrate) AS grosscomm_actualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE b.scomm / (1 - b.tpositiontaking)
				  END * CASE
						  WHEN b.virtualrate < b.actualrate
						  THEN b.virtualrate
						  ELSE b.actualrate
					   END) AS grosscomm_virtualrate
			 , SUM(CASE
					 WHEN b.virtualrate < b.actualrate
					 THEN CASE
							WHEN b.tpositiontaking = 1
							THEN 0
							ELSE b.scomm / (1 - b.tpositiontaking)
						 END
					 ELSE 0
				  END * (actualrate - virtualrate)) AS grosscomm_variance
			 , 1 AS ProductId
			 , SUM((1 - b.tpositiontaking) * ABS(stake) * CASE
													WHEN virtualrate > actualrate
													THEN virtualrate
													ELSE actualrate
												 END) AS turnover_actualrate
			 , SUM((1 - b.tpositiontaking) * ABS(stake) * virtualrate) AS turnover_virtualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE ABS(stake) * CASE
									   WHEN virtualrate > actualrate
									   THEN virtualrate
									   ELSE actualrate
								    END
				  END) AS stake_actualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE ABS(stake) * virtualrate
				  END) AS stake_virtualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * actualrate
				  END) AS WinlossForExtraPT_actualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * virtualrate
				  END) AS WinlossForExtraPT_virtualrate
		 FROM bettrans AS b WITH (NOLOCK)
			INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			INNER JOIN #Match AS m ON b.MatchId = m.MatchId
								 AND m.type = CASE
											   WHEN b.bettype = 10
											   THEN 1
											   ELSE 0
										    END
		 WHERE winlostdate = @StartDate
			  AND b.ruben = 1
			  AND b.statusID IN(111, 112, 113)
			  AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)	
		 GROUP BY srecommend
			   , b.bettype
			   , CASE
				    WHEN m.sporttype = 44
				    THEN 44
				    WHEN m.Sporttype = 1
				    THEN 1
				    ELSE 2
				END OPTION(RECOMPILE);

    DELETE #tmp_src
    WHERE bettype NOT IN(SELECT bettype
					FROM #SportBettype AS s
					WHERE s.productID = 1
						 AND s.EventType IN(1, 2));
------Soccer and Other Sports
    INSERT INTO #src(srecommend
			    , SportType
			    , ProductId
			    , winlost_actualrate
			    , SMAWinloss
			    , commission_actualrate
			    , HouseWinloss_actualrate
			    , HouseWinloss_virtualrate
			    , HouseWinloss_variance
			    , grosscomm_actualrate
			    , grosscomm_virtualrate
			    , grosscomm_variance
			    , turnover_actualrate
			    , turnover_virtualrate
			    , stake_actualrate
			    , stake_virtualrate
			    , WinlossForExtraPT_actualrate
			    , WinlossForExtraPT_virtualrate)
		 SELECT srecommend
			 , SportType
			 , ProductId
			 , SUM(winlost_actualrate)
			 , SUM(SMAWinloss)
			 , SUM(commission_actualrate)
			 , SUM(HouseWinloss_actualrate)
			 , SUM(HouseWinloss_virtualrate)
			 , SUM(HouseWinloss_variance)
			 , SUM(grosscomm_actualrate)
			 , SUM(grosscomm_virtualrate)
			 , SUM(grosscomm_variance)
			 , SUM(turnover_actualrate)
			 , SUM(turnover_virtualrate)
			 , SUM(stake_actualrate)
			 , SUM(stake_virtualrate)
			 , SUM(WinlossForExtraPT_actualrate)
			 , SUM(WinlossForExtraPT_virtualrate)
		 FROM #tmp_src
		 GROUP BY srecommend
			   , SportType
			   , ProductId;
---2. Not Sportsbook and not have detail table yet ; and special Sportsbook : Parlay
    INSERT INTO #src(srecommend
			    , SportType
			    , winlost_actualrate
			    , SMAWinloss
			    , commission_actualrate
			    , HouseWinloss_actualrate
			    , HouseWinloss_virtualrate
			    , HouseWinloss_variance
			    , grosscomm_actualrate
			    , grosscomm_virtualrate
			    , grosscomm_variance
			    , ProductId
			    , CasinoType
			    , turnover_actualrate
			    , turnover_virtualrate
			    , stake_actualrate
			    , stake_virtualrate
			    , WinlossForExtraPT_actualrate
			    , WinlossForExtraPT_virtualrate)
		 SELECT srecommend
			 , 0 AS SportType
			 , SUM((winlost - actual_stake) * actualrate) AS winlost_actualrate
			 , SUM((awinlost + mwinlost + swinlost) * actualrate) AS SMAWinloss
			 , SUM(scomm * actualrate) AS commission_actualrate
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) * actualrate) AS HouseWinloss_actualrate
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost) * virtualrate + scomm * CASE
																					   WHEN b.virtualrate < b.actualrate
																					   THEN b.virtualrate
																					   ELSE b.actualrate
																				    END) AS HouseWinloss_virtualrate
			 , SUM((winlost - actual_stake + awinlost + mwinlost + swinlost + CASE
																	WHEN b.virtualrate < b.actualrate
																	THEN b.scomm
																	ELSE 0
																 END) * (actualrate - virtualrate)) AS HouseWinloss_variance
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE b.scomm / (1 - b.tpositiontaking)
				  END * b.actualrate) AS grosscomm_actualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE b.scomm / (1 - b.tpositiontaking)
				  END * CASE
						  WHEN b.virtualrate < b.actualrate
						  THEN b.virtualrate
						  ELSE b.actualrate
					   END) AS grosscomm_virtualrate
			 , SUM(CASE
					 WHEN b.virtualrate < b.actualrate
					 THEN CASE
							WHEN b.tpositiontaking = 1
							THEN 0
							ELSE b.scomm / (1 - b.tpositiontaking)
						 END
					 ELSE 0
				  END * (actualrate - virtualrate)) AS grosscomm_variance
			 , CASE
				  WHEN s.EventType = 0
					  AND ProductID = 1
				  THEN-3
				  ELSE s.ProductID
			   END AS ProductID
			 , s.CasinoType
			 , SUM((1 - b.tpositiontaking) * CASE
										  WHEN s.productID = 1
										  THEN ABS(stake)
										  ELSE stake
									   END * CASE
											   WHEN virtualrate > actualrate
											   THEN virtualrate
											   ELSE actualrate
										    END) AS turnover_actualrate
			 , SUM((1 - b.tpositiontaking) * CASE
										  WHEN s.productID = 1
										  THEN ABS(stake)
										  ELSE stake
									   END * virtualrate) AS turnover_virtualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN s.productID = 1
							THEN ABS(stake)
							ELSE stake
						 END * CASE
								 WHEN virtualrate > actualrate
								 THEN virtualrate
								 ELSE actualrate
							  END
				  END) AS stake_actualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE CASE
							WHEN s.productID = 1
							THEN ABS(stake)
							ELSE stake
						 END * virtualrate
				  END) AS stake_virtualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * actualrate
				  END) AS WinlossForExtraPT_actualrate
			 , SUM(CASE
					 WHEN b.tpositiontaking = 1
					 THEN 0
					 ELSE(winlost - actual_stake) * virtualrate
				  END) AS WinlossForExtraPT_virtualrate
		 FROM bettrans AS b WITH (NOLOCK)
			INNER JOIN CS_CustSuper AS cn88 WITH (NOLOCK) ON b.srecommend = cn88.CustId
			INNER JOIN #SportBettype AS s ON b.bettype = s.bettype
		 WHERE winlostdate = @StartDate
			  AND b.statusID IN(111, 112, 113)
			  AND b.ruben = 1
			  AND
				 (s.productID <> 1
				  AND s.RefTable NOT IN(1, 2)
				  OR s.productID = 1
				  AND s.EventType = 0)
			  AND (@Headline = 0
					OR (@Headline = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					OR (@Headline = 2 AND EXISTS (SELECT TOP 1 1 FROM #tmp_XPG_SuperID s WHERE b.srecommend = s.SuperID))
					)	
		 GROUP BY srecommend
			   , CASE
				    WHEN s.EventType = 0
					    AND ProductID = 1
				    THEN-3
				    ELSE s.ProductID
				END
			   , s.CasinoType;
-------------Insert to Result table to get data----------
-----1. Soccer and Others
    INSERT INTO #Result(ProductId
				  , winlost
				  , Position
				  , Commission
				  , RealHouseWinloss
				  , VirtualHouseWinloss
				  , VarianceIncome
				  , RealTurnover
				  , VirtualTurnover
				  , ExtraPT
				  , NewExtraPT)
		 SELECT CASE
				  WHEN b.Sporttype = 1
				  THEN-5
				  WHEN b.sporttype IN(2, 44)
				  THEN-4
			   END AS ProductID
			 , SUM(winLost_actualrate) AS winlost
			 , SUM(SMAWinloss) AS Position
			 , SUM(commission_actualrate) AS Commission
			 , SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate) * ISNULL(e.ExtraPT, 0)) AS RealHouseWinloss
			 , SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate) * ISNULL(e.ExtraPT, 0)) AS VirtualHouseWinloss
			 , SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome
			 , SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover
			 , SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE winlost_actualrate * e.ExtraPT
				  END) AS ExtraPT
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE(WinlossForExtraPT_actualrate + grosscomm_actualrate) * e.ExtraPT
				  END) AS NewExtraPT
		 FROM #src AS b
			LEFT JOIN #ExtraPT_Sel AS e ON b.srecommend = e.superID
									 AND e.ProductID = b.ProductId
									 AND e.Sporttype = CASE
													   WHEN b.sporttype = 44
													   THEN 44
													   ELSE 0
												    END
									 AND e.SubProduct = ''
		 WHERE b.ProductId = 1
		 GROUP BY CASE
				    WHEN b.Sporttype = 1
				    THEN-5
				    WHEN b.sporttype IN(2, 44)
				    THEN-4
				END;
--- Parlay			 
    INSERT INTO #Result(ProductId
				  , winlost
				  , Position
				  , Commission
				  , RealHouseWinloss
				  , VirtualHouseWinloss
				  , VarianceIncome
				  , RealTurnover
				  , VirtualTurnover
				  , ExtraPT
				  , NewExtraPT)
		 SELECT b.ProductId
			 , SUM(winlost_actualrate) AS WinLost
			 , SUM(SMAWinloss) AS Position
			 , SUM(commission_actualrate) AS Commission
			 , SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate) * ISNULL(e.ExtraPT, 0)) AS RealHouseWinloss
			 , SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate) * ISNULL(e.ExtraPT, 0)) AS VirtualHouseWinloss
			 , SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome
			 , SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover
			 , SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE winlost_actualrate * e.ExtraPT
				  END) AS ExtraPT
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE(WinlossForExtraPT_actualrate + grosscomm_actualrate) * e.ExtraPT
				  END) AS NewExtraPT
		 FROM #src AS b
			LEFT JOIN #ExtraPT_Sel AS e ON b.srecommend = e.superID
									 AND b.ProductID = -3
									 AND e.ProductID = 1
									 AND e.Sporttype = 0
									 AND e.SubProduct = ''
		 WHERE b.ProductID = -3
		 GROUP BY b.ProductId;
----NUMBER GAME			
    INSERT INTO #Result(ProductId
				  , winlost
				  , Position
				  , Commission
				  , RealHouseWinloss
				  , VirtualHouseWinloss
				  , VarianceIncome
				  , RealTurnover
				  , VirtualTurnover
				  , ExtraPT
				  , NewExtraPT)
		 SELECT b.ProductId
			 , SUM(winlost_actualrate) AS WinLost
			 , SUM(SMAWinloss) AS Position
			 , SUM(commission_actualrate) AS Commission
			 , SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate) * ISNULL(e.ExtraPT, 0)) AS RealHouseWinloss
			 , SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate) * ISNULL(e.ExtraPT, 0)) AS VirtualHouseWinloss
			 , SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome
			 , SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover
			 , SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE winlost_actualrate * e.ExtraPT
				  END) AS ExtraPT
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE(WinlossForExtraPT_actualrate + grosscomm_actualrate) * e.ExtraPT
				  END) AS NewExtraPT
		 FROM #src AS b
			LEFT JOIN #ExtraPT_Sel AS e ON b.srecommend = e.superID
									 AND b.ProductID = e.ProductId
		 WHERE b.ProductId = 3
		 GROUP BY b.ProductId;
------------------------------------------

---Virtual Sports, RNG Keno, Virtual Sports 2, Lottery
    INSERT INTO #Result(ProductId
				  , winlost
				  , Position
				  , Commission
				  , RealHouseWinloss
				  , VirtualHouseWinloss
				  , VarianceIncome
				  , RealTurnover
				  , VirtualTurnover
				  , ExtraPT
				  , NewExtraPT)
		 SELECT b.ProductId AS ProductId
			 , SUM(winlost_actualrate) AS WinLost
			 , SUM(SMAWinloss) AS Position
			 , SUM(commission_actualrate) AS Commission
			 , SUM(HouseWinloss_actualrate - (WinlossForExtraPT_actualrate + grosscomm_actualrate) * ISNULL(e.ExtraPT, 0)) AS RealHouseWinloss
			 , SUM(HouseWinloss_virtualrate - (WinlossForExtraPT_virtualrate + grosscomm_virtualrate) * ISNULL(e.ExtraPT, 0)) AS VirtualHouseWinloss
			 , SUM(HouseWinloss_variance - (WinlossForExtraPT_actualrate - WinlossForExtraPT_virtualrate) * ISNULL(e.ExtraPT, 0) - grosscomm_variance * ISNULL(e.ExtraPT, 0)) AS VarianceIncome
			 , SUM(turnover_actualrate - ISNULL(e.ExtraPT, 0) * stake_actualrate) AS RealTurnover
			 , SUM(turnover_virtualrate - ISNULL(e.ExtraPT, 0) * stake_virtualrate) AS VirtualTurnover
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE winlost_actualrate * e.ExtraPT
				  END) AS ExtraPT
			 , SUM(CASE ISNULL(e.ExtraPT, 0)
					 WHEN 0
					 THEN 0
					 ELSE(WinlossForExtraPT_actualrate + grosscomm_actualrate) * e.ExtraPT
				  END) AS NewExtraPT
		 FROM #src AS b
			LEFT JOIN #ExtraPT_Sel AS e ON b.srecommend = e.superID
									 AND e.ProductID = b.ProductId
		 WHERE b.ProductId IN(5, 8, 27, 28) ---Virtual Sports, RNG Keno, Virtual Sports 2, Lottery
		 GROUP BY b.ProductId;
-----2. Total ----------------------------------------------------------------

----Get Result----
    DECLARE @ProductOrder AS TABLE(
	    DisplayOrder    INT
	  , ProductId       INT
	  , ProductName     NVARCHAR(50)
	  , Site            TINYINT DEFAULT 0);
    INSERT INTO @ProductOrder(DisplayOrder
					   , ProductId
					   , ProductName)
    VALUES
		 (1, -5, 'Soccer'),
		 (2, -4, 'Other Sports'),
		 (3, -3, 'Parlay'),
		 (6, 8, 'RNG Keno'),
		 (7, 3, 'Number Game'),
		 (10, 5, 'Virtual Sports'),
		 (11, 27, 'Virtual Sports 2'),
		 (12, 28, 'Lottery');

    UPDATE R
		 SET
			DisplayOrder = P.DisplayOrder
		   , ProductName = P.ProductName
    FROM #Result R
	   INNER JOIN @ProductOrder P ON P.ProductID = R.ProductId;

    SELECT d.ProductName AS GroupName
	    , d.DisplayOrder
	    , SUM(d.winlost) AS MemberWinLoss
	    , SUM(d.Position) AS SMAWinLoss
	    , SUM(d.Commission) AS Commission
	    , SUM(d.RealHouseWinloss) AS RealIncome
	    , SUM(d.VirtualHouseWinloss) AS VirtualIncome
	    , SUM(d.VarianceIncome) AS VarianceIncome
	    , SUM(d.RealTurnover) AS RealTurnover
	    , SUM(d.VirtualTurnover) AS VirtualTurnover
	    , SUM(CASE
			    WHEN @StartDate < @EffectedDate
			    THEN-d.extraPT
			    ELSE-d.NewExtraPT
			END) AS HeadlineIncome
    FROM #Result AS d
    GROUP BY d.ProductName
		 , d.DisplayOrder
    ORDER BY DisplayOrder ASC;


    DROP TABLE #tmp_src;
    DROP TABLE #src;
    DROP TABLE #ExtraPT_Sel;
    DROP TABLE #Match;
    DROP TABLE #Result;
    DROP TABLE #SportBettype;
    DROP TABLE #tmp_XPG_SuperID;
END;