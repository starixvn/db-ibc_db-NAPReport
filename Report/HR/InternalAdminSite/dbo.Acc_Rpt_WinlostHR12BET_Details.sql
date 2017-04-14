ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostHR12BET_Details]
	@winlostdate	datetime,
	@ReportType		INT = 0 
AS 
BEGIN
/*
	Created by: Phuong Dao
	Date: 2009-05-09
	Task: 12BET Tote Horse Racing Detailed Report 
	DB: DB06.BODB02, DB02.BODB02
	
	Revisions:
		- 20090603@PhuongDao: 
			+ Winloss with Positiontaking Tote
			+ Add 12BETSuperTB 
		- 20091008@Jamie: 
			+ Allow the members under currency IN to bet HR 
			+ Get the list of supers from the function
		- 20100508@Jamie: Change to call f_DepSuper_1 instead of f_DepSuperAllowedHR
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20110725@Johnson: separate report for Horse racing SA, UK, AU
	
	
	Param's Explanation:
		@ReportType = 0: All Parner
					= 1: HR SA Tote
					= 2: HR UK
					= 3: HR AUS
*/
	SET NOCOUNT ON 
	
	DECLARE @tmpPartner TABLE(groupType INT, partnerID INT)
	
	IF @ReportType = 0
	BEGIN
		INSERT INTO @tmpPartner(groupType,partnerid)
			SELECT 1,1 -- SA,RACE-PHU
		UNION ALL 
			SELECT 2,2 -- UK,RACE-ATRUK
		UNION ALL
			SELECT 2,3 -- UK,RACE-ATRIRL
		UNION ALL
			SELECT 2,4 -- UK,RACE-RUK
		UNION ALL
			SELECT 3,5--  AUS,RACE-TARCORP
	END
	ELSE IF @ReportType =1
	BEGIN
		INSERT INTO @tmpPartner(groupType,partnerid)
			SELECT 1,1 -- SA,RACE-PHU
	END
	ELSE IF @ReportType = 2
	BEGIN
		INSERT INTO @tmpPartner(groupType,partnerid)
			SELECT 2,2 -- UK,RACE-ATRUK
		UNION ALL
			SELECT 2,3 -- UK,RACE-ATRIRL
		UNION ALL
			SELECT 2,4 -- UK,RACE-RUK
	END
	ELSE IF @ReportType = 3
	BEGIN
		INSERT INTO @tmpPartner(groupType,partnerid)
			SELECT 3,5--  AUS,RACE-TARCORP
	END
	
	SELECT	[groupType],			
			currencyName,
			currency,
			leagueid,
			groupmatch,
			ISNULL(hr.PTWLAgency_Origin,0)			PTWLAgency_Origin,
			ISNULL(hr.PTWLAgency,0)					PTWLAgency,
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
			ISNULL(hr.winTOAgency_Origin,0)			winTOAgency_Origin,
			ISNULL(hr.winTOAgency,0)				winTOAgency,			
			ISNULL(hr.placeTOAgency_Origin,0)		placeTOAgency_Origin,
			ISNULL(hr.placeTOAgency,0)				placeTOAgency,
			ISNULL(hr.winplaceTOAgency_Origin,0)	winplaceTOAgency_Origin,
			ISNULL(hr.winplaceTOAgency,0)			winplaceTOAgency,
			ISNULL(hr.winTOAgency_Origin,0)
			  + ISNULL(hr.placeTOAgency_Origin,0)
			  + ISNULL(hr.winplaceTOAgency_Origin,0)totalTOAgency_Origin,
			ISNULL(hr.winTOAgency,0)
			  + ISNULL(hr.placeTOAgency,0)
			  + ISNULL(hr.winplaceTOAgency,0)		totalTOAgency,
			ISNULL(hr.commIncomeAgency_Origin,0)	commIncomeAgency_Origin,		
			ISNULL(hr.commIncomeAgency,0)			commIncomeAgency,
			ISNULL(hr.winTOMem_Origin,0)
			  + ISNULL(hr.placeTOMem_Origin,0)
			  + ISNULL(hr.winplaceTOMem_Origin,0)
			  - ISNULL(hr.DividendWonMem_Origin,0)
			  - ISNULL(hr.PTWLAgency_Origin,0)
			  - ISNULL(hr.commIncomeAgency_Origin,0)AmountDue2IBC_Origin,
 			ISNULL(hr.winTOMem,0)
			  + ISNULL(hr.placeTOMem,0)
			  + ISNULL(hr.winplaceTOMem,0)
			  - ISNULL(hr.DividendWonMem,0)
			  - ISNULL(hr.PTWLAgency,0)
			  - ISNULL(hr.commIncomeAgency,0)		AmountDue2IBC	

	FROM (
			SELECT	t.[groupType],					
					o.leagueid,
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
					
					--turnover Agency
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*b.tpositiontaking ELSE 0 END) winTOAgency_Origin,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*b.tpositiontaking ELSE 0 END) placeTOAgency_Origin,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE b.liveawayscore WHEN 0 THEN b.actual_stake/2 ELSE b.actual_stake END)*b.tpositiontaking ELSE 0 END) winplaceTOAgency_Origin,
					SUM(CASE WHEN b.bettype = 31 THEN b.actual_stake*b.tpositiontaking*b.actualrate ELSE 0 END) winTOAgency,
					SUM(CASE WHEN b.bettype = 32 THEN b.actual_stake*b.tpositiontaking*b.actualrate ELSE 0 END) placeTOAgency,
					SUM(CASE WHEN b.bettype = 33 THEN (CASE b.liveawayscore WHEN 0 THEN b.actual_stake/2 ELSE b.actual_stake END)*b.tpositiontaking*b.actualrate ELSE 0 END) winplaceTOAgency,
					
					--commission Agency 	
					SUM(b.scomm) commIncomeAgency_Origin,
					SUM(b.scomm*b.actualrate) commIncomeAgency,		
					
					--PT Winloss Agency 
					SUM(b.awinlost + b.mwinlost + b.swinlost) PTWLAgency_Origin,
					SUM((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) PTWLAgency			

			FROM	bettrans b WITH (NOLOCK) 
					INNER JOIN Outright o WITH (NOLOCK) ON b.matchid = o.orid
					INNER JOIN RacingMeeting r WITH (NOLOCK) ON o.leagueid = r.meetingid
					INNER JOIN  @tmpPartner t ON r.partnerid = t.partnerid
			WHERE	b.winlostdate = @winlostdate 
					AND b.bettype in (31,32,33)
					--AND b.status not in ('VOID','REJECT','DONE','Refund')
					AND b.statusID NOT IN (101,102,103,121)
					AND b.ruben = 1
					AND b.srecommend in (SELECT custid FROM f_DepSuper_1('12BET'))
						
			GROUP BY  t.[groupType], o.leagueid, o.groupmatch, b.currency, b.currencyName					  		
	)hr
	ORDER BY [groupType], currencyName, leagueid, CAST (groupmatch AS TINYINT) 
END 
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_Details] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostHR12BET_Details] TO [Dot_Member]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostHR12BET_Details] TO [vnteam]