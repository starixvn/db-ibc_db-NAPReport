ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Finance_Details14]
	@winlostdate	datetime,
	@bettype int
AS

  /*	Creator: Phuong Dao
		Date: 2009-03-03
		Task: Detailed Finance Report
		DB: DB06.bodb02
		
		Revisions:
			- 20090418@PhuongDao: Get IndexName from RemoteRef via homeid instead of matchcode 
			- 20090714@Kiwi: Exclude 'Refund' ticket
			- 20090731@Jamie: Not to view data in range of date, but only one date at once 	
			-- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement
			- 16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone

  */
	SET NOCOUNT ON
	
	SELECT	m.leagueid,	--- Market 
			m.homeid, -- Indexname,   --- Indexes 
			sum((winlost-actual_stake)*actualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*actualrate) Position,
			sum(scomm*actualrate) Commission,
			sum((1-tpositiontaking)*(case when b.winlostdate<'16 Dec 2010' then actual_stake else stake end)*actualrate) Turnover
	
	FROM	bettrans14 b with (nolock)
			INNER JOIN match14 m with (nolock) ON b.matchid = m.matchid
	WHERE	b.winlostdate = @winlostdate
			AND b.bettype=@bettype 
			AND b.matchid > 0 
			--AND b.status NOT IN ('VOID', 'REJECT','DONE', 'Refund') 
			AND b.statusID not in (101,102,103,121)
			AND b.ruben = 1	

	GROUP BY m.homeid, m.leagueid
	ORDER BY m.leagueid, m.homeid

    GO
    GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Finance_Details14] TO [bodbAdminNet]
	GO
	GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Finance_Details14] TO [vnteam]