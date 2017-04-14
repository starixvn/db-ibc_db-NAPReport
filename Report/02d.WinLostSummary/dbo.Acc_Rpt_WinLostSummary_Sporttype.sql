USE [bodb_Report]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_WinlostSummary_Sporttype]
    @fromdate   DATETIME,
    @todate     DATETIME    
AS
    /*
        Created: Johnson
        Date: 2013-06-20
        Task: summary winlost by sporttype
        DB: DBRPT/bodb_Report
        
        Revisions:
            - 20130822@Johnson: change to use rptWinlost instead rptWinlost2
            - 20131206@Kathy: Add HR Fixed Odds (154) [Redmine:#6505]
			- 20140327@Dom: Add Keno
			- 20150525@Jim: apply sport& bettype matrix and also support GoldDeluxe & Metric Gaming (#35359 & #28309 )
			- 20150710@Jim: Super Balance fix and Microgaming integration (feature #38168 )
			- 20150723@Jim: Apply Bettrade [#38815]
			- 20150828@Jim: support Colossus Bet (#42608)
			- 20150921@Jim: support MO (#41935)
			- 20151020@Sophia: Fix bug missing Outright data [#30661]
			- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
			- 20151210@Percy: Add new product: Cockfighting Sabong [Redmine: #49027]
			- 20160112@Percy: Expand new bettype for RNG Casino [Redmine: #49134]
			- 20160225@Jim: offer  Allbet Live Casino [Redmine:#50921)]
			- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model, using sporttype, bettye matrix function, change the way to get data Microgaming-RNG Casino from bettransRNG instead bettrans [RedmineID: #55589]
			- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
			- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
			- 20160913@Percy: [RedmineID: #59840]
				1. Include hedge match of 8RM account 
				2. Left join #TempMatch to include data bettrade
			- 20160916@Robert: Integrate new product NG2 [RedmindID: #63460]
			- 20161129@Robert: NAP Reports - Integrate Fishing World Product [RedmindID: #67757]
        Parameter's Explanation:
    */
