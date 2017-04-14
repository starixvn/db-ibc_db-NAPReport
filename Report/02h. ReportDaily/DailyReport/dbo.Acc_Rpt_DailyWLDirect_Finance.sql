ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Finance]
	@winlostdate	datetime
AS

	/*	Creator: Phuong Dao
		Date: 2009-03-03
		Task: Finance WinLost Summary report
		DB: DB06.bodb02
		
		Revisions:
			- 20090731@Jamie: Not to view data in range of date, but only one date at once 		
			-- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
			16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
	*/
	SET NOCOUNT ON
	
	SELECT		
			b.bettype bettype,
			sum((winlost-actual_stake)*actualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal,
			sum((1-tpositiontaking)*(case when b.winlostdate<'16 Dec 2010' then actual_stake else stake end)*actualrate) Turnover
	FROM	bettrans b WITH (NOLOCK)
	WHERE	b.winlostdate = @winlostdate
			AND b.bettype BETWEEN 51 AND 66 
			AND b.matchid > 0 
			AND b.ruben = 1		
			--AND b.status NOT IN ('VOID', 'REJECT','done','REFUND') 
			AND b.statusID not in (101,102,103,121)
			
	GROUP BY b.Bettype
	ORDER BY b.Bettype
	
	GO
    GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Finance] TO [bodbAdminNet]
    GO
    GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Finance] TO [vnteam]