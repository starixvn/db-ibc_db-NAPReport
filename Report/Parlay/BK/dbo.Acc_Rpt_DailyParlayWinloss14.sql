 ALTER PROCEDURE [dbo].[Acc_Rpt_DailyParlayWinloss14]
	@winlostdate datetime
AS
/*	Creator: Elodie
	Date: 20121016
	Task: Daily parlay winloss report
	DB: DB06.bodb02

	Revisions: 		

	Parameter's Explanation:
		- Combinations: Bettrans.betcheck is stored the number of selection by format 'm4', 'm3' ...
		- LiveType (Livehomescore):
			0: Non Live : All bets are Dead Ball 
			1: Live: All bets are Live Ball 
			2: Mix Live and Non Live: contains Live and Dead Ball

*/
SET NOCOUNT ON 
 
SELECT 
		case when betcheck in ('m2','m3','m4','m5') then betcheck else 'm6' end as Combinations, 
		livehomescore as LiveType, status, 
		sum((winlost-actual_stake)*actualrate) WinLost,
		count(1) BetCount,
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,
		sum(scomm*actualrate) Commission,	
		sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
		sum((1-tpositiontaking)*(ABS(stake)*actualrate)) Turnover	
FROM	bettrans14 WITH (NOLOCK)
WHERE
		ruben=1 AND
		bettype = 9 AND
		matchid = 9 AND 
		winlostdate = @winlostdate AND
		statusID NOT IN (101,102,103) 	
GROUP BY  case when betcheck in ('m2','m3','m4','m5') then betcheck else 'm6' end, livehomescore, status
ORDER BY  case when betcheck in ('m2','m3','m4','m5') then betcheck else 'm6' end, livehomescore, status

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyParlayWinloss14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyParlayWinloss14] TO [vnteam]  