BEGIN
	SET NOCOUNT ON
	----Get Sport Bettype Matrix------
	DECLARE @isTest BIT= 0;
     SELECT @isTest = dbo.f_CheckSPVersion(@@PROCID);
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500),SortKey TINYINT,liveindicator BIT)
	INSERT INTO @SportBettype (ProductID  , Bettype  ,EventType ,SubProduct )
	SELECT ProductID,
            Bettype,
            EventType,
            SubProduct
     FROM bodb02.dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest);

	UPDATE @SportBettype
	SET liveindicator =0
	
	INSERT INTO @SportBettype(ProductID,Bettype,EventType,SubProduct,liveindicator)
	SELECT ProductID
		 ,Bettype
		 ,EventType
		 ,SubProduct
		 ,1 AS liveindicator
	FROM @SportBettype
	WHERE liveindicator =0	
	
	UPDATE @SportBettype
	SET SortKey = CASE  WHEN Bettype =1   AND liveindicator =0   THEN 1
						WHEN Bettype =301 AND liveindicator =0   THEN 2
						WHEN Bettype =1   AND liveindicator =1   THEN 3
						WHEN Bettype =301 AND liveindicator =1   THEN 4
						WHEN Bettype =3   AND liveindicator =0   THEN 5
						WHEN Bettype =302 AND liveindicator =0   THEN 6
						WHEN Bettype =3   AND liveindicator =1   THEN 7
						WHEN Bettype =302 AND liveindicator =1   THEN 8
						WHEN Bettype =7   AND liveindicator =0   THEN 9
						WHEN Bettype =303 AND liveindicator =0   THEN 10
						WHEN Bettype =7   AND liveindicator =1   THEN 11
						WHEN Bettype =303 AND liveindicator =1   THEN 12
						WHEN Bettype =8   AND liveindicator =0   THEN 13
						WHEN Bettype =304 AND liveindicator =0   THEN 14
						WHEN Bettype =8   AND liveindicator =1   THEN 15
						WHEN Bettype =304 AND liveindicator =1   THEN 16
						ELSE 17
						END
	
	DECLARE @_fromdate    DATETIME,
			@_todate      DATETIME

	SELECT @_fromdate = @fromdate,
			@_todate = @todate

    CREATE TABLE #TempMatch (matchid int, matchcode varchar(50))
    CREATE TABLE #TempData (sporttype int, 
							bettype int, 
							liveindicator bit, 
							ibc int, 
							IsHedge bit, 
							status varchar(10),
							OrderKey tinyint,
							SortKey tinyint,
							realWinlost money, 
							realPosition money,
							realCommission money, 
							realLineTotal money, 
							virtualLineTotal money, 
							realTurnover money, 
							virtualTurnover money
							)

    DECLARE @movebetdate datetime,
			@balanceupdate datetime,
			@f_date datetime,
			@t_date datetime
    
        SELECT 
            TOP 1 @balanceupdate = winlostdate
        FROM bodb02.dbo.Bettrans WITH(NOLOCK)
        WHERE bettype = 20000 and matchid = 0 and custid = 3
    
        SELECT         
            @movebetdate = max(eventdate) 
        FROM  bodb02.dbo.match14 WITH(NOLOCK)
            
        IF @_todate > @movebetdate
        BEGIN
            IF @_fromdate < @movebetdate
                SELECT @f_date = @movebetdate
            ELSE
                SELECT @f_date = @_fromdate
            
            SELECT @t_date = @_todate
        
            INSERT INTO #TempMatch
            SELECT m.matchid,m.matchcode FROM bodb02.dbo.match(nolock) m WHERE m.eventdate BETWEEN @f_date AND @t_date
			UNION ALL 
			SELECT m.orid as matchid, m.matchcode FROM bodb02.dbo.Outright(nolock) m WHERE m.eventdate BETWEEN @f_date AND @t_date
        END

        IF @_fromdate <=@movebetdate
        BEGIN
            IF @_todate < @movebetdate
                SELECT @t_date = @_todate
            ELSE
                SELECT @t_date = @movebetdate
            
            SELECT @f_date = @_fromdate

            INSERT INTO #TempMatch
            SELECT m.matchid,m.matchcode FROM bodb02.dbo.match14(nolock) m WHERE m.eventdate BETWEEN @f_date AND @t_date
			UNION ALL 
			SELECT m.orid as matchid, m.matchcode FROM bodb02.dbo.Outright14(nolock) m WHERE m.eventdate BETWEEN @f_date AND @t_date
        END
        IF @_fromdate <@balanceupdate
        BEGIN
            IF @_todate < @balanceupdate
                SELECT @t_date = @_todate
            ELSE
                SELECT @t_date = @balanceupdate - 1
            
            SELECT @f_date = @_fromdate

            INSERT INTO #TempMatch
            SELECT m.matchid,m.matchcode FROM bodb_archive.dbo.match_bk(nolock) m WHERE m.eventdate BETWEEN @f_date AND @t_date
			UNION ALL 
			SELECT m.orid as matchid, m.matchcode FROM bodb_archive.dbo.Outright_bk(nolock) m WHERE m.eventdate BETWEEN @f_date AND @t_date
        END

        INSERT INTO #TempData
        SELECT CASE s.SubProduct WHEN 'MG-SuperLive' THEN -1
								 ELSE	b.sporttype
								 END sporttype			
				,case when (b.bettype in (1,3,7,8,301,302,303,304) or (b.bettype between 801 and 899)) then b.bettype else 19999 end as bettype
				,b.liveindicator
				,ibc
				, CASE WHEN m.matchcode LIKE '%Hedge%' THEN 1 ELSE 0 END IsHedge
				,'' status 
				,CASE s.SubProduct WHEN 'MG-SuperLive' THEN 2 ELSE 1 END AS OrderKey
				,s.SortKey					
				,ISNULL(SUM(realWinlost),0) as realWinlost
				,ISNULL(SUM(realPosition),0) as realPosition
				,ISNULL(SUM(realcommission),0) as realCommission
				,ISNULL(SUM(realLineTotal),0) as realLineTotal
				,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
				,ISNULL(SUM(realTurnover),0) as realTurnover
				,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM dbo.rptWinlost b WITH(NOLOCK)
			INNER JOIN #TempMatch m ON m.matchid = b.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate           
		   AND ((s.ProductID = 1 AND s.SubProduct NOT IN ('BT-Sold','BT-Bought','BT-Comm','BT-Winloss')) OR s.ProductID = 3) -- SB or NG, exclude bettrade
        GROUP BY CASE s.SubProduct WHEN 'MG-SuperLive' THEN -1 ELSE	b.sporttype END				
				,case when (b.bettype in (1,3,7,8,301,302,303,304) or (b.bettype between 801 and 899)) then b.bettype else 19999 end 
				,b.liveindicator
				,ibc
				,CASE WHEN b.bettype in (1,3,7,8) then b.bettype else 19999 end        
				,CASE WHEN m.matchcode LIKE '%Hedge%' THEN 1 ELSE 0 END
				,CASE s.SubProduct WHEN 'MG-SuperLive' THEN 2 ELSE 1 END
				,s.SortKey						
		
		INSERT INTO #TempData
		-- bettrade
		SELECT -2 sporttype			
				,903 bettype
				,1 liveindicator
				,ibc
				, CASE WHEN ISNULL(m.matchcode, '') LIKE '%Hedge%' THEN 1 ELSE 0 END IsHedge
				,'' status 
				,15 OrderKey
				,s.SortKey					
				,ISNULL(SUM(realWinlost),0) as realWinlost
				,ISNULL(SUM(realPosition),0) as realPosition
				,ISNULL(SUM(realcommission),0) as realCommission
				,ISNULL(SUM(realLineTotal),0) as realLineTotal
				,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
				,ISNULL(SUM(realTurnover),0) as realTurnover
				,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM dbo.rptWinlost b WITH(NOLOCK)
			LEFT JOIN #TempMatch m ON m.matchid = b.matchid
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate           
		   AND s.ProductID = 1 AND s.SubProduct IN ('BT-Comm','BT-Winloss')
        GROUP BY ibc
				,CASE WHEN ISNULL(m.matchcode, '') LIKE '%Hedge%' THEN 1 ELSE 0 END
				,s.SortKey	
	
		INSERT INTO #TempData
        --Casino
        SELECT  251 as sporttype
				,71 as bettype
				,0 as liveindicator
				,0 as ibc
				,0 as IsHedge
				,'' status
				,5 as OrderKey
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0)
				,ISNULL(SUM(realPosition),0)
				,ISNULL(SUM(realCommission),0)
				,ISNULL(SUM(realLineTotal),0)
				,ISNULL(SUM(realLineTotal),0) as virtualLineTotal --copy data from actual value
				,ISNULL(SUM(CASE WHEN b.bettype = 71 THEN 0 ELSE realTurnover END),0) as realTurnover
				,ISNULL(SUM(CASE WHEN b.bettype = 71 THEN 0 ELSE realTurnover END),0) as virtualTurnover
        FROM dbo.rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate            
			AND s.ProductId=6
        --GROUP BY b.bettype
	
		INSERT INTO #TempData
        --Bingo
        SELECT 	252 as sporttype
				,b.bettype
				,0 as liveindicator
				,0 as ibc
				,0 as IsHedge
				,'' status
				,6 as OrderKey
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0)
				,ISNULL(SUM(realPosition),0)
				,ISNULL(SUM(realCommission),0)
				,ISNULL(SUM(realLineTotal),0)
				,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
				,0 as realTurnover
				,NULL as virtualTurnover
        FROM dbo.rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
            --AND bettype = 73
			AND s.ProductId=7
        GROUP BY b.bettype
    
		INSERT INTO #TempData
		-- Keno
		SELECT 	202 sporttype
				,b.bettype
				,b.liveindicator
				,ibc
				,0 as IsHedge
				,'' status  
				,7 as OrderKey	
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0) as realWinlost
				,ISNULL(SUM(realPosition),0) as realPosition
				,ISNULL(SUM(realcommission),0) as realCommission
				,ISNULL(SUM(realLineTotal),0) as realLineTotal
				,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
				,ISNULL(SUM(realTurnover),0) as realTurnover
				,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM dbo.rptWinlost b WITH(NOLOCK)
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
            --and bettype BETWEEN 1501 AND 1599
			AND s.ProductId=8
        GROUP BY sporttype,b.liveindicator ,ibc
            ,b.bettype
    
		INSERT INTO #TempData
        --Live casino
        SELECT  162 as sporttype
				,b.bettype
				,0 as liveindicator
				,0 as ibc
				,0 as IsHedge
				,'' status
				,8 as OrderKey
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0)
				,ISNULL(SUM(realPosition),0) 
				,ISNULL(SUM(realCommission),0)
				,ISNULL(SUM(realLineTotal),0)
				,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
				,ISNULL(SUM(realTurnover),0)
				,ISNULL(SUM(realTurnover),0) as virtualTurnover
        FROM dbo.rptWinlost b WITH(NOLOCK)
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
            --AND bettype between 1101 and 1199
			AND s.ProductId=4
        GROUP BY b.bettype
    
		INSERT INTO #TempData
        SELECT  97 -- mix parlay
				,9 as bettype
				,0 as liveindicator
				,0 as ibc
				,0 as IsHedge
				,status
				,3 as OrderKey
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0)
				,ISNULL(SUM(realPosition),0) 
				,ISNULL(SUM(realCommission),0)
				,ISNULL(SUM(realLineTotal),0)
				,ISNULL(SUM(virtualLineTotal),0)
				,ISNULL(SUM(realTurnover),0)
				,ISNULL(SUM(virtualTurnover),0)
        FROM dbo.rptWinlost b WITH(NOLOCK)
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
            AND (bettype = 9 or (bettype = 29 and exrisk = 1))
        GROUP BY status
    
		INSERT INTO #TempData
        SELECT  98 --system parlay
				,29 as bettype
				,0 as liveindicator
				,0 as ibc
				,0 as IsHedge
				,status
				,4 as OrderKey
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0)
				,ISNULL(SUM(realPosition),0) 
				,ISNULL(SUM(realCommission),0)
				,ISNULL(SUM(realLineTotal),0)
				,ISNULL(SUM(virtualLineTotal),0)
				,ISNULL(SUM(realTurnover),0)
				,ISNULL(SUM(virtualTurnover),0)
        FROM dbo.rptWinlost b WITH(NOLOCK)
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
            AND bettype = 29 and exrisk <> 1  
        GROUP BY status
    
		INSERT INTO #TempData
        --racing
        SELECT   sporttype
				,0 as bettype
				,0 as liveindicator
				,0 as ibc
				,0 as IsHedge
				,'' as status
				,14 as OrderKey
				,17 as SortKey
				,ISNULL(SUM(realWinlost),0)
				,ISNULL(SUM(realPosition),0) 
				,ISNULL(SUM(realCommission),0)
				,ISNULL(SUM(realLineTotal),0)
				,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
				,0 as realTurnover
				,0 as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
            --AND bettype BETWEEN 31 AND 33
			AND s.ProductId=2
        GROUP BY sporttype
    
		INSERT INTO #TempData
        --virtual sports
        SELECT sporttype
            ,0 as bettype
            ,0 as liveindicator
            ,0 as ibc
            ,0 as IsHedge
            ,'' as status
			,15 as OrderKey
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0)
            ,ISNULL(SUM(realPosition),0) 
            ,ISNULL(SUM(realCommission),0)
            ,ISNULL(SUM(realLineTotal),0)
            ,ISNULL(SUM(realLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0)
            ,ISNULL(SUM(realTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
		INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
        WHERE winlostdate BETWEEN @_fromdate AND @_todate
            --AND bettype BETWEEN 1201 AND 1299
			AND s.ProductId=5
        GROUP BY sporttype

		INSERT INTO #TempData
        -- HR Fixed Odds
        SELECT sporttype
            ,bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,1 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND sporttype = 154
        GROUP BY sporttype,bettype, b.liveindicator ,ibc
	
		INSERT INTO #TempData
		-- GD
        SELECT 255 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,9 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=12
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc
	
		INSERT INTO #TempData
		-- Micro Gaming LC
        SELECT 203 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,10 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=13
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc
	
		INSERT INTO #TempData
		-- Micro Gaming RNG
        SELECT 205 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,10 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=17
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc
	
		INSERT INTO #TempData
		--- AG Casino
        SELECT 250 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,11 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=11
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc
	
		INSERT INTO #TempData
		--	VegasGame aka Macau
        SELECT 249 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,12 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=14
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc	
	
		INSERT INTO #TempData
		-- allbet section 
        SELECT 211 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,13 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=21
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc	
	   
	   -- Macau Games section 
		INSERT INTO #TempData
        SELECT 212 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,13 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=22
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc	
	
		INSERT INTO #TempData
		--	ColossusBet
        SELECT 204 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,16 as OrderKey	
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId=15
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc
	
		INSERT INTO #TempData
		  SELECT sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,17 as OrderKey
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId IN (23)
        GROUP BY sporttype,b.bettype, b.liveindicator ,ibc	
	   --Fish World
		UNION ALL
		  SELECT 219 sporttype
            ,b.bettype
            ,b.liveindicator
            ,ibc
            ,0 as IsHedge
            ,'' status 
			,17 as OrderKey
			,17 as SortKey
            ,ISNULL(SUM(realWinlost),0) as realWinlost
            ,ISNULL(SUM(realPosition),0) as realPosition
            ,ISNULL(SUM(realcommission),0) as realCommission
            ,ISNULL(SUM(realLineTotal),0) as realLineTotal
            ,ISNULL(SUM(virtualLineTotal),0) as virtualLineTotal
            ,ISNULL(SUM(realTurnover),0) as realTurnover
            ,ISNULL(SUM(virtualTurnover),0) as virtualTurnover
        FROM rptWinlost b WITH(NOLOCK)
			INNER JOIN @SportBettype s ON s.Bettype = b.bettype AND b.liveindicator=s.liveindicator
		WHERE winlostdate BETWEEN @_fromdate AND @_todate
            AND s.ProductId IN (24)
        GROUP BY b.bettype, b.liveindicator ,ibc		
	ORDER BY OrderKey ASC	
	
	-- Result --
	CREATE TABLE #Result
	(
		sporttype INT,
        bettype INT,
        liveindicator BIT,
        ibc TINYINT,
        IsHedge BIT,
        status NVARCHAR(20),
		OrderKey TINYINT,
        SortKey TINYINT,
        realWinlost MONEY,
        realPosition MONEY, 
        realCommission MONEY,
        realLineTotal MONEY,
        virtualLineTotal MONEY,
        realTurnover MONEY,
        virtualTurnover MONEY
	)

	-- 8RM, BARM
	INSERT INTO #Result
	SELECT sporttype,
           bettype,
           liveindicator,
           ibc,
           0 AS IsHedge,
           status,
		   OrderKey,
           SortKey,
           SUM(realWinlost) as realWinlost,
           SUM(realPosition) as realPosition, 
           SUM(realCommission) as realCommission,
           SUM(realLineTotal) as realLineTotal,
           SUM(virtualLineTotal) as virtualLineTotal,
           SUM(realTurnover) as realTurnover,
           SUM(virtualTurnover) as virtualTurnover 
	FROM #TempData
	WHERE ibc IN (1, 2)
	GROUP BY sporttype,
           bettype,
           liveindicator,
           ibc,
           status,
           OrderKey,
           SortKey

	-- Hegde match, Normal match
	INSERT INTO #Result
	SELECT sporttype,
           bettype,
           liveindicator,
           0 AS ibc,
           IsHedge,
           status,
		   OrderKey,
           SortKey,
           SUM(realWinlost) as realWinlost,
           SUM(realPosition) as realPosition, 
           SUM(realCommission) as realCommission,
           SUM(realLineTotal) as realLineTotal,
           SUM(virtualLineTotal) as virtualLineTotal,
           SUM(realTurnover) as realTurnover,
           SUM(virtualTurnover) as virtualTurnover 
	FROM #TempData
	GROUP BY sporttype,
           bettype,
           liveindicator,
           IsHedge,
           status,
           OrderKey,
           SortKey

	SELECT sporttype,
           bettype,
           liveindicator,
           ibc,
           IsHedge,
           status,
		   OrderKey,
           SortKey,
           SUM(realWinlost) as realWinlost,
           SUM(realPosition) as realPosition, 
           SUM(realCommission) as realCommission,
           SUM(realLineTotal) as realLineTotal,
           SUM(virtualLineTotal) as virtualLineTotal,
           SUM(realTurnover) as realTurnover,
           SUM(virtualTurnover) as virtualTurnover 
	FROM #Result
	GROUP BY sporttype,
           bettype,
           liveindicator,
           ibc,
		   IsHedge,
           status,
           OrderKey,
           SortKey
	ORDER BY OrderKey,SortKey, liveindicator
    
	DROP TABLE #TempMatch
	DROP TABLE #TempData
	DROP TABLE #Result
END
GO 
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostSummary_Sporttype] TO [vnteam]
GO 
GRANT EXECUTE ON [dbo].[Acc_Rpt_WinlostSummary_Sporttype] TO [bodbAdminNet]
GO 
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_WinlostSummary_Sporttype] TO [bodbAdminNet]
GO