/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
 
ALTER PROCEDURE [dbo].[Acc_Rpt_BetCount_ByProduct_Super]
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME,
	@CustID			INT,
	@SportType		INT
AS  
/*  Created: Dominic 
	Date: 2014-06-02  
    Task : Total settled/running bets count per Product by super within current month
    DB: DBAGE/bodb02  
   
    Revisions:  
		- 20140701@Dominic: Get running Keno bets from table Translog
		- 20150617@Elodie: Migrate CustDB to DBCUST (call CustGameType by link server DBACC)
		- 20150828@Jim: support GoldDeluxe & Metric Gaming(#40262)
		- 20150828@Jim: support Colossus Bet (#42608)
		- 20151215@Percy: suport Cockfighting [Redmine: #49027]
		- 20160108@Percy: Add new range bettype for Casino [Redmine: #49134]
		- 20160203@Sophia:	. Change the way to get report 
							. Apply RNG Casino [Redmine: #49134]
							. Appy Metric gaming - Superlive
		- 20160229@Jim: Offer Allbet [Redmine #50921]
		- 20160407@Sophia: Fix bug low performance - need to call Openquery [redmine: #55623]
		- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
		- 20160916@Robert:
			1. Integrate new product NG2 [RedmindID: #63460]
			2. Clean code of Cockfighting
		- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]  
		- 20170627@Cherry: Integrate Lottery and Betradar Virtual Sports (#78184, 78495)
		- 20170808@Cherry: Integrate RNG Tablet Games (#78424)
		- 20170825@Cherry: Integrate Lucky 3 (#78214)
		- 20171030@Kean: Integrate Bullfighting (#85712)
		- 20171110@Kean: Should count the running tickets from translogs table (#86319)
		- 20171113@Kean:  (#86319) Include GoldDeluxe for counting of running tickets from translog table(#86319)
		- 2018.03.19@Franklin: Integrate  ONE RNG Jackpot (#91712)
		- 20180411@Franklin: Integrate Pragmatic (#92642)
		- 20180816@Cherry: Integrate Poker Games (#97830)
		- 20181219@Robert: NAP Report - Add new sporttype for Happy 5 (#104253) 
		- 20190128@Robert: Video Poker - Integrate into NAP Reports[#107706]
		- 20190308@Robert: #109822 - NAP Report - Integrate Bet Builder
		- 20190722@Robert: #117010 - NAP Report - Integrate Card Club on NAP Report
	Param's Explanation:  
	  + @MoveBetsDay: The day of moving bets to battrans14
	  + @BalanceUpDay: The day of moving bets to battransbk
	  + @CustID: SuperID
	  + {251: Casino (include : 251, 208, 209, 210), 151:Racing, 252:Bingo, 161:Number Game, 162:Live Casino, 180:Virtual Sports, 202:Keno,  -1 : Metric Gaming - Superlive}
			220: Lottery, 160: Lucky 3, 207: Bullfighting, 163: Poker Games
  
*/  
BEGIN
	SET NOCOUNT ON
	
	DECLARE @CurrentDate SMALLDATETIME
	DECLARE @FirstDate SMALLDATETIME
	DECLARE @TempFromDate SMALLDATETIME
	DECLARE @TempToDate SMALLDATETIME
			
	--Table of Super/master/Member that belong to real super above	
	CREATE TABLE #FiltedDownlineAcc(
		CustID		INT,
		IsDisable	BIT,
		BetStatus	NVARCHAR(10), 
		BetCount	INT
		)
		
	--Table of member that played bet within current month	
	CREATE TABLE #AvailableMember(CustID INT, BetStatus NVARCHAR(10), BetCount INT)	
	
	SELECT @CurrentDate = CAST(GETDATE() AS DATE)
	SELECT @FirstDate = CONVERT(VARCHAR(25),DATEADD(dd,-(DAY(@CurrentDate)-1),@CurrentDate),101)   --- First date of the month
    
    --Get running Keno, Colossus Bet, Bullfighting, Lottery, GoldDeluxe, MG-Superlive
    IF @sportType IN (202,204,207,220,255,-1)                       
    BEGIN
		INSERT INTO #AvailableMember
		SELECT tl.custid,tl.[status],COUNT(1) 
		FROM dbo.translog tl WITH(NOLOCK)
		WHERE (tl.productID IN (202,204,207,220,255)
			  OR tl.GameID BETWEEN 801 AND 806
			)
			AND tl.srecommend = @CustID
			AND tl.StatusId = 0 
		GROUP BY tl.custid,tl.[status]
    END
    
    
    -- Get data from bettrans
	IF @CurrentDate > @MoveBetsDay
	BEGIN
		IF @FirstDate <= @MoveBetsDay 
			SET @TempFromDate =  DATEADD(DAY,1,@MoveBetsDay)
		ELSE
			SET @TempFromDate = @FirstDate
			
		INSERT INTO #AvailableMember
		SELECT b.custid,b.[status],
				CASE WHEN b.bettype BETWEEN 1401 AND 1499 THEN SUM(b.betid) ELSE COUNT(1) END BetCount
		FROM dbo.bettrans b WITH(NOLOCK)
		WHERE b.winlostdate BETWEEN @TempFromDate AND @CurrentDate
		AND (
			b.bettype BETWEEN 31 AND CASE WHEN @sportType=151 THEN 49 ELSE 0 END
			OR b.bettype BETWEEN 81 AND (CASE WHEN @sportType=161 THEN 120 ELSE 0 END)
			OR b.bettype BETWEEN 8101 AND (CASE WHEN @sportType=161 THEN 8120 ELSE 0 END)
			OR b.bettype BETWEEN 1101 AND (CASE WHEN @sportType=162 THEN 1199 ELSE 0 END)			
			OR b.bettype BETWEEN 801 AND (CASE WHEN @sportType= -1 AND b.StatusID <> 0 THEN 806 ELSE 0 END)
			OR b.bettype BETWEEN 1501 AND (CASE WHEN @sportType=202 AND b.StatusID <> 0 THEN 1599 ELSE 0 END)
			OR b.bettype BETWEEN 73 AND (CASE WHEN @sportType= 252 THEN 73 ELSE 0 END)
			OR b.bettype BETWEEN 1701 AND (CASE WHEN @sportType= 255 THEN 1703 ELSE 0 END) -- GoldDeluxe
			OR b.bettype BETWEEN 18000 AND (CASE WHEN @sportType= 204 THEN 18005 ELSE 0 END) -- Colossus Bet
			OR b.bettype BETWEEN 2501 AND (CASE WHEN @SportType = 213 AND b.StatusID <> 0 THEN 2699 ELSE 0 END) -- NG2	
			OR b.bettype BETWEEN 1021 AND CASE WHEN @sportType = 220 THEN 1049 ELSE 0 END --Loterry
			OR (@sportType=180 AND (b.bettype BETWEEN 1201 AND 1299 OR b.bettype BETWEEN 2700 AND 2899)) --Virtual Sports and Betradar Virtual Sports	
			OR b.bettype BETWEEN 1600 AND CASE WHEN @sportType = 160 THEN 1610 ELSE 0 END --Lucky 3
			OR (@sportType = 207 AND b.bettype = 1004) --Bullfighting
			OR b.bettype BETWEEN 1401 AND CASE WHEN @sportType = 163 THEN 1499 ELSE 0 END --Poker Games			
		) 
		AND ( 
				----b.status IN ('WON','LOSE','DRAW','running') 
				b.statusId IN (111,112,113,0) 
			)	
		AND b.srecommend = @CustID
		AND b.bettype NOT IN (38)
		GROUP BY b.custid,b.[status], b.bettype
		
		-- Get data from bettransRnG
		IF @sportType IN (251, 212, 219, 163)
		BEGIN
			INSERT INTO #AvailableMember
			SELECT b.custid,
					b.[status],
					COUNT(1) BetCount
			FROM dbo.bettransRNG b WITH(NOLOCK)
			WHERE b.winlostdate BETWEEN @TempFromDate AND @CurrentDate
			AND (
					(@sportType=251 AND (b.gameID BETWEEN 2101 AND 2399 OR b.gameID BETWEEN 2901 AND 2999))
					OR b.gameID BETWEEN 4001 AND CASE WHEN @sportType=212 THEN 4300 ELSE 0 END 	--Macau Games and Pragmatic
					OR b.gameID BETWEEN 1011 AND CASE WHEN @sportType=219 THEN 1020 ELSE 0 END -- Fishing World			
					OR b.gameID BETWEEN 1901 AND CASE WHEN @sportType=212 THEN 1999 ELSE 0 END -- Card Club [Video Poker]					
				) 
			AND (
					b.statusId IN (111,112,113,0) 
				)	
			AND b.srecommend = @CustID
			AND b.gameID NOT IN (2198, 2398, 2998, 2199, 2399, 2999)
			GROUP BY b.custid,b.[status]
		END	

		-- Get data from bettransLC
		IF @sportType IN (211)
		BEGIN
			INSERT INTO #AvailableMember
			SELECT b.custid,b.[status],COUNT(1) 
			FROM dbo.bettransLC b WITH(NOLOCK)
			WHERE b.winlostdate BETWEEN @TempFromDate AND @CurrentDate
			AND (
					b.gameID BETWEEN 2401 AND CASE WHEN @sportType=211 THEN 2499 ELSE 0 END 	
				) 
			AND (
					b.statusId IN (111,112,113,0) 
				)	
			AND b.srecommend = @CustID
			GROUP BY b.custid,b.[status]
		END
	END

	--Get data from bodb_account.dbo.mcCustBettingDaily
	IF @FirstDate <= @MoveBetsDay
	BEGIN
		IF @CurrentDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @CurrentDate

		DECLARE @sql VARCHAR(MAX) 
		SET @sql = 	'
				SELECT * FROM  OPENQUERY ( DBWH ,''
				SELECT b.custid,''''SETTLED'''',SUM(b.BetCount)
				FROM bodb_account.dbo.mcCustBettingDaily b WITH (NOLOCK)					 
				WHERE	b.rptDate BETWEEN '''''+ CONVERT(VARCHAR(10),@FirstDate, 121)+ ''''' AND '''''+  CONVERT(VARCHAR(10),@TempToDate, 121)  + '''''
						AND 
						(
							b.bettype BETWEEN 31 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' =151 THEN 49 ELSE 0 END
							OR b.bettype BETWEEN 81 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' =161 THEN 120 ELSE 0 END)
							OR b.bettype BETWEEN 8101 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' =161 THEN 8120 ELSE 0 END)
							OR b.bettype BETWEEN 1101 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' =162 THEN 1199 ELSE 0 END)
							OR (' + CONVERT(VARCHAR(5),@sportType) +' = 251 AND (b.bettype BETWEEN 2101 AND 2399 OR b.bettype BETWEEN 2901 AND 2999)) --RNG Casino
							OR b.bettype BETWEEN 801 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = -1 THEN 806 ELSE 0 END)
							OR b.bettype BETWEEN 1501 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' =202 THEN 1599 ELSE 0 END)
							OR b.bettype BETWEEN 73 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 252 THEN 73 ELSE 0 END)
							OR b.bettype BETWEEN 1701 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 255 THEN 1703 ELSE 0 END) -- GoldDeluxe
							OR b.bettype BETWEEN 18000 AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 204 THEN 18005 ELSE 0 END) -- Colossus Bet
							OR b.bettype BETWEEN 2401  AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 211 THEN 2499 ELSE 0 END) -- AllBet
							OR b.bettype BETWEEN 4001  AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 212 THEN 4300 ELSE 0 END) -- Macau Games and Pragmatic
							OR b.bettype BETWEEN 2501  AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 213 THEN 2699 ELSE 0 END) -- NG2
							OR b.bettype BETWEEN 1011  AND (CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +'  = 219 THEN 1020 ELSE 0 END) -- Fishing World
							OR b.bettype BETWEEN 1021 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 220 THEN 1049 ELSE 0 END --Loterry
							OR (' + CONVERT(VARCHAR(5),@sportType) +' =180 AND (b.bettype BETWEEN 1201 AND 1299 OR b.bettype BETWEEN 2700 AND 2899)) --Virtual Sports		
							OR b.bettype BETWEEN 1600 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 160 THEN 1610 ELSE 0 END --Lucky 3
							OR (' + CONVERT(VARCHAR(5),@sportType) +' = 207 AND b.bettype = 1004) --Bullfighting	
							OR b.bettype BETWEEN 1401 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 163 THEN 1499 ELSE 0 END --Poker Games			
							OR b.bettype BETWEEN 1901 AND CASE WHEN ' + CONVERT(VARCHAR(5),@sportType) +' = 165 THEN 1999 ELSE 0 END --Card Club [Video Poker]							
						) 
						AND b.bettype NOT IN (38)
						AND b.status IN (3  ---DRAW
										,12	---HALF LOSE
										,13	---HALF WON
										,4	---LOSE
										,8	---WON								 
										)	
						AND CustID IN ( 
										SELECT	CustID 
										FROM	bodb02.dbo.CustInfo WITH(NOLOCK)
										WHERE	srecommend = '+ CONVERT(VARCHAR(50),@CustID) +' AND RoleID = 1 )
						GROUP BY b.custid '' )'		 
		
				
		INSERT INTO #AvailableMember 
		EXEC (@sql)	
	END
	
	--Get data for downline list 
    IF @sportType = 151
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			(ci.Disable151_AU & ci.Disable152_AU & ci.Disable152_UK & ci.Disable153_AU & ci.DisableHorseRacing & ci.DisableOpenTote),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid                 
	END
	IF @sportType IN (161)
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			ci.DisableNumber,
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid                  
	END
	IF @sportType = 162
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			(~ci.SyncLiveCasino | ci.DisableLiveCasino),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid               
	END
	IF @sportType IN (-1,255,204)
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			CASE WHEN @sportType = -1  THEN  ci.DisableSuperLive
				 WHEN @sportType = 255 THEN  ci.DisableGoldDeluxe
				 WHEN @sportType = 204 THEN  ci.DisableColossusBet
				 END ,
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid               
	END
	IF @sportType IN (251) -----251, 208, 209, 210
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			(~ci.SyncCasino |(ci.DisableCasino)),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid             
	END
	IF @sportType = 252
    BEGIN            
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
			(~ci.SyncBingo | ci.DisableBingo),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid                   
	END
	IF @sportType = 202
    BEGIN      
		WITH CustEnableKeno (CustID)
		AS(
			SELECT gt.CustID
			FROM DBACC.bodb02.dbo.CustGameType gt WITH (NOLOCK) 
				JOIN #AvailableMember av ON av.CustID = gt.CustID
			WHERE gt.IsDisabled = 0
			GROUP BY gt.CustID
		)
		INSERT INTO #FiltedDownlineAcc
		SELECT av.custid,
			0,
			av.BetStatus,
			av.BetCount
		FROM #AvailableMember av              
			INNER JOIN CustEnableKeno ce ON ce.CustID = av.custid    
		UNION ALL
		SELECT av.custid,
			1,
			av.BetStatus,
			av.BetCount
		FROM #AvailableMember av              
			LEFT JOIN CustEnableKeno ce ON ce.CustID = av.custid    
		WHERE ce.CustID IS NULL
	END
	IF @sportType IN (211,212,213,219,220,180,160,207,163)
    BEGIN
		DECLARE @bitmapOrder TABLE (bitmapOrder TINYINT)
		INSERT INTO @bitmapOrder (bitmapOrder)
		SELECT bitmapOrder 
		FROM dbo.ProductStatusProfile WITH(NOLOCK) 
		WHERE Sporttype = @SportType 
	    
		INSERT INTO #FiltedDownlineAcc
		SELECT ci.custid,
				(SELECT CASE MIN(CONVERT(INT, f.value)) WHEN 0 THEN 0 ELSE 1 END
			FROM CustProductStatus cps WITH(NOLOCK)
				CROSS APPLY @bitmapOrder b
				CROSS APPLY f_CustSetting_ProductStatusSel(cps.bitmapIsDisabled, b.bitmapOrder) f
			WHERE custid = ci.custid),
			av.BetStatus,
			av.BetCount
		FROM dbo.custInfo ci WITH(NOLOCK)
		JOIN #AvailableMember av ON av.CustID = ci.custid                   
	END
	
	--Return result
	SELECT cs.custid,cs.username,rs.IsDisable,
			SUM(CASE WHEN rs.BetStatus <> 'running' THEN rs.BetCount ELSE 0 END) SettledBets,
			SUM(CASE WHEN rs.BetStatus = 'running' THEN rs.BetCount ELSE 0 END)  RunningBets
	FROM #FiltedDownlineAcc rs
	JOIN dbo.Customer cs ON cs.custid = rs.CustID
	GROUP BY cs.custid,cs.username,rs.IsDisable
	ORDER BY cs.username
	
	--Drop temp tables
	DROP TABLE #FiltedDownlineAcc
	DROP TABLE #AvailableMember

END
GO 

GRANT EXECUTE ON [dbo].[Acc_Rpt_BetCount_ByProduct_Super] TO [bodbAdminNet]
GO
