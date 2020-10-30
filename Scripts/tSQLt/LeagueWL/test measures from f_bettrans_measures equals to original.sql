USE bodb02
GO

ALTER PROCEDURE testLeagueWinloss.[test measures from f_bettrans_measures equals to original]
AS
	/*created by Jaden: test new tvf's integrity*/
	/*execution: `tSQLt.Run 'testLeagueWinloss.[test measures from f_bettrans_measures equals to original]'`*/
BEGIN
    -------------------------------------------------------------
    IF OBJECT_ID('tempdb..#actual') IS NOT NULL DROP TABLE #actual
    IF OBJECT_ID('tempdb..#expected') IS NOT NULL DROP TABLE #expected
    -------------------------------------------------------------
    EXEC dbo.[__set up tests__]
    -------------------------------------------------------------
    DECLARE @IsNoDraw BIT = 0
    -------------------------------------------------------------
	CREATE TABLE #actual ( MatchID              INT,
                           LiveIndicator        BIT,
                           MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)

	CREATE TABLE #expected(MatchID              INT,
                           LiveIndicator        BIT,
                           MemberWinLoss		MONEY,
						   SMAWinLoss			MONEY,
						   ExtraPT				MONEY,
						   Commission			MONEY,
						   RealIncome			MONEY,
						   VirtualIncome		MONEY,
						   VarianceIncome		MONEY,
						   RealTurnover		    MONEY,
						   VirtualTurnover		MONEY)
    ------------build #actual
   	INSERT INTO #actual 
       SELECT   MatchID        
              , LiveIndicator  
              , MemberWinLoss
              , SMAWinLoss	
              , [Extra's Amount]		
              , [TreeCommission]	
              , RealHouseIncome	
              , VirtualHouseIncome
              , VarianceHouseIncome
              , RealHouseTurnover	
              , VirtualHouseTurnover
        FROM dbo.f_bettrans_measures(@IsNoDraw)
    ------------build #expected
    INSERT INTO #expected
        SELECT sd.matchid,
            sd.liveindicator LiveIndicator,
            ((sd.winlost - sd.actual_stake) * sd.actualrate) AS MemberWinLoss,
            ((sd.awinlost + sd.mwinlost + sd.swinlost) * sd.actualrate) AS SMAWinLoss,
            ((CASE WHEN sd.tpositiontaking = 1 THEN 0
                 ELSE (sd.winlost - sd.actual_stake) + sd.scomm / (1 - sd.tpositiontaking) END) 
             * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0) 
             * sd.actualrate
             ) AS ExtraPT,
            (sd.scomm * sd.actualrate) AS Commission,
            ((
                 sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost + sd.scomm 
                 - CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking) END 
                 * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)
             ) 
             * sd.actualrate
             ) AS RealIncome,
            ((
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
            ((
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
            (CASE WHEN sd.tpositiontaking = 1 THEN 0
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
            (CASE WHEN sd.tpositiontaking = 1 THEN 0
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
    FROM dbo.bettrans sd (NOLOCK)
    -------------------------------------------------------------
    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
    -------------------------------------------------------------
END;
GO