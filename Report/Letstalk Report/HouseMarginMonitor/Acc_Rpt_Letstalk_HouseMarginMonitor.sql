/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/


USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_Letstalk_HouseMarginMonitor @FromDate        SMALLDATETIME,
											            @ToDate          SMALLDATETIME,
											            @BetType         VARCHAR(MAX) = '228', -- List of bet types to report, delimited by comma
                                                        @WLThreshold     FLOAT = -10000, -- bet types that under this threshold will be reported
                                                        @MarginThreshold FLOAT = -10     -- unit: percent %, bet types that under this threshold will be reported
AS
/*
	Created: Jaden.Tamg@20201208
	Task: House's Low Margin Alert via Lestalk (#146591)
	DB: DBACC.bodb02

	Revisions:
		- 20201208@Jaden.Tang: Creation - https://nexdev.net/projects/nap-accounting-report/wiki/House_Margin_Monitoring
        - 20201211@Jaden.Tang: Use less-than-or-equal check for @MarginThreshold instead of less-than
		- 20220805@Jaden.Tang: Remove SELECT INTO #tmp pattern (#176082)
                               Remove table function f_bettrans_measure

    Example:
        exec bodb02.dbo.Acc_Rpt_Letstalk_HouseMarginMonitor '20200101', '20201230', '228,229'
*/

BEGIN

	SET NOCOUNT ON

	CREATE TABLE #tmpHalfWonLoseBettype (Bettype int)

    INSERT INTO #tmpHalfWonLoseBettype (Bettype)
    SELECT DISTINCT BetType
    FROM bodb02.dbo.SportBettypeMatrix (NOLOCK)
    WHERE ProductID = 1 AND BetType NOT IN (29, 38, 901, 902 ,903, 904, 999, 18999)

    CREATE TABLE #parameter (BetType INT)
    
    INSERT INTO #parameter
    SELECT CAST(val AS INT) AS betType
    FROM bodb02.dbo.strSplit(@BetType, ',')

    DECLARE @ExcludeDraw BIT = 1
   
    ;WITH CTE_measures AS (
        SELECT  winlostdate,
                sd.bettype                  AS BetType,
                ruben,
                statusID,
                currency,
                (sd.winlost - sd.actual_stake + sd.awinlost + sd.mwinlost + sd.swinlost + sd.scomm 
                    - (CASE WHEN sd.tpositiontaking = 1 THEN 0
                            ELSE sd.winlost - sd.actual_stake + sd.scomm / (1 - sd.tpositiontaking)
                        END) 
                    * ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0)) 
                    * sd.actualrate 	    AS RealHouseIncome,
                CASE WHEN sd.tpositiontaking = 1 THEN 0
                     ELSE (1 - sd.tpositiontaking - ISNULL(CAST(sd.epositiontaking AS DECIMAL(9, 8)), 0))
                                * ABS(sd.stake)
                                * CASE WHEN sd.virtualrate > sd.actualrate THEN sd.virtualrate ELSE sd.actualrate END
                END 
                * 
                CASE WHEN @ExcludeDraw = 1 
                     THEN CASE WHEN ((sd.winlostdate < '2019-10-01' AND sd.bettype IN (1, 3, 7, 8, 17, 18, 124, 125, 482, 483, 484, 485))
                                        OR (sd.winlostdate >= '2019-10-01' AND h.Bettype IS NOT NULL))
                                    AND sd.statusID IN (112, 113)
                                    AND ABS(sd.modds) = 0.25
                          THEN 0.5
                          ELSE 1 END
                     ELSE 1 
                END 		                AS RealHouseTurnover
        FROM bodb02.dbo.bettrans sd WITH (NOLOCK)
        LEFT JOIN #tmpHalfWonLoseBettype h WITH (NOLOCK) 
            ON sd.bettype = h.Bettype
    )
    SELECT  sd.bettype                      AS BetType,
            MAX(bt.typenamee)               AS BetTypeName,
            -SUM(sd.RealHouseIncome) 		AS HouseWL,
            SUM(sd.RealHouseTurnover) 		AS HouseTO
    FROM CTE_measures sd
    INNER JOIN bodb02.dbo.bettype bt WITH (NOLOCK)
        ON sd.bettype = bt.typeid
    WHERE sd.winlostdate BETWEEN @FromDate AND @ToDate
        AND sd.ruben = 1
        AND sd.statusID IN (111, 112, 113)
        AND sd.currency NOT IN (20, 27, 28)
        AND sd.bettype IN (SELECT BetType FROM #parameter)
    GROUP BY sd.bettype
    HAVING -SUM(sd.RealHouseIncome) <= @WLThreshold
       AND (-SUM(sd.RealHouseIncome) / SUM(sd.RealHouseTurnover)) * 100 <= @MarginThreshold
    OPTION (RECOMPILE)

    DROP TABLE #tmpHalfWonLoseBettype
    DROP TABLE #parameter
END
GO
