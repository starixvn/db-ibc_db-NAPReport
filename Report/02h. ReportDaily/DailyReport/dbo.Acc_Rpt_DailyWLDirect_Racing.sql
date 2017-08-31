USE [bodb02]
GO

/****** Object:  StoredProcedure [dbo].[Acc_Rpt_DailyWLDirect_Racing]    Script Date: 11/20/2015 1:14:19 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Racing]
	@winlostdate	datetime
AS
SET NOCOUNT ON

/*	Created: Johnson
	Date: 2011-03-14
	Task: Winloss Summary History for Racing
	DB: DBACC/bodb02
	
	Revisions: 		
		- 20110701@Johnson: change the programdate in LeagueDetail is the programdate in OutRight
		- 20130618@Johnson: Add NSW racing's pools from AUST
		- 20130730@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)			
		- 20150108@Dom: Apply sport bettype matrix	
		- 20151120@Percy: Change column name (to match DW) [RedmineID: #46576]
		- 20170831@Cherry: Extend data type of Sporttype (#73545)
*/

----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT)
	INSERT INTO @SportBettype
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode=4,@ProductId=2

	DECLARE @tmpIBCFee TABLE(partnerID int,IBCFee bit)
		
	DECLARE @CommSetting TABLE (matchid int primary key,
						IBCFee			bit,
						sporttype		int,
						ToteCommWin		smallmoney,
						ToteCommPlace	smallmoney,
						ToteCommWP		smallmoney,
						ToteFee			smallmoney
					)
	CREATE TABLE #DepAgent (custid int primary key)
		
	INSERT INTO #DepAgent 
	SELECT custid
	FROM custInfo with(NOLOCK)
	WHERE srecommend IN (SELECT custid FROM f_DepSuper_1('All'))
	AND roleid = 2
	UNION
	SELECT 5707545--BARM					
				
	INSERT INTO @tmpIBCFee (partnerID, IBCFee)
		SELECT 1,1 --RACE-PHU
	UNION ALL
		SELECT 2,0 --RACE-ATRUK
	UNION ALL
		SELECT 3,0 --RACE-ATRIRL
	UNION ALL
		SELECT 4,0 --RACE-RUK
	UNION ALL
		SELECT 5,1 --RACE-TABCORP
	UNION ALL
		SELECT 6,1 --RACE-TABCORPNSW
	UNION ALL
		SELECT 101,1 --GREY-DTOTEUK
	UNION ALL
		SELECT 102,1 --GREY-DTOTEIRL
	UNION ALL
		SELECT 103,1 --GREY-TABCORP
	UNION ALL
		SELECT 104,1 --GREY-TABCORPNSW
	UNION ALL
		SELECT 201,1 --HAR-TABCORP
	UNION ALL
		SELECT 202,1 --HAR-TABCORPNSW
		
	INSERT INTO @CommSetting
	SELECT m.orid , t.IBCFee, l.sporttype, p.ToteCommWin, p.ToteCommPlace,(p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM outright m WITH(NOLOCK)
		INNER JOIN LeagueDetail p WITH(NOLOCK) ON m.leagueid = p.leagueid and p.programDate = m.programDate 
		INNER JOIN RacingMeeting r WITH(NOLOCK) ON p.leagueid = r.meetingid		
		INNER JOIN league l WITH(NOLOCK) ON m.leagueid = l.leagueid
		INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID 
	WHERE m.eventdate = @winlostdate and l.sporttype between 151 and 153
		
	SELECT	cs.sporttype,
			case when dep.custid is null then 1 else 2 end as [Site],
			sum((b.winlost -b.actual_stake)*b.actualrate) WinLost,
			sum((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) Position,
			sum(b.scomm*b.actualrate) Commission,
			-(sum((case when b.bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
			- sum(case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when b.bettype in (31,32) then b.actual_stake*(1 - b.tpositiontaking - isnull(b.oddsspread,0) ) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
			+ sum((case b.bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
								when 33 then bm.TOPhum*cs.ToteCommWP 
								else 0 end)*b.actualrate) --commIncomeIBC
			- sum(b.scomm*b.actualrate)) LineTotal,
			sum(case when b.bettype = 33 then bm.TOIBC*b.actualrate else b.actual_stake*isnull(oddsspread,0)*b.actualrate end) Turnover
			
	FROM	bettrans b with (nolock)
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid  
			 left join (
				select	refno,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore <>0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
			 left join (SELECT custid FROM #DepAgent) dep ON b.recommend = dep.custid
			 INNER JOIN @SportBettype s ON s.bettype = b.bettype
	WHERE	b.ruben =1 
			--and b.bettype in (31,32,33)
			and b.matchid >0
			and b.winlostdate = @winlostdate
			--and b.status not in ('VOID','REJECT','DONE','REFUND')
			and b.statusID NOT IN (101,102,103,121)

	GROUP BY cs.sporttype ,case when dep.custid is null then 1 else 2 end
	ORDER BY cs.sporttype, site
	
	DROP TABLE #DepAgent
	
	

GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Racing] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Racing] TO [vnteam] AS [dbo]
GO


