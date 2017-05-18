USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_AllProductWLAutomail]
	@AllowSendEmail BIT = 0 OUTPUT
AS
/*
	Created: Dom
	Date: 20140418
	Task : Automail Win Loss reports for all products
	DB: DBACC.bodb02
	Original:

	Revisions:
		- 20150619@Sophia: Add Gold Deluxe, AG Casino, Vegas Game [#38512]
		- 20150702@Sophia: Apply Metric Gaming, Microgaming and Bettrade [#36906]
		- 20150722@Sophia: Send mail for dummy account in case of testing
		- 20150928@Sophia: Apply Colosuss Bets and expand the range of AG Casino [#43352]
		- 20150930@Sophia: Fix winlostyesterday at table Transfer_bk [#44701]
		- 20151102@Sophia: Apply Microgaming LC and RNG [RedmineID: #46450]
		- 20151210@Sophia: Apply Cock Fighting [Redmine: #48602]
		- 20151217@Sophia: Apply Muay Thai [Redmine: #48667]
		- 20160114@Sophia: Apply OW RNG [Redmine: #48285]
		- 20160330@Sophia: Remove Bingo [Redmine: #54719]
		- 20160404@Sophia: Apply Allbet [Redmine: #50588]
		- 20160412@Percy: support Voidbridge single wallet [Redmine: #55258]
		- 20160815@Percy: Apply new bettype of Bettrade: 904 [RedmineID: #61786]
		- 20161013@Percy: Apply NG2 [RedmineID: #64117]
		- 20161222@Percy: Apply Fishing World [RedmineID: #65734]
		- 20161227@Percy: Clean up code Cockfighting [RedmineID: #69446]
		- 20170213@Percy: Remove SLI [RedmineID: #70036]
		- 20170323@Percy: Apply Cash Out [RedmineID: #72164]
		 
	Param's Explanation:
	
*/

