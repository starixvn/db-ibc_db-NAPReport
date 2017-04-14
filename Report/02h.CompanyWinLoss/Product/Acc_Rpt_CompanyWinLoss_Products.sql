USE [bodb02]
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_CompanyWinLoss_Products]
	 @StartDate SMALLDATETIME,
      @EndDate   SMALLDATETIME
AS
/*	Creator: Sophia.Nguyen
	Date: 2016-05-11
	Task: Company Winloss Report - Main SP [Redmine: #48448]
	DB: DBACC/bodb02	
		
	Revisions:
		- 20160622@Sophia: 	. Remove group by ExtraPT to avoid duplicated data. [Redmine: #59732]
							. Ignore param @EndDate because of the performance, and business supports only one day 
		 
		- 20160915@Percy: Integrate NG2 [RedmineID: #63460]
		- 20160922@Percy: Use local parameter to prevent bad parameter sniffing [RedmindID: #64573]
		- 20161130@Percy: Integrate Fishing World [RedmineID: #67757]
		- 20161213@Sophia: Remove parameter @winlostdate, use @StartDate to obtain parameter sniffing [RedmindID: #68634]
		- 20160112@Percy: Change Extra PT formula [RedmineID: #70208]
	Explanation's Param:
	
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @EffectedDate DATETIME -- 20160112@Percy: Applying date of changing extra PT formula [RedmineID: #70208]
	SELECT  @EffectedDate = '2017-01-19'
	
	------Get Sport Bettype Matrix------
	-- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	CREATE TABLE #SportBettype (ProductID INT, Bettype INT,EventType INT, SubProduct VARCHAR(500), RefTable TINYINT, CasinoType TINYINT)
	INSERT INTO #SportBettype ( ProductID, Bettype, EventType, SubProduct, RefTable, CasinoType)
	SELECT ProductID,
        Bettype,
        EventType,
        SubProduct,
		RefTable,
		CasinoType
    FROM dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)

	 
	--- End Sport Bettype Matrix------
	
	
	CREATE TABLE #src(	srecommend INT,
						site	TINYINT,
						Sporttype INT, 						
						winlost_actualrate MONEY, 
						winlost_virtualrate MONEY,
						position_actualrate MONEY, 
						position_virtualrate MONEY, 
						commission_actualrate MONEY, 
						commission_virtualrate MONEY, 
						Linetotal_actualrate MONEY,
						Linetotal_virtualrate MONEY,
						turnover_actualrate MONEY,
						turnover_virtualrate MONEY ,
						grosscomm_actualrate MONEY,
						ProductId INT,
						CasinoType TINYINT
					)

	CREATE TABLE #srcDetail
					(	srecommend INT,
						site	TINYINT,											
						winlost_actualrate MONEY, 
						winlost_virtualrate MONEY,
						position_actualrate MONEY, 
						position_virtualrate MONEY, 
						commission_actualrate MONEY, 
						commission_virtualrate MONEY, 
						Linetotal_actualrate MONEY,
						Linetotal_virtualrate MONEY,
						turnover_actualrate MONEY,
						turnover_virtualrate MONEY,
						grosscomm_actualrate MONEY,
						ProductId INT,
						CasinoType TINYINT
					)

	CREATE TABLE #Result (
						DisplayOrder	INT,
						ProductId		INT,
						ProductName		NVARCHAR(50),											
						site			TINYINT,
						winlost			MONEY, 
						Position		MONEY, 
						Commission		MONEY,
						RealLineTotal	MONEY, 
						VirtualLineTotal MONEY, 
						RealTurnover	MONEY, 
						VirtualTurnover MONEY, 						
						ExtraPT			MONEY,
						NewExtraPT		MONEY
					)


	--- Deposit Super
	CREATE TABLE #DepSuper (custid int )
			 
	INSERT INTO #DepSuper 
	SELECT custid FROM f_DepSuper_1('All')
	
	
	---- Extra PT 
	CREATE TABLE #ExtraPT_Sel (ProductID INT,Sporttype INT ,SubProduct VARCHAR(100),SuperID INT,ExtraPT DECIMAL(9,8))
			
	INSERT INTO #ExtraPT_Sel (ProductID, Sporttype, SubProduct, SuperID, ExtraPT) 
	SELECT	ProductID, SportType, SubProduct, SuperId, SUM(ExtraPT) AS ExtraPT 
	FROM	bodb_ACC.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
	WHERE	@StartDate BETWEEN FromDate AND Todate
	GROUP BY ProductID, SportType, SubProduct, SuperId

	
	----------------------	Racing -------------------------------------
	 DECLARE @RBWinlost TABLE(
							site TINYINT,
							winlost money,
							pos money,
							comm money,
							Linetotal money,							
							turnover money								
						)	


	---insert company's comm setting that is recieved from Phumelela into this temp table.
	DECLARE @tmpIBCFee TABLE(partnerID int,IBCFee bit)

	DECLARE @CommSetting TABLE
	(	MatchId			int,
		IBCFee			bit,
		ToteCommWin		smallmoney,
		ToteCommPlace	smallmoney,
		ToteCommWP		smallmoney,
		ToteFee			smallmoney	
	)
	 
	
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

	 		
	INSERT INTO @CommSetting (MatchId, IBCFee, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
	SELECT	DISTINCT o.orid as MatchId, t.IBCFee, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.LeagueId = p.LeagueId AND p.programDate = o.programDate
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.LeagueId
			INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
	WHERE	o.EventDate = @StartDate
	
	
	----------------------------------- 
	INSERT INTO @RBWinlost (  site, winlost, pos, comm, Linetotal, turnover)
	SELECT	 
			case when dep.custid is null then 1 else 2 end as site,
			sum((b.winlost -b.actual_stake)*b.actualrate) as winlost,
			sum((b.awinlost + b.mwinlost + b.swinlost)*b.actualrate) as pos,
			sum(b.scomm*b.actualrate) as comm,
			-(sum((case when b.bettype = 33 then bm.WLIBC else -(b.winlost -b.actual_stake)*isnull(b.oddsspread,0) end)*b.actualrate) 
								- sum( case when cs.IBCFee = 0 then 0 else (case when b.bettype = 33 then bm.TOPhum when b.bettype in (31,32) then b.actual_stake*(1 -b.tpositiontaking - isnull(b.oddsspread,0)) else 0 end)*b.actualrate*cs.ToteFee end) --FeeDue2 
								+ sum((case b.bettype when 31 then b.actual_stake*cs.ToteCommWin*(1 - b.tpositiontaking - isnull(oddsspread,0))
													when 32 then b.actual_stake*cs.ToteCommPlace*(1 - b.tpositiontaking - isnull(oddsspread,0))
													when 33 then bm.TOPhum*cs.ToteCommWP  
													else 0 end)*b.actualrate) --commIncomeIBC
								- sum(b.scomm*b.actualrate)) as realLinetotal,
			sum(case when b.bettype = 33 then bm.TOIBC*b.actualrate else b.actual_stake*isnull(oddsspread,0)*b.actualrate end) as turnover
			
	FROM	bettrans b with (nolock)
			INNER JOIN @CommSetting as cs ON b.MatchId = cs.MatchId 
			 left join (
				select	refno,
						sum(case when bm.bettype = 32 and liveawayscore =0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bm.bettype = 32 and liveawayscore = 0 then 0 when bm.bettype = 31 or (bm.bettype = 32 and liveawayscore <> 0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm bm with (nolock)
				INNER JOIN #SportBettype s ON s.Bettype = bm.bettype 
				WHERE 	s.ProductID = 2
				group by refno
			 )bm on b.transid = bm.refno 
			 INNER JOIN #SportBettype s ON s.Bettype = b.bettype
			 left join (select custid FROM #DepSuper) dep ON b.srecommend = dep.custid
	WHERE	b.ruben = 1 
			and s.ProductID = 2
			and b.MatchId >0
			and b.winlostdate = @StartDate 
			and b.statusID in (111, 112, 113)	
	GROUP BY  case when dep.custid is null then 1 else 2 end

	-------------------------------------- End of Racing -------------------------------------------------
	CREATE TABLE #Match (MatchId INT, sporttype smallint, [type] tinyint)--, primary key(MatchId, type))
	INSERT INTO #Match 
	SELECT	m.MatchId, 
			s.sporttype,
			m.type
	FROM (
			SELECT MatchId, LeagueId, exrisk, MatchCode, 0 as type --'match'
			FROM match WITH (NOLOCK) WHERE EventDate = @StartDate
			UNION ALL
			SELECT orid, LeagueId, 0, MatchCode, 1 as type --'outright'
			FROM outright WITH (NOLOCK) WHERE EventDate = @StartDate
			)m	
	INNER JOIN league l WITH (NOLOCK) ON m.LeagueId = l.LeagueId	
	INNER JOIN Sports s WITH (NOLOCK) ON l.sporttype = s.sporttype 

	CREATE CLUSTERED INDEX CIX_MatchID ON #Match (MatchID, [Type])
	
	--------------------------------------------------------------------------------
	---1. Sportsbook only and outright (not Parlay)
	INSERT INTO #src (srecommend ,site, SportType, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
					  Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, grosscomm_actualrate, ProductId )
	SELECT	srecommend,
			1 AS site,
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype = 1 THEN 1				
				 ELSE 2 
				 END AS SportType,		
			SUM((winlost-actual_stake)*actualrate) winlost_actualrate,
			SUM((winlost-actual_stake)*virtualrate) winlost_virtualrate,
			SUM((awinlost+mwinlost+swinlost)* actualrate) position_actualrate,
			SUM((awinlost+mwinlost+swinlost)*virtualrate) position_virtualrate,	
			SUM(scomm*actualrate) commission_actualrate,
			SUM(scomm*virtualrate) commission_virtualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal_actualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal_virtualrate,
			SUM((1-tpositiontaking)*ABS(stake)*actualrate) turnover_actualrate, 
			SUM((1-tpositiontaking)*ABS(stake)*virtualrate) turnover_virtualrate,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm/(1-b.tpositiontaking) END)*b.actualrate) grosscomm_actualrate,
			1 As ProductId   
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype  
		INNER JOIN #Match m ON b.MatchId = m.MatchId 		
	WHERE winlostdate = @StartDate
		AND b.bettype < 19001
		AND b.statusID IN (111, 112, 113) 
		AND b.ruben = 1	
		AND m.type = CASE WHEN b.bettype = 10 THEN 1 ELSE 0 END 
		AND s.productID = 1
		AND s.EventType IN (1,2)
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm','BT-Winloss') 
	GROUP BY srecommend,
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype = 1 THEN 1				
				 ELSE 2
				 END
				 
	------ BARM (only)
	INSERT INTO #src (srecommend ,site, SportType, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
					  Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, grosscomm_actualrate, ProductId )
	SELECT	2 AS srecommend,
			2 AS site,
			CASE WHEN m.sporttype = 44 THEN 44 
				  WHEN m.Sporttype = 1 THEN 1				
				 ELSE 2
				 END AS SportType,		
			SUM((winlost-actual_stake)*actualrate) winlost_actualrate,
			SUM((winlost-actual_stake)*virtualrate) winlost_virtualrate,
			SUM((awinlost+mwinlost+swinlost)* actualrate) position_actualrate,
			SUM((awinlost+mwinlost+swinlost)*virtualrate) position_virtualrate,	
			SUM(scomm*actualrate) commission_actualrate,
			SUM(scomm*virtualrate) commission_virtualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal_actualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal_virtualrate,
			SUM((1-tpositiontaking)*ABS(stake)*actualrate) turnover_actualrate, 
			SUM((1-tpositiontaking)*ABS(stake)*virtualrate) turnover_virtualrate,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm/(1-b.tpositiontaking) END)*b.actualrate) grosscomm_actualrate,
			1 As ProductId   
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype  
		INNER JOIN #Match m ON b.MatchId = m.MatchId   
	WHERE  b.recommend = 5707545 
		AND	b.winlostdate = @StartDate
		AND b.bettype < 19001
		AND b.statusID IN (111, 112, 113) 
		AND b.ruben = 1	
		AND m.type = CASE WHEN b.bettype = 10 THEN 1 ELSE 0 END 
		AND s.productID = 1
		AND s.EventType IN (1,2)
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm','BT-Winloss') 
	GROUP BY  
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype = 1 THEN 1				
				 ELSE 2 
				 END	

		
	----- Minus data of BARM 
	UPDATE 	c
	SET		c.winlost_actualrate = c.winlost_actualrate - d.winlost_actualrate,
			c.winlost_virtualrate = c.winlost_virtualrate - d.winlost_virtualrate,
			c.position_actualrate = c.position_actualrate - d.position_actualrate,
			c.position_virtualrate = c.position_virtualrate - d.position_virtualrate,
			c.commission_actualrate = c.commission_actualrate - d.commission_actualrate,
			c.commission_virtualrate = c.commission_virtualrate - d.commission_virtualrate,
			c.LineTotal_actualrate = c.LineTotal_actualrate - d.LineTotal_actualrate,
			c.LineTotal_virtualrate = c.LineTotal_virtualrate - d.LineTotal_virtualrate,
			c.turnover_actualrate = c.turnover_actualrate - d.turnover_actualrate,
			c.turnover_virtualrate = c.turnover_virtualrate - d.turnover_virtualrate,
			c.grosscomm_actualrate = c.grosscomm_actualrate - d.grosscomm_actualrate
	FROM	#src c
	INNER JOIN #src d
		ON c.srecommend = d.srecommend
			AND c.SportType = d.SportType 
	WHERE  c.srecommend = 2 AND c.Site = 1 AND d.Site = 2
								 

 	---2. Not Sportsbook and not have detail table yet ; and special Sportsbook : Parlay, Metric gaming, Bettrade 
	INSERT INTO #src (srecommend ,site, SportType, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
					  Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, grosscomm_actualrate, ProductId, CasinoType )
	SELECT	srecommend,
			1 as site,  
			0 AS SportType,
			SUM((winlost-actual_stake)*actualrate) winlost_actualrate,
			SUM((winlost-actual_stake)*virtualrate) winlost_virtualrate,
			SUM((awinlost+mwinlost+swinlost)* actualrate) position_actualrate,
			SUM((awinlost+mwinlost+swinlost)*virtualrate) position_virtualrate,	
			SUM(scomm*actualrate) commission_actualrate,
			SUM(scomm*virtualrate) commission_virtualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal_actualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal_virtualrate,
			SUM((1-tpositiontaking)*ABS(stake)*actualrate) turnover_actualrate, 
			SUM((1-tpositiontaking)*ABS(stake)*virtualrate) turnover_virtualrate,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm/(1-b.tpositiontaking) END)*b.actualrate) grosscomm_actualrate,
			CASE s.SubProduct WHEN 'MG-SuperLive' THEN -1 WHEN 'BT-Comm' THEN -2 WHEN 'BT-Winloss' THEN -2 ELSE CASE WHEN s.EventType = 0 AND ProductID = 1 THEN -3 ELSE s.ProductID END END AS ProductID,
			s.CasinoType
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype
	WHERE winlostdate = @StartDate
		AND b.bettype < 19001
		AND b.statusID IN (111, 112, 113) 
		AND b.ruben = 1	
		AND	( ----s.productID NOT IN (1,6,17,22,21) ---- OW RNG(6), Microgaming - RNG Casino (17), Voidbridge (22),  Allbet (21)	
			(s.productID <> 1 AND s.RefTable NOT IN (1,2))  ------ not have data detail in bettransRNG and BettransLC 
			OR (s.productID = 1 AND s.SubProduct IN ('MG-SuperLive','BT-Comm','BT-Winloss')) ---Metric Gaming - Superlive , Bettrade
			OR (s.productID = 1 AND s.EventType = 0 ) ----Palay
			)	
	GROUP BY srecommend ,
			CASE s.SubProduct WHEN 'MG-SuperLive' THEN -1 WHEN 'BT-Comm' THEN -2 WHEN 'BT-Winloss' THEN -2 ELSE CASE WHEN s.EventType = 0 AND ProductID = 1 THEN -3 ELSE s.ProductID END END,
			s.CasinoType   

	----3. Get from Detail table ----------
	-- Get bettransRNG data	
	INSERT INTO #srcDetail (srecommend ,site , winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
							Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, grosscomm_actualrate, ProductId, CasinoType)
	SELECT	b.srecommend,
			1 as site,			
			SUM((winlost-actual_stake)*actualrate) winlost_actualrate,
			SUM((winlost-actual_stake)*virtualrate) winlost_virtualrate,
			SUM((awinlost+mwinlost+swinlost)* actualrate) position_actualrate,
			SUM((awinlost+mwinlost+swinlost)*virtualrate) position_virtualrate,	
			SUM(scomm*actualrate) commission_actualrate,
			SUM(scomm*virtualrate) commission_virtualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal_actualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal_virtualrate,
			SUM((1-tpositiontaking)*ABS(b.stake)*actualrate) turnover_actualrate, 
			SUM((1-tpositiontaking)*ABS(b.stake)*virtualrate) turnover_virtualrate,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm/(1-b.tpositiontaking) END)*b.actualrate) grosscomm_actualrate,
			s.ProductID, s.CasinoType
	FROM bettransRNG b WITH(NOLOCK)
		INNER JOIN #SportBettype s ON b.gameid = s.bettype	
	WHERE winlostdate = @StartDate
		----AND s.ProductID IN (6,17,22) 	---- OW RNG(6), Microgaming - RNG Casino (17), Voidbridge (22)
		AND s.RefTable = 1  --- Use Table BettransRNG
		AND b.statusID IN (111, 112, 113) 
	GROUP BY b.srecommend, s.ProductID, s.CasinoType
			 
	 	 
	-- Get bettransLC Data
	INSERT INTO #srcDetail (srecommend ,site, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
							Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, grosscomm_actualrate, ProductId, CasinoType)
	SELECT	
			b.srecommend,
			1 as site, 	
			SUM((winlost-actual_stake)*actualrate) winlost_actualrate,
			SUM((winlost-actual_stake)*virtualrate) winlost_virtualrate,
			SUM((awinlost+mwinlost+swinlost)* actualrate) position_actualrate,
			SUM((awinlost+mwinlost+swinlost)*virtualrate) position_virtualrate,	
			SUM(scomm*actualrate) commission_actualrate,
			SUM(scomm*virtualrate) commission_virtualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*actualrate) LineTotal_actualrate,
			SUM((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal_virtualrate,
			SUM((1-tpositiontaking)*ABS(b.stake)*actualrate) turnover_actualrate, 
			SUM((1-tpositiontaking)*ABS(b.stake)*virtualrate) turnover_virtualrate,
			SUM((CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm/(1-b.tpositiontaking) END)*b.actualrate) grosscomm_actualrate,
			s.ProductID, s.CasinoType
	FROM bettransLC b WITH(NOLOCK)	
		INNER JOIN #SportBettype s ON b.gameid = s.bettype
	WHERE winlostdate = @StartDate
		----AND s.ProductID = 21  ---- AllBet (21)
		AND s.RefTable = 2  --- Use Table BettransLC
		AND b.statusID IN (111, 112, 113) 
	GROUP BY
			b.srecommend, s.ProductID, s.CasinoType
			 
	-------------------------------------------------------

	UPDATE	#src
	SET		site = 2
	WHERE 	srecommend IN (SELECT CustId FROM  #DepSuper)
	
	UPDATE	#srcDetail
	SET		site = 2
	WHERE 	srecommend IN (SELECT CustId FROM  #DepSuper)  
	

	---------------------------------------------------------		  
	-------------Insert to Result table to get data----------
	-----1. Soccer and Others
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT
			CASE WHEN b.Sporttype = 1 THEN -5
				 WHEN b.sporttype IN (2,44) THEN -4 				 
				 END as ProductID,	
			site,
			SUM(winLost_actualrate) AS winlost,
			SUM(position_actualrate) AS Position,
			SUM(commission_actualrate) AS Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(Linetotal_virtualrate) AS VirtualLineTotal,
			SUM(turnover_actualrate) AS RealTurnover,
			SUM(turnover_virtualrate) AS VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#src b		
		LEFT JOIN #ExtraPT_Sel e 
			ON  b.srecommend = e.superID 
			AND e.ProductID = b.ProductId 			
			AND e.Sporttype = CASE WHEN b.sporttype = 44 THEN 44 ELSE 0 END
			AND e.SubProduct = ''  			
	WHERE	b.ProductId = 1
	GROUP BY		
			CASE WHEN b.Sporttype = 1 THEN -5
				 WHEN b.sporttype IN (2,44) THEN -4 				 
				 END,			
			site 		
	 	

			   
	----METRIC GAMING -SUPER LIVE
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT
			b.ProductID, site,
			SUM(ISNULL(b.winlost_actualrate,0)) WinLost,
			SUM(ISNULL(b.position_actualrate,0)) Position,
			SUM(ISNULL(commission_actualrate,0)) Commission,	
			SUM(ISNULL(LineTotal_actualrate,0)) AS RealLineTotal,
			SUM(ISNULL(Linetotal_virtualrate,0)) as VirtualLineTotal,	
			SUM(ISNULL(turnover_actualrate,0)) RealTurnover,
			SUM(ISNULL(turnover_virtualrate,0)) VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#src b		
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID 	
		AND b.ProductId = -1 
		AND e.ProductID = 1		
		AND e.Sporttype = 0 
		AND e.SubProduct = 'MG-SuperLive'
	WHERE b.ProductId = -1
	GROUP BY b.ProductId, site 

	
	--- Parlay			 
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT 
			b.ProductId, site,
			SUM(winlost_actualrate) WinLost,
			SUM(position_actualrate) Position,
			SUM(commission_actualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(Linetotal_virtualrate) AS VirtualLineTotal,	
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#src b
		LEFT JOIN #ExtraPT_Sel e 
			ON  b.srecommend = e.superID 
			AND b.ProductID = -3
			AND e.ProductID = 1 		
			AND e.Sporttype = 0
			AND e.SubProduct = ''
	WHERE	b.ProductID = -3	
	GROUP BY b.ProductId, site
	
	----NUMBER GAME			
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT
		    b.ProductId, site,
			SUM(winlost_actualrate) WinLost,
			SUM(position_actualrate) Position,
			SUM(commission_actualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(Linetotal_virtualrate) AS VirtualLineTotal,	
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#src b		
	LEFT JOIN #ExtraPT_Sel e 
			ON  b.srecommend = e.superID 
			AND b.ProductID = e.ProductId			
	WHERE	b.ProductId = 3		
	GROUP BY b.ProductId, site


	---Racing
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT	2 as ProductId,
			site,
			WinLost,
			Pos AS Position,
			Comm AS Commission,
			LineTotal AS RealLineTotal,
			LineTotal AS VirtualLineTotal,
			turnover AS RealTurnover,
			0 VirtualTurnover,
			0 ExtraPT,
			0 NewExtraPT
	FROM   @RBWinlost

	---bettrade
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT
			b.ProductId,
			site,
			SUM(ISNULL(b.winlost_actualrate,0)) WinLost,
			SUM(ISNULL(b.position_actualrate,0)) Position,
			0 AS Commission,	
			SUM(ISNULL(LineTotal_actualrate,0)) AS RealLineTotal,
			SUM(ISNULL(LineTotal_actualrate,0)) as VirtualLineTotal,	
			0 AS RealTurnover,
			0 AS VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#src b
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID
			AND b.ProductId = -2
			AND e.ProductId = 1 
			AND e.Sporttype = 0
			AND (e.SubProduct = 'BT-Comm' OR e.SubProduct ='BT-Winloss')
	WHERE	b.ProductId = -2
	GROUP BY site, b.ProductId

	------------------------------------------
	---Live casino and Casino and 3rd Party
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT	
			--CASE WHEN b.ProductId IN (14) THEN 6   ---- Casino
			--	ELSE CASE WHEN  b.ProductId IN (4,11,12,13) THEN 4  ---Live Casino
			--		ELSE b.ProductId END END AS ProductId  ,

			CASE WHEN b.CasinoType = 1 THEN 6  ---- Casino
				 WHEN b.CasinoType = 2 THEN 4  ---Live Casino
				 ELSE b.ProductId END AS ProductId ,
			site,
			SUM(winlost_actualrate) WinLost,
			SUM(position_actualrate) Position,
			SUM(commission_actualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(LineTotal_virtualrate) AS VirtualLineTotal,
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#src b		
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID 
			AND e.ProductID = b.ProductId	
	WHERE	b.ProductId IN (5,8,15,23) ---Virtual Sports, Keno, Colossus Bets, NG2 (3rd)
			--- OR b.ProductId IN (4,11,12,13)    -----SLI, AG Casino, Gold Deluxe, MGC Live casino  (liveCasino)
			--- OR b.ProductId IN (6, 14) --- Macau (Casino)
			OR b.CasinoType IN (1,2)
			
	GROUP BY site, CASE WHEN b.CasinoType = 1 THEN 6   ---- Casino
				 WHEN b.CasinoType = 2 THEN 4  ---Live Casino
				 ELSE b.ProductId END

	 
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT	
			--CASE WHEN b.ProductId IN (6,17,22) THEN 6  --- Casino
			--	ELSE 4	--- Live Casino
			--	END AS ProductId,	
						
			CASE WHEN b.CasinoType = 1 THEN 6  ---- Casino
				 WHEN b.CasinoType = 2 THEN 4  ---Live Casino
				 ELSE b.ProductId END AS ProductId ,	
			site,
			SUM(winlost_actualrate) WinLost,
			SUM(position_actualrate) Position,
			SUM(commission_actualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(LineTotal_virtualrate) AS VirtualLineTotal,
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate)* e.ExtraPT END) AS ExtraPT,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE (winlost_actualrate + grosscomm_actualrate)* e.ExtraPT END) AS NewExtraPT
	FROM	#srcDetail b			
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID 
			AND e.ProductID = b.ProductId	
	WHERE b.ProductId IN (24) -- Fishing World
			---OR  b.ProductId IN (6,17,22) --- OW RNG + Microgaming - RNG Casino, Macau Games (Casino)
			OR b.CasinoType IN (1,2)
	GROUP BY site, 
			 CASE WHEN b.CasinoType = 1 THEN 6  ---- Casino
				 WHEN b.CasinoType = 2 THEN 4  ---Live Casino
				 ELSE b.ProductId END

	-----2. Total ----------------------------------------------------------------
	-- Get win lost of agent '8RM' , 'BARM'
	INSERT INTO #Result (ProductId, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, ExtraPT, NewExtraPT)
	SELECT	CASE WHEN m.Sporttype = 1 THEN -98				
				 ELSE -99
				 END AS ProductId,
			CASE b.recommend WHEN 52466 THEN 1 
							 WHEN 5707545 THEN 2 END AS site,		
			-SUM (winlost-actual_stake) WinLost,
			-SUM (awinlost+mwinlost+swinlost) Position,
			SUM (scomm) Commission,	
			-SUM (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-SUM (winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			SUM ((1-tpositiontaking)*ABS(stake)) RealTurnover,
			SUM ((1-tpositiontaking)*ABS(stake)) VirtualTurnover,	
			0 AS ExtraPT,
			0 AS NewExtraPT
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype  
		INNER JOIN #Match m ON b.MatchId = m.MatchId   
	WHERE  b.recommend IN (52466, 5707545)
		AND	b.winlostdate = @StartDate
		AND b.bettype < 19001
		AND b.statusID IN (111, 112, 113) 
		AND b.ruben = 1	
		AND m.type = CASE WHEN b.bettype = 10 THEN 1 ELSE 0 END 
		AND s.productID = 1
		AND s.EventType IN (1,2)
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm','BT-Winloss') 
	GROUP BY  
			CASE WHEN m.Sporttype = 1 THEN -98				
				 ELSE -99
				 END,
			CASE b.recommend WHEN 52466 THEN 1 
							 WHEN 5707545 THEN 2 END					
	-----3. Total ----------------------------------------------------------------



	--------------------------------------------
	----Get Result----
	
	DECLARE @ProductOrder AS TABLE (						
						DisplayOrder	INT,
						ProductId		INT,
						ProductName		NVARCHAR(50),
						Site			TINYINT DEFAULT (0)
						)
	
	INSERT INTO @ProductOrder (DisplayOrder, ProductId, ProductName)
	VALUES 	
	 (1, -5, 'Soccer')
	,(2, -1, 'Metric Gaming - Superlive')
	,(3, -4, 'Other Sports')
	,(4, -3, 'Parlay')

	,(5, 3, 'Number Game')
	,(6, 4, 'Live Casino')
	,(7, 6, 'Casino')
	,(8, 5, 'Virtual Sports')
	,(9, 8, 'Keno')
	,(10, 2, 'Racing')
	,(11, -2, 'Bettrade')
	,(12, 15, 'Colossus Bets')
	,(13, 23, 'NG2')
	,(14, 24, 'Fishing World')

		
	INSERT INTO @ProductOrder (DisplayOrder, ProductId, ProductName, Site)
	VALUES 	
	 (100, -98, 'Soccer 8RM', 1)
	, (100, -98, 'Soccer BARM', 2)
	, (101, -99, 'Other Sports 8RM', 1)
	, (101, -99, 'Other Sports BARM', 2)


	UPDATE	R
	SET		DisplayOrder = P.DisplayOrder,
			ProductName = P.ProductName
	FROM	#Result R
	INNER JOIN @ProductOrder P
			ON P.ProductID = R.ProductId
			AND P.Site = CASE WHEN P.Site <> 0 THEN r.Site ELSE 0 END  


	 SELECT		CASE WHEN d.DisplayOrder IN (100,101)  THEN 'RM' ELSE d.ProductName END AS GroupName,
                CASE WHEN d.DisplayOrder IN (100,101) THEN d.ProductName
					 WHEN d.Site = 1 THEN 'Credit' 
					 WHEN d.Site = 2 THEN 'Deposit' 
					END AS RowName,
				d.DisplayOrder, site,
                SUM (d.winlost) AS MemberWinLoss,
                SUM (d.Position) AS SMAWinLoss,
                SUM (d.Commission) AS Commission,
                SUM (d.RealLineTotal) AS RealIncome,
                SUM (d.VirtualLineTotal) AS VirtualIncome,
                SUM (d.RealLineTotal - d.VirtualLineTotal) AS VarianceIncome,
                SUM (d.RealTurnover) AS RealTurnover,
                SUM (d.VirtualTurnover) AS VirtualTurnover,
				SUM (CASE WHEN @StartDate < @EffectedDate THEN -d.extraPT ELSE -d.NewExtraPT END) AS extraPT,
				SUM (CASE WHEN @StartDate < @EffectedDate THEN d.RealLineTotal - d.extraPT ELSE d.RealLineTotal - d.NewExtraPT END) AS AfterExtraPT
        FROM #Result d   
		GROUP BY CASE WHEN d.DisplayOrder IN (100,101) THEN 'RM' ELSE d.ProductName END,
                 CASE WHEN d.DisplayOrder IN (100,101) THEN d.ProductName
					 WHEN d.Site = 1 THEN 'Credit' 
					 WHEN d.Site = 2 THEN 'Deposit' 
					END,  
				d.DisplayOrder, site        
		ORDER BY DisplayOrder ASC,  site	

	
	DROP TABLE #src
	DROP TABLE #srcDetail
	DROP TABLE #DepSuper
	DROP TABLE #ExtraPT_Sel
	DROP TABLE #Match
	DROP TABLE #Result	
	DROP TABLE #SportBettype
	
	
END

GO 
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_CompanyWinLoss_Products] TO [vnteam]
GO 
GRANT EXECUTE ON [dbo].[Acc_Rpt_CompanyWinLoss_Products] TO [bodbAdminNet]
GO 