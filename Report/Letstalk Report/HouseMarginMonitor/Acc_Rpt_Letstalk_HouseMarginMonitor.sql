/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/


USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_Letstalk_HouseMarginMonitor @FromDate  SMALLDATETIME,
											            @ToDate    SMALLDATETIME,
											            @BetType   VARCHAR(MAX) = '228' -- List of bet types to report, delimited by comma
AS
/*
	Created: Jaden.Tamg@20201208
	Task: House's Low Margin Alert via Lestalk (#146591)
	DB: DBACC.bodb02

	Revisions:
		- 20201208@Jaden.Tang: Creation - https://nexdev.net/projects/nap-accounting-report/wiki/House_Margin_Monitoring

    Example:
        exec bodb02.dbo.Acc_Rpt_Letstalk_HouseMarginMonitor '20200101', '20201230', '228,229'
*/

BEGIN

	SET NOCOUNT ON

    SELECT CAST(val AS INT) AS betType
    INTO #parameter
    FROM bodb02.dbo.strSplit(@BetType, ',')

    DECLARE @ExcludeDraw BIT = 1
   
    SELECT  sd.bettype                      AS BetType,
            MAX(bt.BetTypeName)             AS BetTypeName,
            SUM(sd.RealHouseIncome) 		AS HouseWL,
            SUM(sd.RealHouseTurnover) 		AS HouseTO
    FROM bodb02.dbo.f_bettrans_measures(@ExcludeDraw) sd
    INNER JOIN bodb02.dbo.f_HouseMarginMonitorBetTypes() bt
        ON sd.bettype = bt.BetType
        AND sd.bettype IN (SELECT betType FROM #parameter)
    WHERE sd.winlostdate BETWEEN @FromDate AND @ToDate
        AND sd.ruben = 1
        AND sd.statusID IN (111, 112, 113)
        AND sd.currency NOT IN (20, 27, 28)
    GROUP BY sd.bettype
    OPTION (RECOMPILE)

    DROP TABLE #parameter
END
GO
