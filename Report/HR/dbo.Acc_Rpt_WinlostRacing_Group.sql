ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostRacing_Group]
	@fromdate	smalldatetime,
	@todate		smalldatetime
AS 
/*
	Created by: Jamie
	Date: 2009-06-27
	Task: Group Horse Racing Report
	DB: DBRPT/bodb_report
	Original : [Acc_Rpt_WinlostHR_Group]

	History:
		- 20090814@Jamie: Show Fixed Odd HR 
		- 20100527@Jamie: Add one more section for Partner [DividendWon, Expense Comm, Fees]
			+ Amount Due to: Phu: include Fees ; Others: exclude Fees
		- 20101113@Henry: Add column Partner
			+ HRType = 1 --> Partner: PHU
			+ HRType = 2 --> Partner: RUK
			+ HRType = 3 --> Partner: ATR
			+ HRType = 4 --> Partner: ATRIRE
			+ HRType = 5 --> Partner: AUS
		- 20110303@Johnson: - get report from rptRacingWinlost table not rptHRWinlost
							- Include AU meeting
							- AmountFee2rd Include fees from AU meeting 
							- not use HRType instead get partnerID 
		- 20111226@Jamie: Change the Amount Due To for Greyhound UK/Irish 
		- 20130226@Lukas: move SP to database bodb_Report
	Explanation's Param:
		- AmountDueToPartner: 
			+ HR For UK/Irish: Minus Tote Fee ( -ToteFee)
			+ Greyhound for UK/Irish: Not Including ToteFee (0)
			+ Others: Plus ToteFee ( + ToteFee)

*/
	SET NOCOUNT ON
	SELECT	winlostdate,
			r.PartnerName,
			--CASE HRType 
			--	WHEN 1 THEN 'PHU'
			--	WHEN 2 THEN 'RUK'
			--	WHEN 3 THEN 'ATR'
			--	WHEN 4 THEN 'ATRIRE'
			--	WHEN 5 THEN 'AUS'
			--END Partner,
			turnoverAgents,
			turnoverHouse, -- turnoverIBC -> turnoverHouse
			turnoverAgents 
			 + turnoverHouse 		
			 + turnover3rd		totalTurnover, --IBC + Agents + Partner 
			incomeHousePT,			
			incomeHouseNetComm,		
			incomeHousePT 
			 + incomeHouseNetComm	totalHouseIncome, -- totalIBCIncome -> totalHouseIncome
			income12BETPT,
			income12BETComm,
			income12BETPT 
			 + income12BETComm	total12BETIncome,
			incomeHousePT
			 + incomeHouseNetComm
			 + income12BETPT
			 + income12BETComm	groupTotalIncome,
			ISNULL(turnover3rd,0) turnover3rd,
			ISNULL(DividendWon3rd,0) DividendWon3rd,
			ISNULL(ExpComm3rd,0) ExpComm3rd,
			ISNULL(Fees3rd,0) Fees3rd,
			ISNULL(turnover3rd,0) 
			 - ISNULL(DividendWon3rd,0)  	
			 - ISNULL(ExpComm3rd,0)
			 + (CASE	WHEN m.PartnerID IN (2,3,4) THEN - ISNULL(Fees3rd,0)	-- HR for UK/Irish: -- RACE-ATRUK ,RACE-ATRIRL ,RACE-RUK
						WHEN m.PartnerID IN (101,102) THEN 0					-- Greyhound for UK/Irish: GREY-DTOTEUK, GREY-DTOTEIRL
						ELSE ISNULL(Fees3rd,0) END) AmountDue23rd				-- Others
			
	FROM	dbo.rptRacingWinlost m WITH (NOLOCK)
			INNER JOIN bodb02.dbo.RacingPartner r WITH(NOLOCK) ON 	m.partnerID = r.partnerID
	WHERE	winlostdate BETWEEN @fromdate AND @todate 
	ORDER BY winlostdate, m.PartnerID 



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostRacing_Group] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostRacing_Group] TO [vnteam] AS [dbo]