BEGIN

	DECLARE @dummyBalance TABLE ([group] varchar(10),orderby INT, custid INT, product VARCHAR(50))
	 
	DECLARE @isTest BIT,@SQL NVARCHAR(100) = OBJECT_NAME(@@PROCID)

	IF  (@SQL like '%_xtest%')
	BEGIN
		SELECT @isTest = 1
	END
	ELSE
	BEGIN
		SELECT @isTest = 0
	END

	------------------------------------------
	
	--INSERT INTO @dummyBalance 
	--		  SELECT	'SB',1, 6911909	, 'Sportsbook Live'			---- DWLSPL'
	--UNION ALL SELECT	'SB',2, 6911911	, 'Sportsbook Non-Live'		---- DWLSPNL
	--UNION ALL SELECT	'SB',3, 6911913	, 'Parlay'		---- DWLParlay
	--UNION ALL SELECT	'SB',4, 6911914	, 'Outright'	---- DWLOutright
	--UNION ALL SELECT	'3rd', 5, 6911916	, 'RNG Casino'		---- DWLCasino
	--UNION ALL SELECT	'3rd', 6, 6911917	, 'Live Casino' ---- DWLLiveCasino
	--UNION ALL SELECT	'3rd', 7, 6911918	, 'Number Game' ---- DWLNumber	
	--UNION ALL SELECT	'3rd', 8, 6911919	, 'Racing'		---- DWLRacing
	--UNION ALL SELECT	'partners', 9, 7723121	, 'Racing (Due to Partners)'	----- VNM-Racing Partners MYR
	--UNION ALL SELECT	'3rd', 10, 6913085	, 'Bingo'		---- DWLBingo
	--UNION ALL SELECT	'3rd', 11, 8158305	, 'Virtual Sports'	---- DWLVirtualSports
	--UNION ALL SELECT	'3rd', 12, 14054918, 'Keno'		---- DWLKeno
	--UNION ALL SELECT	'3rd', 13, 18123445, 'Gold Deluxe'
	--UNION ALL SELECT	'3rd', 14, 18188766, 'AG Casino'
	--UNION ALL SELECT	'3rd', 15, 18188815, 'Vegas Game'
 
	IF @isTest = 0
	BEGIN 	
		INSERT INTO @dummyBalance ([group], orderby, custid, product )
		SELECT		CASE WHEN Product IN ('SPL','SPNL','Parlay','Outright') THEN 'SB' 
						 WHEN Product IN ('Racing (Due to Partners)') THEN 'partners' 
						 ELSE '3rd' END AS [Group]
					, Seq
					, Custid
					, CASE	WHEN Product = 'SPL' THEN 'Sportsbook Live' 
							WHEN Product = 'SPNL' THEN 'Sportsbook Non-Live' 
						 ELSE Product END AS Product
		FROM	bodb_ACC.dbo.Acc_DWLList WITH (NOLOCK)
		WHERE  	Product NOT IN ('Total Balance')
	END
	ELSE 
	BEGIN 
		INSERT INTO @dummyBalance ([group], orderby, custid, product )
		SELECT		CASE WHEN Product IN ('SPL','SPNL','Parlay','Outright') THEN 'SB' 
						 WHEN Product IN ('Racing (Due to Partners)') THEN 'partners' 
						 ELSE '3rd' END AS [Group]
					, Seq
					, Custid
					, CASE	WHEN Product = 'SPL' THEN 'Sportsbook Live' 
							WHEN Product = 'SPNL' THEN 'Sportsbook Non-Live' 
						 ELSE Product END AS Product
		FROM 	bodb_ACC.dbo.Acc_DWLList_xtest WITH (NOLOCK)
		WHERE  	Product NOT IN ('Total Balance')
	END

	DECLARE @_fromdate    DATETIME,
			@_todate      DATETIME,
			@totalrows 	  INT,
			@TotalDummy	  INT
			
			
	SELECT @_todate = convert(varchar(10), getdate()-1, 120)
	SELECT @_fromdate = convert(varchar(10), DATEADD(DAY, -(DAY(GETDATE()-1)), GETDATE()),120)

    CREATE TABLE #TempYesterday (CustId INT, Winlostyesterday MONEY)
	CREATE TABLE #TempMonthToDate (WinlostDate DATETIME,CustId int, WinlostMonthToDate money)
	CREATE TABLE #TempCustTrans (CustId INT)
	
    
    DECLARE @movebetdate datetime,
        @balanceupdate datetime
        --@f_date datetime,
        --@t_date datetime
    
        SELECT 
            TOP 1 @balanceupdate = winlostdate
        FROM bodb02.dbo.Bettrans WITH(NOLOCK)
        WHERE bettype = 20000 and matchid = 0 and custid = 3
            
		--SELECT @f_date = @balanceupdate
		--SELECT @t_date = @_todate
		/*
        INSERT INTO #TempMonthToDate
        SELECT b.winlostdate,
			b.custid, 
			ISNULL(-SUM(winlost-actual_stake),0) AS winlostyesterday
		FROM bettrans b WITH(NOLOCK) 
			WHERE b.winlostdate BETWEEN @f_date AND @t_date
			AND	b.custid in( SELECT custid FROM @dummyBalance )
			AND ruben = 1 
			AND statusid NOT IN (101,102,103,121,141)	
		GROUP BY b.custid,b.winlostdate
		ORDER BY b.custid
		*/
        IF @_fromdate < @balanceupdate --get bettrans BK
        BEGIN
            
			--SELECT @f_date = @_fromdate
            --SELECT @t_date = @balanceupdate - 1
            
            INSERT INTO #TempMonthToDate
            SELECT b.winlostdate,
				b.custid, 
				ISNULL(-SUM(b.Credit - b.Debit),0) AS winlostyesterday
			FROM bodb_archive.dbo.transfer_bk b WITH(NOLOCK) 
			 WHERE b.winlostdate BETWEEN @_fromdate AND @balanceupdate - 1
				AND	b.custid in (Select CustId from @dummyBalance ) ----( 6911909,6911911,6911913,6911914,6911916,6911917,6911918,6911919,6913085,7723121,8158305, 14054918 )
				AND b.bettype IN(21001,21002)
			GROUP BY b.custid,b.winlostdate
			ORDER BY b.custid

			INSERT INTO #TempMonthToDate
			SELECT b.winlostdate,
				b.custid, 
				ISNULL(-SUM(winlost-actual_stake),0) AS winlostyesterday
			FROM bettrans b WITH(NOLOCK) 
				WHERE b.winlostdate BETWEEN @balanceupdate AND @_todate
				AND	b.custid in( SELECT custid FROM @dummyBalance )
				AND ruben = 1 
				AND statusid NOT IN (101,102,103,121,141)	
				AND b.bettype IN(21001,21002)
			GROUP BY b.custid,b.winlostdate
			ORDER BY b.custid

			PRINT @balanceupdate;
			

        END
		ELSE IF(@_fromdate >= @balanceupdate)
		BEGIN
			INSERT INTO #TempMonthToDate
			SELECT b.winlostdate,
				b.custid, 
				ISNULL(-SUM(winlost-actual_stake),0) AS winlostyesterday
			FROM bettrans b WITH(NOLOCK) 
				WHERE b.winlostdate BETWEEN @_fromdate AND @_todate
				AND	b.custid in( SELECT custid FROM @dummyBalance )
				AND ruben = 1 
				AND statusid NOT IN (101,102,103,121,141)	
				AND b.bettype IN(21001,21002)
			GROUP BY b.custid,b.winlostdate
			ORDER BY b.custid

			PRINT @balanceupdate;

		END

		INSERT INTO #TempYesterday
		SELECT b.custid, 
			b.WinlostMonthToDate AS winlostyesterday
		FROM #TempMonthToDate b 
		WHERE b.winlostdate = @_todate
		ORDER BY b.custid

