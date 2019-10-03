ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostHRMS88_Details]
	@winlostdate	DATETIME
AS 
/*
	Created by: Jamie
	Date: 2009-08-12
	Task: Mansion88 Tote Horse Racing Detailed Report 
	DB: DB06.BODB02, DB02.BODB02
	
	Revisions:
		- 20091008@Jamie: Get the supers allowed to bet HR from the function
		- 20100508@Jamie: Change to call f_DepSuper_1 instead of f_DepSuperAllowedHR
		-- 20100526@Henry: Change to use StatusID instead of Status in WHERE statement

	Param's Explanation:
		+ Mansion HR Agent: PT = 0 , Comm = 4% 	
*/
BEGIN
	SET NOCOUNT ON 
	SELECT	currencyName,
			currency,
			leagueid,
			groupmatch,
			ISNULL(hr.winTOMem_Origin,0)			winTOMem_Origin,
			ISNULL(hr.winTOMem,0)					winTOMem,
			ISNULL(hr.placeTOMem_Origin,0)			placeTOMem_Origin,
			ISNULL(hr.placeTOMem,0)					placeTOMem,
			ISNULL(hr.winplaceTOMem_Origin,0)		winplaceTOMem_Origin,
			ISNULL(hr.winplaceTOMem,0)				winplaceTOMem,
			ISNULL(hr.winTOMem_Origin,0)
			  + ISNULL(hr.placeTOMem_Origin,0)
			  + ISNULL(hr.winplaceTOMem_Origin,0)	totalTOMem_Origin,
			ISNULL(hr.winTOMem,0)
			  + ISNULL(hr.placeTOMem,0)
			  + ISNULL(hr.winplaceTOMem,0)			totalTOMem,			
			ISNULL(hr.DividendWonMem_Origin,0)		DividendWonMem_Origin,	
			ISNULL(hr.DividendWonMem,0)				DividendWonMem,	
			ISNULL(hr.commIncomeAgency_Origin,0)	commIncomeAgency_Origin,		
			ISNULL(hr.commIncomeAgency,0)			commIncomeAgency,
			ISNULL(hr.winTOMem_Origin,0)
			  + ISNULL(hr.placeTOMem_Origin,0)
			  + ISNULL(hr.winplaceTOMem_Origin,0)
			  - ISNULL(hr.DividendWonMem_Origin,0)
			  - ISNULL(hr.commIncomeAgency_Origin,0)AmountDue2IBC_Origin,
 			ISNULL(hr.winTOMem,0)
			  + ISNULL(hr.placeTOMem,0)
			  + ISNULL(hr.winplaceTOMem,0)
			  - ISNULL(hr.DividendWonMem,0)
			  - ISNULL(hr.commIncomeAgency,0)		AmountDue2IBC	

	FROM (
			SELECT	o.leagueid,
					o.groupmatch,
					b.currency,
					b.currencyName,
					-- Turnover Member 
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake ELSE 0 END) winTOMem_Origin,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake ELSE 0 END) placeTOMem_Origin,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE b.liveawayscore WHEN 0 THEN b.actual_stake/2 ELSE b.actual_stake END) ELSE 0 END) winplaceTOMem_Origin,
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*b.actualrate ELSE 0 END) winTOMem,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*b.actualrate ELSE 0 END) placeTOMem,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE b.liveawayscore WHEN 0 THEN b.actual_stake/2 ELSE b.actual_stake END)*b.actualrate ELSE 0 END) winplaceTOMem,
					-- DividendWon Member 
					SUM(CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN b.winlost -b.actual_stake/2 ELSE b.winlost END) DividendWonMem_Origin,
					SUM(CASE WHEN b.bettype = 33 AND b.liveawayscore = 0 THEN (b.winlost -b.actual_stake/2)*b.actualrate ELSE b.winlost*b.actualrate END) DividendWonMem,
					-- commission Agency 	
					SUM(b.scomm) commIncomeAgency_Origin,
					SUM(b.scomm*b.actualrate) commIncomeAgency	

			FROM	bettrans b WITH (NOLOCK) 
					INNER JOIN Outright o WITH (NOLOCK) ON b.matchid = o.orid 
			WHERE	b.winlostdate = @winlostdate 
					AND b.bettype in (31,32,33)
					--AND b.status not in ('VOID','REJECT','DONE','Refund')
					AND b.statusID NOT IN (101,102,103,121)
					AND b.ruben = 1
					AND b.srecommend in (SELECT custid FROM f_DepSuper_1('Mansion88'))
			GROUP BY o.leagueid, o.groupmatch, b.currency, b.currencyName					  		
	)hr
	ORDER BY currencyName, leagueid, CAST (groupmatch AS TINYINT)
END 
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHRMS88_Details] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHRMS88_Details] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHRMS88_Details] TO [vnteam]

