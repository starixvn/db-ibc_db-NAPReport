USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_Sporttype]
	@winlostdate	smalldatetime 
AS
/*	Creator: Phuong Dao
	Date: 2009-03-03
	Task: Daily Winloss Report
	DB: DBACC/bodb02	
		
	History:
		- 20090514@PhuongDao: Winlost for Casino
		- 20090608@PhuongDao: PT Winlost Tote HR
		- 20090722@Kiwi: Improve HR peformance by using table variable
		- 20090731@Jamie: Not to view data in range of date, but only one date at once 	
		- 20090815@Jamie: Include Fixed Odds Report
		- 20091109@Kiwi: Declare @temp table to contain all matches based on @winlostdate
		- 20100331@Jamie: arrange the new structure for HR meetings 
			+ Remove hard-code FeeDue2 
			+ Remove Fixed Odds out as well
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20100611@Henry: Change mix-parlay match from 0 to 9
		- 20100916@Henry: Include Bingo + Number Game
		- 20101204@Johnson: Separate Number Game from Other Sports
		16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
		- 20110314@Johnson: - change Horse Racing to Racing	
							- Check Tote Fee is passed to Partners or not
							- Remove Finance report
		- 20110516@Lukas: re-arrange bettype
		- 20110701@Johnson: - change the programdate in LeagueDetail is the programdate in OutRight
		- 20110801@Johnson: - add new bettype system parlay
							- add more bettype for number game Warrior, Next Combo, Number Group
		- 20110824@Johnson: - remove check winlostdate with '16 Dec 2010' for sumary turnover, get from stake instead actual_stake
		- 20110824@Elly: - Correct Turnover of sports book since Sep 01, 2011
		- 20110930@Tom: 1. Add Report for P2P Games  Bettype: 1000	
						2. Hide code Report Casino and Bingo
		- 20111122@Tom: Unhide code Report Casino and Bingo
		- 20111202@Sophia: . Add new range for sportbook from 121 to 999
						   . Remove @NegativeBetEffectiveDate
		- 20120231@Sophia: Add live casino bettype from 1101 to 1199
		- 20120210@Henry: Fix System parlay bug turnover
		- 20120405@Hurri: Exclude bettype 72 (P2P bet ticket) in the calculation of Casino
		- 20120412@Hurri: Get win lost of agent 'BARM' (@WinLost_BARM)
		- 20120503@Sophia: Edit LineTotal and Comm for P2P
		- 20120514@Elodie:  Correct win lost of agent 'BARM'
		- 20120530@Elodie: Change formula of 8RM/BARM winloss
		- 20120628@Elodie: check case of matchid = orid
		- 20120814@Elodie: Add Virtual sports report
		- 20120920@Elodie: Add DisplayOrder field
		- 20121009@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20121015@Elodie: Add EnableVirtual field, arrange the order of products to separate 2h report into 2 sections: 
								+ Section 1: all products that disable virtual currency 
								+ Section 2: all products that enable virtual currency 
		- 20121017@Lukas: performance tunning - use temp table before retrieve some products	
		- 20121102@Elodie: Use actual rate instead of virtural rate for Virtual sport		
		- 20130408@Elodie: Add RealLineTotal field for all products that enable virtual currency
		- 20130522@Elodie: Get more fields RealTurnover, VirtualTurnover
		- 20130618@Johnson: Add NSW racing's pools from AUST	
		- 20130703@Kathy: Update matchid for RnG Ca			
		- 20130717@Kathy: Apply Progressive Bonus: add bettype 72 for Casino
		- 20130730@Johnson: Separate win loss by credit/deposit site(1: credit, 2: deposit)				
		- 20130910@Johnson: get virtual values for all product	
		- 20140303@Dom: Add Keno
		- 20140910@Johnson: - Separate major and minor bettypes of soccer
							- Combine Mix Parlay and System Parlay into 1 section
		- 20141203@Dom: Apply sport bettype matrix
		- 20150204@Johnson: move 1H Double Chance bet type to major bettype [RedmineID: #27216]
		- 20150521@Sophia: Apply Gold Deluxe and Metric Gaming - SuperLive and revise Sport Betype Matrix [#35359] 
		- 20150702@Sophia: Apply Microgaming and SuperBalance [#38168]
		- 20150723@Sophia: Apply Bettrade [#38815]
		- 20150805@Sophia: Get Turnover of Macau and Microgaming - RNG Casino (Group Casino)
		- 20150828@Sophia: Apply Colossus Bets [#41935]
		- 20150917@Jim: Integrate MO product (Feature #41935)
		- 20151109@Sophia: Microgaming RNG Casino New sporttype [RedmineID: #46576]		
		- 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
		- 20151210@Percy: Add new product: Cockfighting Sabong [Redmine: #49027]
		- 20160125@Robert: Cricket - Integrate to Accounting Reports [#50274]
		- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
		- 20160308@Jim: Incorporate Extra PT into 2h report [#53194]
		- 20160415@Sophia:  . Fix bug After ExtraPT of Sportbook  [Redmine: #55533]
							. Remove P2P, Bingo
		- 20160408@Robert: Support drill-down to the match winloss details for Megic Gaming - Superlive product [RedmineID#55584]
		- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
		- 20160504@Sophia: Refactor code, Enhance Performance , Remove Cockfighting [Redmind: #56764]
		- 20160615@Sophia: Change READPAST to NOLOCK because of the Deadlock [Redmind: #59254]
		- 20160718@Percy: Remove FromDate, ToDate fields when select from Acc_GroupExtraPTSetting [RedmineID: #60973]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)

	Explanation's Param:
		- @FI_3rdShare: winloss of Third party 
		- @WinLost_BARM: winlost for outsource (We use agent 'BARM' to put all outsoucing transactions which follow BA danger customers)declare @p2 money
		  SET @p2 = -430156.7928;
		  EXEC Acc_Rpt_DailyWLDirect_Sporttype
			  @winlostdate = '2015-09-10 00:00:00',
			  @LineTotal = @p2 OUTPUT;
		  SELECT @p2;
		- DisplayOrder field:	1 -> 100: all products that enable virtual currency 
								101 -> 200: all products that disable virtual currency 

		

*/
BEGIN
	SET NOCOUNT ON

	
	 ------Get Sport Bettype Matrix------
	 -- Check SP Version	 
	 DECLARE @isTest BIT = 0
	 SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	 CREATE TABLE #SportBettype (ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500), IsSoccerMajor BIT)
	 INSERT INTO #SportBettype ( ProductID, Bettype, EventType, SubProduct)
	 SELECT ProductID,
            Bettype,
            EventType,
            SubProduct
     FROM dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest)

	 
	 UPDATE #SportBettype 
	 SET IsSoccerMajor = 1 
	 WHERE Bettype IN (1,2,3,5,6,7,8,12,15,24,25,28,121,122,123,126,151,301,302,303,304)

	  --- End Sport Bettype Matrix------
		
	 DECLARE @RBWinlost TABLE(
							site TINYINT,
							winlost money,
							pos money,
							comm money,
							Linetotal money,							
							turnover money								
						)			
	
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
						ProductId INT   
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
						ProductId INT  
					)

	CREATE TABLE #DepSuper (custid int )
	CREATE TABLE #ExtraPT_Sel (ProductID INT,Sporttype INT ,SubProduct VARCHAR(100),SuperID INT,ExtraPT DECIMAL(9,8),fromdate DATETIME, todate DATETIME  )
	
	CREATE TABLE #Result (
						DisplayOrder	INT,
						SportName		NVARCHAR(50),
						SportType		INT,
						ibc				TINYINT,
						site			TINYINT,
						winlost			MONEY, 
						Position		MONEY, 
						Commission		MONEY,
						RealLineTotal	MONEY, 
						VirtualLineTotal MONEY, 
						RealTurnover	MONEY, 
						VirtualTurnover MONEY, 
						EnableVirtual	MONEY,
						ExtraPT			MONEY,
						ProductId		INT 
					)
										
	--insert company's comm setting that is recieved from Phumelela into this temp table.
	DECLARE @tmpIBCFee TABLE(partnerID int,IBCFee bit)

	DECLARE @CommSetting TABLE
	(	MatchID			int,
		IBCFee			bit,
		ToteCommWin		smallmoney,
		ToteCommPlace	smallmoney,
		ToteCommWP		smallmoney,
		ToteFee			smallmoney	
	)
	 
	--deposit super
	INSERT INTO #DepSuper 
	SELECT custid FROM f_DepSuper_1('All')
	
			
	INSERT INTO #ExtraPT_Sel (ProductID, Sporttype, SubProduct, SuperID, FromDate, ToDate, ExtraPT )
	SELECT	ProductID, SportType, SubProduct, SuperId, FromDate, ToDate, SUM(ExtraPT) AS ExtraPT 
	FROM	bodb_ACC.dbo.Acc_GroupExtraPTSetting a WITH (NOLOCK)
	WHERE	@winlostdate BETWEEN FromDate AND Todate
	GROUP BY ProductID, SportType, SubProduct, SuperId, FromDate, ToDate
	
	---CREATE CLUSTERED INDEX IX_ExtraPT ON #ExtraPT_Sel (SuperID, ExtraPT)
	
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

	 		
	INSERT INTO @CommSetting (MatchID, IBCFee, ToteCommWin, ToteCommPlace, ToteCommWP, ToteFee)
	SELECT	DISTINCT o.orid as matchid, t.IBCFee, p.ToteCommWin, p.ToteCommPlace, (p.ToteCommWin + p.ToteCommPlace)/2 ToteCommWP, p.ToteFee 
	FROM	outright o WITH (NOLOCK)
			INNER JOIN LeagueDetail p WITH (NOLOCK) ON o.leagueID = p.LeagueID AND p.programDate = o.programDate
			INNER JOIN RacingMeeting r WITH(NOLOCK) ON r.meetingID = p.leagueid
			INNER JOIN @tmpIBCFee t ON r.partnerID = t.partnerID
	WHERE	o.eventdate = @winlostdate 
	
	 
	----------------------------------------------------------------------
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
			INNER JOIN @CommSetting as cs ON b.matchid = cs.matchid 
			 left join (
				select	refno,
						sum(case when bettype = 32 and liveawayscore =0 then 0 else stake*isnull(oddsspread,0) end) TOIBC,
						-sum((winlost - stake)*isnull(oddsspread,0)) WLIBC,
						sum(case when bettype = 32 and liveawayscore = 0 then 0 when bettype = 31 or (bettype = 32 and liveawayscore <> 0) then stake*(1 -tpositiontaking - isnull(oddsspread,0)) else 0 end) TOPhum
				from	bettransm with (nolock)
				group by refno
			 )bm on b.transid = bm.refno 
			 INNER JOIN #SportBettype s ON s.Bettype = b.bettype
			 left join (select custid FROM #DepSuper) dep ON b.srecommend = dep.custid
	WHERE	b.ruben = 1 
			and s.ProductID = 2
			and b.matchid >0
			and b.winlostdate = @winlostdate
			and b.statusID not in (101,102,103,121)	
	GROUP BY  case when dep.custid is null then 1 else 2 end
	---------------------------------------------------------------------------------------
 
	CREATE TABLE #Match (matchid INT, sporttype smallint, type varchar(10), primary key(matchid, type))
	INSERT INTO #Match 
	SELECT	m.matchid, 
			s.sporttype,
			m.type
	FROM (
			SELECT matchid, leagueid, exrisk, matchcode, 'match' as type FROM match WITH (NOLOCK) WHERE eventdate = @winlostdate
			UNION ALL
			SELECT orid, leagueid, 0, matchcode, 'outright' as type FROM outright WITH (NOLOCK) WHERE eventdate = @winlostdate
			)m	
	INNER JOIN league l WITH (NOLOCK) ON m.leagueid = l.leagueid	
	INNER JOIN Sports s WITH (NOLOCK) ON l.sporttype = s.sporttype 


	--------------------------------------------------------------------------------
	---1. Sportsbook only and outright
	INSERT INTO #src (srecommend ,site, SportType, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
					  Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, ProductId )
	SELECT	srecommend,
			1 AS site,
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype > 1 THEN 3 
				 WHEN s.IsSoccerMajor = 1 THEN 1 
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
			1 As ProductId   
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype  
		INNER JOIN #Match m ON b.matchid = m.matchid 		
	WHERE winlostdate = @winlostdate
		AND b.bettype < 19001
		AND b.statusID NOT IN (101,102,103,121) 
		AND b.ruben = 1	
		AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 
		AND s.productID = 1
		AND s.EventType IN (1,2)
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss') 
	GROUP BY srecommend,
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype > 1 THEN 3 
				 WHEN s.IsSoccerMajor = 1 THEN 1 
				 ELSE 2 
				 END


	------ BARM (site only)
	INSERT INTO #src (srecommend ,site, SportType, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
					  Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, ProductId )
	SELECT	2 AS srecommend,
			2 AS site,
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype > 1 THEN 3 
				 WHEN s.IsSoccerMajor = 1 THEN 1 
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
			1 As ProductId   
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype  
		INNER JOIN #Match m ON b.matchid = m.matchid   
	WHERE  b.recommend = 5707545 
		AND	b.winlostdate = @winlostdate
		AND b.bettype < 19001
		AND b.statusID NOT IN (101,102,103,121) 
		AND b.ruben = 1	
		AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 
		AND s.productID = 1
		AND s.EventType IN (1,2)
		AND s.SubProduct NOT IN ('MG-SuperLive','BT-Sold','BT-Bought','BT-Comm', 'BT-Winloss') 
	GROUP BY  
			CASE WHEN m.sporttype = 44 THEN 44 
				 WHEN m.Sporttype > 1 THEN 3 
				 WHEN s.IsSoccerMajor = 1 THEN 1 
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
			c.turnover_virtualrate = c.turnover_virtualrate - d.turnover_virtualrate
	FROM	#src c
	INNER JOIN #src d
		ON c.srecommend = d.srecommend
			AND c.SportType = d.SportType 
	WHERE  c.srecommend = 2 AND c.Site = 1 AND d.Site = 2
								 

 	---2. Not Sportsbook and not detail table yet
	INSERT INTO #src (srecommend ,site, SportType, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
					  Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, ProductId )
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
			CASE s.SubProduct
				WHEN 'MG-SuperLive' THEN -1
				WHEN 'BT-Comm' THEN -2
				WHEN 'BT-Winloss' THEN -2
				ELSE CASE
					    WHEN s.EventType = 0
						    AND ProductID = 1
					    THEN-3
					    ELSE s.ProductID
					END
			END AS ProductID
	FROM bettrans b WITH (NOLOCK)
		INNER JOIN #SportBettype s ON b.bettype = s.bettype
	WHERE winlostdate = @winlostdate
		AND b.bettype < 19001
		AND b.statusID NOT IN (101,102,103,121) 
		AND b.ruben = 1	
		AND (s.productID NOT IN (1,6,17,22,21) ---- OW RNG(6), Microgaming - RNG Casino (17), Voidbridge (22),  Allbet (21)	
			OR (s.productID = 1 AND s.SubProduct IN ('MG-SuperLive','BT-Comm', 'BT-Winloss')) ---Metric Gaming - Superlive , Bettrade
			OR (s.productID = 1 AND s.EventType = 0 ) ----Palay
			)	
	GROUP BY srecommend ,
	   CASE s.SubProduct
		  WHEN 'MG-SuperLive' THEN -1
		  WHEN 'BT-Comm' THEN -2
		  WHEN 'BT-Winloss' THEN -2
		  ELSE CASE
				 WHEN s.EventType = 0
					 AND ProductID = 1
				 THEN-3
				 ELSE s.ProductID
			  END
	   END
  
	-- Get from Datail table  
	-- Get bettransRNG data
	
	INSERT INTO #srcDetail (srecommend ,site , winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
							Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, ProductId )
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
			s.ProductID
	FROM bettransRNG b WITH(NOLOCK)
		INNER JOIN #SportBettype s ON b.gameid = s.bettype	
	WHERE winlostdate = @winlostdate
		AND s.ProductID IN (6,17,22) 	---- OW RNG(6), Microgaming - RNG Casino (17), Voidbridge (22)
		AND b.statusID NOT IN (0, 1, 101,102,103,121)
	GROUP BY b.srecommend, s.ProductID
			 
	 	 
	-- Get bettransLC Data
	INSERT INTO #srcDetail (srecommend ,site, winlost_actualrate , winlost_virtualrate , position_actualrate , position_virtualrate , commission_actualrate , commission_virtualrate , 
							Linetotal_actualrate , Linetotal_virtualrate , turnover_actualrate , turnover_virtualrate, ProductId)
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
			s.ProductID
	FROM bettransLC b WITH(NOLOCK)	
		INNER JOIN #SportBettype s ON b.gameid = s.bettype
	WHERE winlostdate = @winlostdate		
		AND s.ProductID = 21  ---- AllBet (21)
		AND b.statusID NOT IN (0, 1, 101,102,103,121)
	GROUP BY
			b.srecommend, s.ProductID
			 
	-------------------------------------------------------

	UPDATE	#src
	SET		site = 2
	WHERE 	srecommend IN (SELECT CustId FROM  #DepSuper)
	
	UPDATE	#srcDetail
	SET		site = 2
	WHERE 	srecommend IN (SELECT CustId FROM  #DepSuper)  
	
	-------------------------------------------------------		 
	--Section 2: all products that enable virtual currency, DisplayOrder field:	1 -> 100

	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			CASE WHEN b.sporttype IN (3,44) THEN 4 
				 WHEN b.Sporttype = 1 THEN 1 
				 WHEN b.Sporttype = 2 THEN 2
				 END as DisplayOrder,
			CASE WHEN b.sporttype IN (3,44) THEN 'Other Sports' 
				 WHEN b.sporttype = 1 THEN 'Soccer-Major Bet Types' 
				 WHEN b.sporttype = 2 THEN 'Soccer-Minor Bet Types' 
				 END AS SportName,
			CASE WHEN b.sporttype IN (3,44) THEN 3 ELSE b.sporttype END as SportType,						
			0 ibc,
			site,
			SUM(winLost_virtualrate) AS winlost,
			SUM(position_virtualrate) AS Position,
			SUM(commission_virtualrate) AS Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(Linetotal_virtualrate) AS VirtualLineTotal,
			SUM(turnover_actualrate) AS RealTurnover,
			SUM(turnover_virtualrate) AS VirtualTurnover,
			1 EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate* e.ExtraPT END) AS ExtraPT,
			1 ProductID
	FROM	#src b		
		LEFT JOIN #ExtraPT_Sel e 
			ON  b.srecommend = e.superID 
			AND e.ProductID = b.ProductId 			
			AND e.Sporttype = CASE WHEN b.sporttype = 44 THEN 44 ELSE 0 END
			AND e.SubProduct = ''  			
	WHERE	b.ProductId = 1
	GROUP BY		
			CASE WHEN b.sporttype IN (3,44) THEN 4 
				 WHEN b.Sporttype = 1 THEN 1 
				 WHEN b.Sporttype = 2 THEN 2
				 END ,
			CASE WHEN b.sporttype IN (3,44) THEN 'Other Sports' 
				 WHEN b.sporttype = 1 THEN 'Soccer-Major Bet Types' 
				 WHEN b.sporttype = 2 THEN 'Soccer-Minor Bet Types' 
				 END,
			CASE WHEN b.sporttype IN (3,44) THEN 3 ELSE b.sporttype END,				
			site 		
	 	

	-- Get win lost of agent '8RM' , 'BARM'
	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			case when m.sporttype> 1 THEN 4 ELSE 1 end as DisplayOrder,
			case when m.sporttype> 1 then 'Other Sports' else 'Soccer' end as SportName,
			case when m.sporttype> 1 then 3 else 1 end as SportType,	
			CASE b.recommend WHEN  52466 THEN 1 
							 WHEN 5707545 THEN 2 
				END AS ibc,
			0 as site,
			-sum(winlost-actual_stake) WinLost,
			-sum(awinlost+mwinlost+swinlost) Position,
			sum(scomm) Commission,	
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) RealLineTotal,
			-sum(winlost - actual_stake + awinlost + mwinlost + swinlost + scomm) VirtualLineTotal,
			-sum((1-tpositiontaking)*ABS(stake)) RealTurnover,
			-sum((1-tpositiontaking)*ABS(stake)) VirtualTurnover,
			0 EnableVirtual,
			0 ExtraPT,
			1 ProductID 
	FROM	bettrans b WITH (NOLOCK)
		INNER JOIN #Match m on b.matchid = m.matchid	
	WHERE	b.winlostdate = @winlostdate
			AND b.matchid > 0 
			AND b.bettype < 19001
			AND b.statusID NOT IN (101,102,103) 
			AND b.ruben = 1	
			AND b.recommend IN (52466, 5707545)
			AND m.type = CASE WHEN b.bettype = 10 THEN 'outright' ELSE 'match' END 
	GROUP BY	
			case when m.sporttype> 1 THEN 4 ELSE 1 end,
			case when m.sporttype> 1 then 'Other Sports' else 'Soccer' end,
			case when m.sporttype> 1 then 3 else 1 end ,
			CASE b.recommend WHEN  52466 THEN 1 
							 WHEN 5707545 THEN 2 
				END	

	
	----METRIC GAMING -SUPER LIVE
	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			3,'Metric Gaming - Superlive', -1, 0, site,
			SUM(ISNULL(b.winlost_virtualrate,0)) WinLost,
			SUM(ISNULL(b.position_virtualrate,0)) Position,
			SUM(ISNULL(commission_virtualrate,0)) Commission,	
			SUM(ISNULL(LineTotal_actualrate,0)) AS RealLineTotal,
			SUM(ISNULL(Linetotal_virtualrate,0)) as VirtualLineTotal,	
			SUM(ISNULL(turnover_actualrate,0)) RealTurnover,
			SUM(ISNULL(turnover_virtualrate,0)) VirtualTurnover,
			1 EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate*e.ExtraPT END) AS ExtraPT ,
			b.ProductID  
	FROM	#src b		
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID 	
		AND b.ProductId = -1 
		AND e.ProductID = 1		
		AND e.Sporttype = 0 
		AND e.SubProduct = 'MG-SuperLive'
	WHERE b.ProductId = -1
	GROUP BY site, b.ProductID 

			 
	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT 
			5,'Parlay', 99, 0, site,
			SUM(winlost_virtualrate) WinLost,
			SUM(position_virtualrate) Position,
			SUM(commission_virtualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(Linetotal_virtualrate) AS VirtualLineTotal,	
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			1 EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate*e.ExtraPT END) AS ExtraPT,
			b.ProductID 			
	FROM	#src b
		LEFT JOIN #ExtraPT_Sel e 
			ON  b.srecommend = e.superID 
			AND b.ProductID = -3
			AND e.ProductID = 1 		
			AND e.Sporttype = 0
			AND e.SubProduct = ''
	WHERE	b.ProductID = -3	
	GROUP BY site, b.ProductID 

	----NUMBER GAME			
	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			6,'Number Game', 161, 0, site,
			SUM(winlost_virtualrate) WinLost,
			SUM(position_virtualrate) Position,
			SUM(commission_virtualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(Linetotal_virtualrate) AS VirtualLineTotal,	
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			1 EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate*e.ExtraPT END) AS ExtraPT, 
			b.ProductId 
	FROM	#src b			
	LEFT JOIN #ExtraPT_Sel e 
			ON  b.srecommend = e.superID 
			AND b.ProductID = e.ProductId			
	WHERE	b.ProductId = 3		
	GROUP BY site, b.ProductId


	--------------------------------------------------------------------------------
	--Section 1: all products that disable virtual currency, DisplayOrder field:	101 -> 200
	/*
	Display order for gaming
		--102. Live Casino: SLI (4), AG Casino (11), Gold Deluxe (12), Microgaming - Live casino (13), AllBet (21)
		--103. Casino:  OW RNG(6), Macau (14),  Microgaming - RNG Casino (17), Voidbridge (22)
		--104. Virtual Sports
		--105. Keno
		--106. Racing
		--107. Bettrade
		--108. Colosuss Bets
	*/

	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT	106,
			'Racing', 
			151, 
			0, 
			site,
			WinLost,
			Pos Position,
			Comm Commission,
			LineTotal AS RealLineTotal,
			LineTotal AS VirtualLineTotal,
			turnover RealTurnover,
			0 VirtualTurnover,
			0 EnableVirtual,
			0 ExtraPT,
			2 AS ProductId  
	FROM @RBWinlost

	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			107,'Bettrade', -2, 0, site,
			SUM(ISNULL(b.winlost_actualrate,0)) WinLost,
			SUM(ISNULL(b.position_actualrate,0)) Position,
			0 AS Commission,	
			SUM(ISNULL(LineTotal_actualrate,0)) AS RealLineTotal,
			SUM(ISNULL(LineTotal_actualrate,0)) as VirtualLineTotal,	
			0 AS RealTurnover,
			0 AS VirtualTurnover,
			0 AS EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate*e.ExtraPT END) AS ExtraPT,  
			b.ProductId
	FROM	#src b
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID
			AND b.ProductId = -2
			AND e.ProductId = 1 
			AND e.Sporttype = 0
			AND e.SubProduct IN ('BT-Comm', 'BT-Winloss')
	WHERE	b.ProductId = -2
	GROUP BY site, b.ProductId

	------------------------------------------
	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			101,'', 0, 0, site,
			SUM(winlost_actualrate) WinLost,
			SUM(position_actualrate) Position,
			SUM(commission_actualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(LineTotal_virtualrate) AS VirtualLineTotal,
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			0 EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate*e.ExtraPT END) AS ExtraPT,
			CASE WHEN b.ProductId IN (14) THEN 6   ---- Casino
				ELSE CASE WHEN  b.ProductId IN (4,11,12,13) THEN 4  ---Live Casino
					ELSE b.ProductId END END AS ProductId  
	FROM	#src b		
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID 
			AND e.ProductID = b.ProductId	
	WHERE	b.ProductId IN (5,8,15) ---Virtual Sports, Keno, Colosuss Bets
			OR b.ProductId IN (4,11,12,13)    -----SLI, AG Casino, Gold Deluxe, MGC Live casino
			OR b.ProductId IN (14) --- Macau
	GROUP BY site, CASE WHEN b.ProductId IN (14) THEN 6   ---- Casino
						ELSE CASE WHEN  b.ProductId IN (4,11,12,13) THEN 4  ---Live Casino
							ELSE b.ProductId END END 
	 
	INSERT INTO #Result (DisplayOrder,SportName, SportType, ibc, site, winlost, Position, Commission, RealLineTotal, VirtualLineTotal, RealTurnover, VirtualTurnover, EnableVirtual, ExtraPT, ProductId )
	SELECT
			101,'', 0, 0, site,
			SUM(winlost_actualrate) WinLost,
			SUM(position_actualrate) Position,
			SUM(commission_actualrate) Commission,	
			SUM(LineTotal_actualrate) AS RealLineTotal,
			SUM(LineTotal_virtualrate) AS VirtualLineTotal,
			SUM(turnover_actualrate) RealTurnover,
			SUM(turnover_virtualrate) VirtualTurnover,
			0 EnableVirtual,
			SUM(CASE ISNULL(e.ExtraPT,0) WHEN 0 THEN 0 ELSE winlost_actualrate*e.ExtraPT END) AS ExtraPT,
			CASE WHEN b.ProductId IN (6,17,22) THEN 6  --- Casino
				ELSE 4	--- Live Casino
				END AS ProductId
	FROM	#srcDetail b			
	LEFT JOIN #ExtraPT_Sel e 
		ON  b.srecommend = e.superID 
			AND e.ProductID = b.ProductId	
	WHERE	b.ProductId IN (21)    ----Allbet
			OR  b.ProductId IN (6,17,22) --- OW RNG + Microgaming - RNG Casino, Voidbridge
	GROUP BY site, CASE WHEN b.ProductId IN (6,17,22) THEN 6  --- Casino
						ELSE 4	--- Live Casino
						END 

	--------------------------------------------
	----Get Result----
	/*
	Display order for gaming
		--102. Live Casino: SLI (4), AG Casino (11), Gold Deluxe (12), Microgaming - Live casino (13), AllBet (21)
		--103. Casino:  OW RNG(6), Macau (14),  Microgaming - RNG Casino (17), Voidbridge (22)
		--104. Virtual Sports
		--105. Keno
		--106. Racing
		--107. Bettrade
		--108. Colosuss Bets
	*/
	
	DECLARE @ProductOrder AS TABLE (						
						DisplayOrder	INT,
						ProductId		INT,
						SportName		NVARCHAR(50),
						SportType		SMALLINT
						)
	
	INSERT INTO @ProductOrder (DisplayOrder, ProductId,SportName, SportType)
	VALUES 	
	 (102, 4, 'Live Casino', 162)
	,(103, 6, 'Casino', 251)
	,(104, 5, 'Virtual Sports', 180)
	,(105, 8, 'Keno', 202)
	,(108, 15,'Colossus Bets', 204)

	UPDATE	R
	SET		DisplayOrder = P.DisplayOrder,
			SportName = P.SportName,
			Sporttype = P.Sporttype
	FROM	#Result R
	INNER JOIN @ProductOrder P
			ON P.ProductID = R.ProductId
	

	SELECT	DisplayOrder, SportName, SportType, ibc, site, 
			SUM (winlost) AS winlost, 
			SUM (Position) AS Position, 
			SUM (Commission) AS Commission, 
			SUM (RealLineTotal) AS RealLineTotal, 
			SUM (VirtualLineTotal) AS VirtualLineTotal, 
			SUM (RealTurnover) AS RealTurnover, 
			SUM (VirtualTurnover) AS VirtualTurnover, 
			SUM (EnableVirtual) AS EnableVirtual, 
			SUM (ExtraPT) AS ExtraPT, 
			ProductId
	FROM	#Result
	GROUP BY DisplayOrder, SportName, SportType, ibc, site, ProductId
	ORDER BY DisplayOrder asc, ibc, site	

					
	DROP TABLE #src
	DROP TABLE #srcDetail
	DROP TABLE #DepSuper
	DROP TABLE #ExtraPT_Sel
	DROP TABLE #Match
	DROP TABLE #Result
	
END
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_Sporttype] TO [vnteam]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_Sporttype] TO [bodbAdminNet]
GO