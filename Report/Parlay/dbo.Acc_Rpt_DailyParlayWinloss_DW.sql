 ALTER PROC [dbo].[Acc_Rpt_DailyParlayWinloss_DW]
	@FromDate datetime,
	@ToDate datetime
AS

/*	Creator: Dom.Cao
	Date: 20121018
	Task: Daily parlay winloss report DW
	DB: DBDW2.bodb_dwrs

	Revisions: 		

	Parameter's Explanation:
		- Combinations: Bettrans.betcheck is stored the number of selection by format 'm4', 'm3' ...
		- LiveType (Livehomescore):
			0: Non Live : All bets are Dead Ball 
			1: Live: All bets are Live Ball 
			2: Mix Live and Non Live: contains Live and Dead Ball

*/


SELECT *
INTO #Exchange 
FROM bodb02.dbo.ExchangeDailyOanda edo WITH(NOLOCK)
WHERE edo.ExchangeDate >=@FromDate AND edo.ExchangeDate <= @ToDate

SELECT 'm'+ CASE WHEN Combination IN(2,3,4,5) THEN cast(Combination AS nvarchar) ELSE '6' END  AS Combinations,
	livestat AS LiveType,
	st.STATUS AS status,
	SUM(WinlossP * actualrate) AS Winlost,
	SUM(BetCount) AS Betcount,
	SUM((winlossA+WinlossS+WinlossM) * actualrate) AS Position,
	
	SUM(CommissionS * actualrate) AS Commission,
	SUM((winlossIBC+CommissionS) * actualrate) AS "LineTotal",  
	SUM(TurnoverIBC * actualrate) AS Turnover
FROM  bodb_account.dbo.rptParlay b WITH(NOLOCK)
	LEFT JOIN bodb_Account.dbo.tbl_Status st with (nolock) on b.status = st.statusid
	LEFT JOIN #exchange ex ON ex.exchangeid = b.currency AND ex.exchangedate = b.rptdate
WHERE b.rptdate >=@FromDate AND b.rptDate <=@ToDate
GROUP BY
    'm'+ CASE WHEN Combination IN(2,3,4,5) THEN cast(Combination AS nvarchar) ELSE '6' END ,
	livestat,
	st.STATUS
ORDER BY
    'm'+ CASE WHEN Combination IN(2,3,4,5) THEN cast(Combination AS nvarchar) ELSE '6' END ,
	livestat,
	st.STATUS
	
	--CASE b.sporttype WHEN 1 THEN 'Soccer' WHEN 2 THEN 'Other Sport' WHEN 3 THEN 'Multi Sports' END
DROP TABLE #exchange	
GO 

GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyParlayWinloss_DW] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyParlayWinloss_DW] TO [vnteam] 
