 ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_VirtualHR_Details14]  
	@winlostdate datetime,  
	@SportType  int,  
	@bettype  int  
AS  
	/* Creator: Elodie  
	Date: 2013-03-07  
	Task: Detailed Winloss Summary History for Virtual HR  
	DB: DBACC/bodb02  

	Revisions:  

	*/   
SET NOCOUNT ON     

	SELECT  
		r.LeagueID,  
		r.EventTime Race,
		sum((winlost-actual_stake)*actualrate) WinLost,  
		sum((awinlost+mwinlost+swinlost)*actualrate) Position,  
		sum(scomm*actualrate) Commission,  
		isnull(sum((winlost-actual_stake + awinlost+mwinlost+swinlost + scomm)*actualrate), 0) as LineTotal,
		sum((1-tpositiontaking)*ABS(b.stake)*actualrate) Turnover  
	FROM  
		bettrans14 b with (nolock)  
		INNER JOIN VSRaceInfo r with (nolock) ON b.matchid = r.EventID  
	WHERE  
		winlostdate = @winlostdate  
		AND b.statusID NOT IN (102, 101, 103) AND b.ruben = 1   
		AND r.SportType = @SportType  
		AND b.BetType = @Bettype  
		and b.matchid >0  
	GROUP BY     
		r.leagueid, 
		r.EventTime 
	ORDER BY   
		r.leagueid, 
		r.EventTime

GO
GRANT EXECUTE ON dbo.[Acc_Rpt_DailyWLDirect_VirtualHR_Details14] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_VirtualHR_Details14] TO [vnteam]       