/****************************This Section is to check there is no ticklet and no key in action**************************/
	/*
	
		Find product that has no ticket and then identify accounts don't need to transfer. If there is no ticket, transfer account should have winlost amount = 0
	
	*/	

	IF @isTest = 0
	BEGIN 	
		INSERT INTO #TempCustTrans
		SELECT DISTINCT custid = CASE 
							WHEN ((bettype <= 999 AND bettype NOT IN (9,10,29,31,32,33,71,72) AND (bettype NOT BETWEEN 81 AND 120) AND (bettype NOT BETWEEN 801 AND 899) AND (bettype NOT BETWEEN 901 AND 904) AND (bettype NOT BETWEEN 911 AND 914)) OR bettype BETWEEN 1301 AND 1334) AND liveindicator =1 AND Sporttype <> 44 THEN 6911909
							WHEN ((bettype <= 999 AND bettype NOT IN (9,10,29,31,32,33,71,72) AND (bettype NOT BETWEEN 81 AND 120) AND (bettype NOT BETWEEN 801 AND 899) AND (bettype NOT BETWEEN 901 AND 904) AND (bettype NOT BETWEEN 911 AND 914)) OR bettype BETWEEN 1301 AND 1334) AND liveindicator =0 AND Sporttype <> 44 THEN 6911911
							WHEN bettype IN(9,29 ) THEN 6911913
							WHEN bettype = 10 THEN 6911914
							WHEN bettype IN (71,72) OR bettype BETWEEN 2101 AND 2399 THEN 6911916
							--WHEN bettype BETWEEN 1101 AND 1199 THEN 6911917
							WHEN bettype BETWEEN 81 AND 120 THEN 6911918
							WHEN bettype IN (31,32,33) THEN 6911919							
							WHEN bettype BETWEEN 1201 AND 1299 THEN 8158305
							WHEN bettype BETWEEN 1501 AND 1599 THEN 14054918
							WHEN bettype IN (31,32,33) THEN 7723121
							WHEN bettype BETWEEN 1800 AND 1899 THEN 18188766
							WHEN bettype = 1900 THEN 18188815
							WHEN bettype BETWEEN 1700 AND 1799 THEN 18123445
							WHEN bettype BETWEEN 801 AND 899 THEN 18123442 
							WHEN bettype BETWEEN 2001 AND 2007 THEN 18256397
							WHEN bettype BETWEEN 2008 AND 2009 THEN 19692521
							WHEN bettype BETWEEN 901 AND 904 THEN 18371760
							WHEN bettype BETWEEN 18000 AND 18099 THEN 19236210
							--WHEN bettype = 1003 THEN 20174484
							WHEN Sporttype = 44 THEN 20174356
							WHEN bettype BETWEEN 2401 AND 2499 THEN 20664406
							WHEN bettype BETWEEN 4001 AND 7999 THEN 21535688
							WHEN bettype BETWEEN 2501 AND 2699 THEN 23765766
							WHEN bettype BETWEEN 1011 AND 1020 THEN 24569216
							WHEN bettype BETWEEN 911 AND 914 THEN 25477229
						END
		FROM bodb_report.dbo.rptWinLost b WITH(NOLOCK)
		WHERE b.winlostdate = @_todate
	END
	ELSE
	BEGIN 
		INSERT INTO #TempCustTrans
		SELECT DISTINCT custid = CASE 
							WHEN ((bettype <= 999 AND bettype NOT IN (9,10,29,31,32,33,71,72) AND (bettype NOT BETWEEN 81 AND 120) AND (bettype NOT BETWEEN 801 AND 899) AND (bettype NOT BETWEEN 901 AND 904) AND (bettype NOT BETWEEN 911 AND 914)) OR bettype BETWEEN 1301 AND 1334) AND liveindicator =1  AND Sporttype <> 44 THEN 9398886
							WHEN ((bettype <= 999 AND bettype NOT IN (9,10,29,31,32,33,71,72) AND (bettype NOT BETWEEN 81 AND 120) AND (bettype NOT BETWEEN 801 AND 899) AND (bettype NOT BETWEEN 901 AND 904) AND (bettype NOT BETWEEN 911 AND 914)) OR bettype BETWEEN 1301 AND 1334) AND liveindicator =0  AND Sporttype <> 44 THEN 12005466
							WHEN bettype IN(9,29 ) THEN 12005470
							WHEN bettype = 10 THEN 12005483
							WHEN bettype IN (71,72) OR bettype BETWEEN 2101 AND 2399 THEN 12017095
							--WHEN bettype BETWEEN 1101 AND 1199 THEN 12962878
							WHEN bettype BETWEEN 81 AND 120 THEN 13062600
							WHEN bettype IN (31,32,33) THEN 13062602
							WHEN bettype BETWEEN 1201 AND 1299 THEN 13062615
							WHEN bettype BETWEEN 1501 AND 1599 THEN 13062664
							WHEN bettype IN (31,32,33) THEN 13062630
							WHEN bettype BETWEEN 1800 AND 1899 THEN 18254399
							WHEN bettype = 1900 THEN 18254404
							WHEN bettype BETWEEN 1700 AND 1799 THEN 18254395
							WHEN bettype BETWEEN 801 AND 899 THEN 18254387 
							WHEN bettype BETWEEN 2001 AND 2007 THEN 18377344
							WHEN bettype BETWEEN 2008 AND 2009 THEN 19741787
							WHEN bettype BETWEEN 901 AND 904 THEN 18377348
							WHEN bettype BETWEEN 18000 AND 18099 THEN 19235780
							--WHEN bettype = 1003 THEN  20256514
							WHEN Sporttype = 44 THEN 20174451
							WHEN bettype BETWEEN 2401 AND 2499 THEN 20805826
							WHEN bettype BETWEEN 4001 AND 7999 THEN 21526102
							WHEN bettype BETWEEN 2501 AND 2699 THEN 23766923
							WHEN bettype BETWEEN 1011 AND 1020 THEN 24567778
							WHEN bettype BETWEEN 911 AND 914 THEN 25440545
						END
		FROM bodb_report.dbo.rptWinLost b WITH(NOLOCK)
		WHERE b.winlostdate = @_todate
	END 


	INSERT INTO #TempYesterday
	SELECT d.custid,0 
	FROM @dummyBalance d LEFT JOIN #TempCustTrans c ON d.custid = c.CustId
	WHERE c.CustId IS NULL AND d.CustId NOT IN(SELECT custid FROM #TempYesterday)
	 
	/****************************End**************************/

	SELECT @totalrows = COUNT(*) FROM #TempYesterday
	SELECt @TotalDummy = COUNT(*) FROM @dummyBalance
	
	IF(@totalrows = @TotalDummy) SET @AllowSendEmail = 1 ELSE SET @AllowSendEmail = 0
--------------------------------------------------------------------------------------- 

	SELECT [group], c.custid, c.product,
		b.winlostyesterday,
		ISNULL(mb.winlostmonthtodate,0) winlostmonthtodate
	FROM @dummyBalance c
	INNER JOIN #TempYesterday b ON b.CustId = c.custid
	LEFT JOIN 
	(
		SELECT custid ,SUM(WinlostMonthToDate) WinlostMonthToDate FROM #TempMonthToDate GROUP BY CustId
	)  mb
	ON c.CustId = mb.CustId
	ORDER BY c.orderby 


	DROP TABLE #TempYesterday
	DROP TABLE #TempMonthToDate
	DROP TABLE #TempCustTrans

END
GO 
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_AllProductWLAutomail] TO [vnteam]
GO 
GRANT EXECUTE ON [dbo].[Acc_Rpt_AllProductWLAutomail] TO [bodbAdminNet]
GO 
