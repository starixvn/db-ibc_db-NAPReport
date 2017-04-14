SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_Rpt_LiveCasino_AgencyWinLoss    Script Date: 12/9/2015 2:49:09 PM ******/
ALTER PROCEDURE [dbo].[Acc_Rpt_LiveCasino_AgencyWinLoss]
	@fromdate datetime,
	@todate datetime,
	@username varchar(50) = '',
	@excludeTest BIT = 0,
	@SiteID smallint = 0,	
	@GameTypeID smallint = 0,
	@GameTableID smallint = 0,--leagueid
	@currency smallint = 0,
	@ReportBy tinyint = 0,
	@ProductId TINYINT = 0,
	@MoveBetDay smalldatetime,
    @Debug BIT = 0
AS 
/*
Created: 20120521@Dom
Task : SP for Live Casino Game - Reports - Agency Win/Loss report
DB: DBACC/bodb02 + Get history sum data from DBDW2

Revisions:
	- Dom.Cao@2012-06-12: 
		- Replace table MasterCube to mcCustLiveCasinoDaily
		- Use temp table tbl_Currency_Daily instead of ExchangeDail
	- Dom.Cao@2012-10-19:
		- Update wrong _RM column: sum((winlost-actual_stake)*actualrate)	
    - 20130123@Daniel: Change link server alias
	- 20150601@Sophia: Apply Gold Deluxe [#35359] 
	- 20150702@Sophia: Apply Microgaming and SuperBalance [#38168]
	- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
	-  Jim@20151113: HotFix #46113
	- 20160223@Robert: Add new range bettype for Allbet Live Casino [RedmineID: #50921]


		
Param's Explanation:

 - @username: 
    + Search by keyword

 - @SiteID: Company filter
    0: All sites (IBC + Licensees)
	-1: IBC sites only
    >0: Specific Licensee (ID)

 - @GameTypeID:
    0: All Game types
    >0: filter by specific game type

 - @GameTableID:
    0: All Game tables
    >0: filter by specific game table

 - @currency: 
    -1: All and convert to RM
    0: All without convert (original)
    >0: Filter by currency ID without convert (original)
  
 - @ReportBy:  
  0: Daily
  1: Monthly
  2: Username (member only)
  3: Game Type
  4: Game Table
  5: currency

  - @ProductId:
  0: All
  4: Live Casino 
  12: GoldDeluxe

*/


select @username = isnull(@username,'')

DECLARE @sql varchar(max),@UserRole int, @CustID INT, @TempDataSQL nvarchar(max), @TempDataSQLDW nvarchar(max),  
		@sqlbettrans nvarchar(max), @sqlDW nvarchar(max), @TempFromDate smalldatetime, 
		@TempToDate smalldatetime, @TempTable nvarchar(max), @sqlTableExchange nvarchar(max)
DECLARE @ColumnList varchar(1500)--, @custfilter nvarchar(max)
DECLARE @groupBy varchar(max)
DECLARE @MemIDs varchar(max)



-- Create Pure data

CREATE TABLE #Data(UserName varchar(50), 
					Currency int,
					BettypeId int,
					LeagueId int,
					TotalBets int,  
					TotalTurnover money,
					CompanyTurnOver money,
					TotalComm money,
					Winlost money,
					PlayerComm money,
					AWinlost money,
					Comm money,
					MWinlost money,
					AComm money,
					SWinlost money,
					SComm money,
					TransDate datetime,
					CompanyWinLoss MONEY,
					
					TotalTurnover_RM money,
					CompanyTurnOver_RM money,
					TotalComm_RM money,
					Winlost_RM money,
					PlayerComm_RM money,
					AWinlost_RM money,
					Comm_RM money,
					MWinlost_RM money,
					AComm_RM money,
					SWinlost_RM money,
					SComm_RM money,
					CompanyWinLoss_RM MONEY,
					)

CREATE TABLE #Agency(AgencyId INT, UserName varchar(50))

SELECT @sqlTableExchange = 'create table #tbl_Currency_Daily
    (
     [ExchangeDate] smalldatetime,
     [ExchangeId] int,
     [ActualRate] float
    )
    create clustered index #IX_curr ON #tbl_Currency_Daily([ExchangeDate],[ExchangeId])

    insert into #tbl_Currency_Daily
    select [ExchangeDate], [ExchangeId],[ActualRate] 
    from ExchangeDailyOanda with (nolock) 
    where exchangedate between '''+convert(varchar(10),@fromdate,120)+''' AND '''+convert(varchar(10),@todate,120)+'''' + char(13)

SELECT @sqlTableExchange = @sqlTableExchange + '
	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5

	DELETE @SportBettype 
	WHERE ProductID NOT IN (4,11,12,13,21)'

SELECT @TempDataSQL = ''
SELECT @TempDataSQLDW = ''
IF(@ReportBy  <> 5)--1,2,3,4
BEGIN
	SELECT   DISTINCT SUBSTRING(username,0,CHARINDEX('dummy3rd',username)) AS LicenseeName
			,Recommend CustID
			,currency 
			,0 AS LicenseeID
			INTO #tmpLicenseeDummy
	FROM DBCUST.CustDB.dbo.Customer c WITH(NOLOCK)
	WHERE username LIKE '%dummy3rd%'
	
	UPDATE d
		SET LicenseeID=s.LicenseeID
		FROM #tmpLicenseeDummy d 
			INNER JOIN DBLIC.bodb_licensee.dbo.Licensees s ON s.LicenseeName=d.LicenseeName
			
	--SELECT @UserRole = 1
	SELECT @TempDataSQL = @TempDataSQL
	+'SELECT ' + CASE WHEN @ReportBy = 2 THEN 'ci.username,'+char(13) ELSE '' END
	+'b.Currency,'+char(13)
	--+'b.actualrate,'+char(13)
	+CASE WHEN @ReportBy = 3 THEN 'b.bettype,'+char(13) ELSE '' END
	+CASE WHEN @ReportBy = 4 THEN 'l.leagueid,'+char(13) ELSE '' END
	+'count(transid),'+char(13)
	+'sum(stake),'+char(13)
	+'sum((1 - tpositiontaking)*stake),'+char(13)
	+'sum(scomm),'+char(13)
	+'sum(winlost-actual_stake),'+char(13)
	+'sum(playercomm),'+char(13)
	+'sum(awinlost),'+char(13)
	+'sum(comm-playercomm),'+char(13)
	+'sum(mwinlost),'+char(13)
	+'sum(acomm-comm),'+char(13)
	+'sum(swinlost),'+char(13)
	+'sum(scomm-acomm),'+char(13)
	+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'b.winlostdate,' +char(13) ELSE '' END
	+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)),'+char(13)
	----------RM-----------------------
	+'sum(stake * b.actualrate),'+char(13)
	+'sum((1 - tpositiontaking)*stake * b.actualrate),'+char(13)
	+'sum(scomm * b.actualrate),'+char(13)
	+'sum((winlost-actual_stake) * b.actualrate),'+char(13)
	+'sum(playercomm * b.actualrate),'+char(13)
	+'sum(awinlost * b.actualrate),'+char(13)
	+'sum((comm-playercomm) * b.actualrate),'+char(13)
	+'sum(mwinlost * b.actualrate),'+char(13)
	+'sum((acomm-comm) * b.actualrate),'+char(13)
	+'sum(swinlost * b.actualrate),'+char(13)
	+'sum((scomm-acomm) * b.actualrate),'+char(13)
	+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm) * b.actualrate)'+char(13)
	
	+'FROM bettrans b with (NOLOCK)'+char(13)
	+CASE WHEN @ReportBy = 2 OR @username <> '' THEN 'INNER JOIN CustInfo ci WITH (NOLOCK) ON ci.CustId = b.CustId'+char(13) ELSE '' END
	+CASE WHEN @GameTableID > 0 OR @ReportBy = 4 THEN 'INNER JOIN [match] m WITH(NOLOCK) ON m.matchid = b.matchid'+char(13)
									+'INNER JOIN league l WITH(NOLOCK) ON l.leagueid = m.leagueid'+char(13) 
	 ELSE ''
	 END
	+CASE WHEN @SiteID <> 0 THEN 'LEFT JOIN (
											SELECT lct.LicenseeID,lct.CustID
													FROM DBLIC.bodb_licensee.dbo.LicenseeCust lct with (nolock) 
													UNION ALL 
													SELECT tmp.LicenseeID,tmp.CustID
													FROM #tmpLicenseeDummy  tmp
											) lc on b.recommend = lc.custid' + char(13)
	 								+'LEFT JOIN DBLIC.bodb_licensee.dbo.Licensees lic with (nolock) on lc.LicenseeID = lic.LicenseeID' + char(13)
	 ELSE ''
	 END
	+'INNER JOIN @SportBettype sb ON sb.Bettype = b.Bettype'+char(13)
	+'WHERE winlostdate  >= @fromdate AND winlostdate <= @todate'+char(13)
	--+'AND b.bettype BETWEEN 1101 AND 1199 AND b.ruben = 1 '+char(13)
	+CASE WHEN @ProductId <> 0 THEN 'AND sb.ProductID = '+ CONVERT(VARCHAR(3),@ProductId) + char(13) ELSE '' END
	+'AND sb.ProductID <> 21' + char(13) --excule Allbet
	+'AND b.ruben = 1' + char(13)
	+'AND statusid IN (111,112,113)'+char(13)
	+CASE WHEN @username <> '' THEN 'AND ci.username LIKE '''+@username+'%'' '+char(13) ELSE '' END
	+case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
	+case when @SiteID > 0 then '	AND lc.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND lc.licenseeID is null' else '' end + char(13)
	+case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
	+case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
	+case when @GameTableID > 0 then '	AND l.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else '' end--gametable filter
	+'GROUP BY'+char(13)
	+CASE WHEN @ReportBy = 3 THEN 'b.bettype,'+char(13) ELSE '' END
	+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'b.winlostdate,' +char(13) ELSE '' END
	+CASE WHEN @ReportBy = 2 THEN 'ci.username,'+char(13) ELSE '' END
	+CASE WHEN @ReportBy = 4 THEN 'l.leagueid,'+char(13) ELSE '' END
	+' b.Currency'+CHAR(13)
	
	--Begin get Allbet data	
	IF(@ProductId = 0 or @ProductId = 21)
	BEGIN
		SELECT @TempDataSQL = @TempDataSQL + ' UNION ALL '
		+'SELECT ' + CASE WHEN @ReportBy = 2 THEN 'ci.username,'+char(13) ELSE '' END
		+'b.Currency,'+char(13)
		--+'b.actualrate,'+char(13)
		+CASE WHEN @ReportBy = 3 THEN 'b.gameID,'+char(13) ELSE '' END
		+CASE WHEN @ReportBy = 4 THEN '0,'+char(13) ELSE '' END
		+'count(transid),'+char(13)
		+'sum(stake),'+char(13)
		+'sum((1 - tpositiontaking)*stake),'+char(13)
		+'sum(scomm),'+char(13)
		+'sum(winlost-actual_stake),'+char(13)
		+'sum(playercomm),'+char(13)
		+'sum(awinlost),'+char(13)
		+'sum(comm-playercomm),'+char(13)
		+'sum(mwinlost),'+char(13)
		+'sum(acomm-comm),'+char(13)
		+'sum(swinlost),'+char(13)
		+'sum(scomm-acomm),'+char(13)
		+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'b.winlostdate,' +char(13) ELSE '' END
		+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)),'+char(13)
		----------RM-----------------------
		+'sum(stake * b.actualrate),'+char(13)
		+'sum((1 - tpositiontaking)*stake * b.actualrate),'+char(13)
		+'sum(scomm * b.actualrate),'+char(13)
		+'sum((winlost-actual_stake) * b.actualrate),'+char(13)
		+'sum(playercomm * b.actualrate),'+char(13)
		+'sum(awinlost * b.actualrate),'+char(13)
		+'sum((comm-playercomm) * b.actualrate),'+char(13)
		+'sum(mwinlost * b.actualrate),'+char(13)
		+'sum((acomm-comm) * b.actualrate),'+char(13)
		+'sum(swinlost * b.actualrate),'+char(13)
		+'sum((scomm-acomm) * b.actualrate),'+char(13)
		+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm) * b.actualrate)'+char(13)
	
		+'FROM bettransLC b with (NOLOCK)'+char(13)
		+CASE WHEN @ReportBy = 2 OR @username <> '' THEN 'INNER JOIN CustInfo ci WITH (NOLOCK) ON ci.CustId = b.CustId'+char(13) ELSE '' END		
		+CASE WHEN @SiteID <> 0 THEN 'LEFT JOIN (
												SELECT lct.LicenseeID,lct.CustID
														FROM DBLIC.bodb_licensee.dbo.LicenseeCust lct with (nolock) 
														UNION ALL 
														SELECT tmp.LicenseeID,tmp.CustID
														FROM #tmpLicenseeDummy  tmp
												) lc on b.recommend = lc.custid' + char(13)
	 									+'LEFT JOIN DBLIC.bodb_licensee.dbo.Licensees lic with (nolock) on lc.LicenseeID = lic.LicenseeID' + char(13)
		 ELSE ''
		 END
		+'INNER JOIN @SportBettype sb ON sb.Bettype = b.gameID'+char(13)
		+'WHERE winlostdate  >= @fromdate AND winlostdate <= @todate'+char(13)		
		+'AND sb.ProductID = 21' + char(13) -- Allbet		
		+'AND statusid IN (111,112,113)'+char(13)
		+CASE WHEN @username <> '' THEN 'AND ci.username LIKE '''+@username+'%'' '+char(13) ELSE '' END
		+case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
		+case when @SiteID > 0 then '	AND lc.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND lc.licenseeID is null' else '' end + char(13)
		+case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
		+case when @GameTypeID > 0 then '	AND b.gameID = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter		
		+'GROUP BY'+char(13)
		+CASE WHEN @ReportBy = 3 THEN 'b.gameID,'+char(13) ELSE '' END
		+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'b.winlostdate,' +char(13) ELSE '' END
		+CASE WHEN @ReportBy = 2 THEN 'ci.username,'+char(13) ELSE '' END		
		+' b.Currency'+CHAR(13)
	END
	-- END get Allbet data	
	
	SELECT @TempDataSQLDW = @TempDataSQLDW ---select from data warehouse
	+'SELECT ' + CASE WHEN @ReportBy = 2 THEN 'ci.username,'+char(13) ELSE '' END
	+'b.currency,'+char(13)
	--+'c.actualrate,'+char(13)
	+CASE WHEN @ReportBy = 3 THEN 'b.bettype,'+char(13) ELSE '' END
	+CASE WHEN @ReportBy = 4 THEN 'b.leagueid,'+char(13) ELSE '' END
	+'SUM(b.betcount),'+char(13)
	+'SUM(stake),'+char(13)
	+'SUM(TurnoverIBC),'+char(13)
	+'SUM(CommissionS),'+char(13)
	+'SUM(WinlossP),'+char(13)
	+'SUM(CommissionP),'+char(13)
	+'SUM(WinlossA),'+char(13)
	+'SUM(CommissionA-CommissionP),'+char(13)
	+'SUM(WinlossM),'+char(13)
	+'SUM(CommissionM-CommissionA),'+char(13)
	+'SUM(WinlossS),'+char(13)
	+'SUM(CommissionS-CommissionM), '+char(13)
	+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'b.rptDate,' +char(13) ELSE '' END
	+'-SUM(winlossIBC+CommissionS),'+char(13)
	----------------RM-------------------------
	+'SUM(stake * c.actualrate),'+char(13)
	+'SUM(TurnoverIBC * c.actualrate),'+char(13)
	+'SUM(CommissionS * c.actualrate),'+char(13)
	+'SUM(WinlossP * c.actualrate),'+char(13)
	+'SUM(CommissionP * c.actualrate),'+char(13)
	+'SUM(WinlossA * c.actualrate),'+char(13)
	+'SUM((CommissionA-CommissionP) * c.actualrate),'+char(13)
	+'SUM(WinlossM * c.actualrate),'+char(13)
	+'SUM((CommissionM-CommissionA) * c.actualrate),'+char(13)
	+'SUM(WinlossS * c.actualrate),'+char(13)
	+'SUM((CommissionS-CommissionM) * c.actualrate), '+char(13)
	+'-SUM((winlossIBC+CommissionS) * c.actualrate)'+char(13)
	
	+'FROM DBDW2.bodb_account.dbo.mcCustLiveCasinoDaily  b WITH(NOLOCK) '+char(13)
	+'INNER JOIN @SportBettype sb ON sb.Bettype = b.Bettype'+char(13)
	+CASE WHEN @ReportBy = 2 OR @username <> '' THEN 'INNER JOIN CustInfo ci WITH (NOLOCK) ON ci.CustId = b.CustId'+char(13) ELSE '' END
	+'INNER JOIN #tbl_Currency_Daily c with (nolock) on b.rptdate = c.exchangedate AND b.currency = c.exchangeid' + char(13)
	+CASE WHEN @SiteID <> 0 THEN 'LEFT JOIN DBDW2.bodb_Account.dbo.tbl_site s with (nolock) on b.siteid = s.siteid' + char(13)
								+'LEFT JOIN DBLIC.bodb_licensee.dbo.Licensees lic with (nolock) on s.site = lic.licenseeName' + char(13)
	 ELSE '' 
	 END
	+'WHERE rptDate  >= @fromdate and rptDate <= @todate'+char(13)
	---+'AND b.bettype BETWEEN 1101 AND 1199' + char(13)
	+ CASE WHEN @ProductId <> 0 THEN 'AND sb.ProductID = '+ CONVERT(VARCHAR(3),@ProductId) + char(13) ELSE '' END
	--+'AND b.status IN (3,4,8)' + char(13)
	+CASE WHEN @username <> '' THEN 'AND ci.username LIKE '''+@username+'%'' '+char(13) ELSE '' END
	+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
	+ case when @SiteID > 0 then '	AND lic.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND s.isDeposit = 0' + char(13) else '' end
	+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
	+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
	+ case when @GameTableID > 0 then '	AND b.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else '' end--gametable filter
	+'GROUP BY'+char(13)
	+CASE WHEN @ReportBy = 3 THEN 'b.bettype,'+char(13) ELSE '' END
	+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'b.rptDate,' +char(13) ELSE '' END
	+CASE WHEN @ReportBy = 2 THEN 'ci.username,'+char(13) ELSE '' END
	+CASE WHEN @ReportBy = 4 THEN 'b.leagueid,'+char(13) ELSE '' END
	+' b.currency'+CHAR(13)
	--+'c.actualrate'+char(13)
	--DROP TABLE #tmpLicenseeDummy
END
ELSE--(@ReportBy = 5)
BEGIN
	IF(@username='')--user not input username --> get all supers
	BEGIN
		SELECT @UserRole = -1
	END
	ELSE
	BEGIN
		SELECT @CustID = custid, @UserRole = roleid from custinfo where username = @username and roleid <> 1
		IF(@UserRole=4)
		BEGIN
			INSERT INTO #Agency
			SELECT custid,username FROM custInfo WHERE srecommend = @CustID AND roleid = 3
		END
		ELSE IF (@UserRole=3)
		BEGIN
			INSERT INTO #Agency
			SELECT custid,username FROM custInfo WHERE mrecommend = @CustID AND roleid = 2
		END
		ELSE IF (@UserRole=2)
		BEGIN
			INSERT INTO #Agency
			SELECT custid,username FROM custInfo WHERE recommend = @CustID AND roleid = 1
		END
		
	END
	
	SELECT   DISTINCT SUBSTRING(username,0,CHARINDEX('dummy3rd',username)) AS LicenseeName
			,Recommend CustID
			,currency 
			,0 AS LicenseeID
			INTO #tmpLicenseeDummy1
		FROM DBCUST.CustDB.dbo.Customer c WITH(NOLOCK)
		WHERE username LIKE '%dummy3rd%'
		
		UPDATE d
		SET LicenseeID=s.LicenseeID
		FROM #tmpLicenseeDummy1 d 
			INNER JOIN DBLIC.bodb_licensee.dbo.Licensees s ON s.LicenseeName=d.LicenseeName
			
	-- There is no username 
	IF(@UserRole IS NULL) RETURN
	
	--- Querying from bettrans	
	SELECT @TempDataSQL = @TempDataSQL
	+'SELECT a.UserName,'+char(13)
	+'b.Currency,'+char(13)
	--+'b.actualrate, '+char(13)
	+'count(transid),'+char(13)
	+'sum(stake),'+char(13)
	+'sum((1 - tpositiontaking)*stake),'+char(13)
	+'sum(scomm),'+char(13)
	+'sum(winlost-actual_stake),'+char(13)
	+'sum(playercomm),'+char(13)
	+'sum(awinlost),'+char(13)
	+'sum(comm-playercomm),'+char(13)
	+'sum(mwinlost),'+char(13)
	+'sum(acomm-comm),'+char(13)
	+'sum(swinlost),'+char(13)
	+'sum(scomm-acomm),'+char(13)
	+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)),'+char(13)
	-------------RM--------------------
	+'sum(stake * b.actualrate),'+char(13)
	+'sum((1 - tpositiontaking)*stake * b.actualrate),'+char(13)
	+'sum(scomm * b.actualrate),'+char(13)
	+'sum((winlost-actual_stake) * b.actualrate),'+char(13)
	+'sum(playercomm * b.actualrate),'+char(13)
	+'sum(awinlost * b.actualrate),'+char(13)
	+'sum((comm-playercomm) * b.actualrate),'+char(13)
	+'sum(mwinlost * b.actualrate),'+char(13)
	+'sum((acomm-comm) * b.actualrate),'+char(13)
	+'sum(swinlost * b.actualrate),'+char(13)
	+'sum((scomm-acomm) * b.actualrate),'+char(13)
	+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm) * b.actualrate)'+char(13)
	
	+'FROM bettrans b with (nolock)'+char(13)
	+'INNER JOIN @SportBettype sb ON sb.Bettype = b.Bettype'+char(13)
	--+'INNER JOIN custinfo ci WITH(NOLOCK) ON ci.custid = b.custid'+char(13)
	+ CASE WHEN @UserRole = 4 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.mrecommend' 
			WHEN @UserRole = 3 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.recommend' 
			WHEN @UserRole = 2 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.custid'
			WHEN @UserRole = -1 THEN 'INNER JOIN CustInfo a ON a.custid = b.srecommend' 
	 ELSE ''
	 END + char(13)
	+CASE WHEN @GameTableID > 0 THEN 'INNER JOIN [match] m WITH(NOLOCK) ON m.matchid = b.matchid'+char(13)
									+'INNER JOIN league l WITH(NOLOCK) ON l.leagueid = m.leagueid'+char(13) 
	 ELSE ''
	 END + char(13)
	+CASE WHEN @SiteID <> 0 THEN 'LEFT JOIN 
									(
									SELECT lct.LicenseeID,lct.CustID
													FROM DBLIC.bodb_licensee.dbo.LicenseeCust lct with (nolock) 
													UNION ALL 
													SELECT tmp.LicenseeID,tmp.CustID
													FROM #tmpLicenseeDummy1  tmp
									)lc   on b.recommend = lc.custid' + char(13)
								+'LEFT JOIN DBLIC.bodb_licensee.dbo.Licensees lic with (nolock) on lc.LicenseeID = lic.LicenseeID' + char(13)
	 ELSE '' 
	 END
	+'WHERE winlostdate  >= @fromdate and winlostdate <= @todate'+char(13)
	---+'AND b.bettype BETWEEN 1101 AND 1199 AND b.ruben = 1' + char(13)
	+ CASE WHEN @ProductId <> 0 THEN 'AND sb.ProductID = '+ CONVERT(VARCHAR(3),@ProductId) + char(13) ELSE '' END
	+'AND sb.ProductID <> 21' + char(13) -- exclude Allbet
	+'AND b.ruben = 1' + char(13)
	+'AND statusid IN (111,112,113)'
	+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
	+ case when @SiteID > 0 then '	AND lc.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND lc.licenseeID is null' else '' end + char(13)
	+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
	+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
	+ case when @GameTableID > 0 then '	AND l.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else '' end--gametable filter
	+'GROUP BY b.Currency,'+char(13)
	+'a.UserName'+char(13)
	--+'b.actualrate'+char(13)

	-- Begin get AllBet Data
	IF(@ProductId = 0 or @ProductId = 21)
	BEGIN
		SELECT @TempDataSQL = @TempDataSQL + ' UNION ALL '
		+'SELECT a.UserName,'+char(13)
		+'b.Currency,'+char(13)	
		+'count(transid),'+char(13)
		+'sum(stake),'+char(13)
		+'sum((1 - tpositiontaking)*stake),'+char(13)
		+'sum(scomm),'+char(13)
		+'sum(winlost-actual_stake),'+char(13)
		+'sum(playercomm),'+char(13)
		+'sum(awinlost),'+char(13)
		+'sum(comm-playercomm),'+char(13)
		+'sum(mwinlost),'+char(13)
		+'sum(acomm-comm),'+char(13)
		+'sum(swinlost),'+char(13)
		+'sum(scomm-acomm),'+char(13)
		+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)),'+char(13)
		-------------RM--------------------
		+'sum(stake * b.actualrate),'+char(13)
		+'sum((1 - tpositiontaking)*stake * b.actualrate),'+char(13)
		+'sum(scomm * b.actualrate),'+char(13)
		+'sum((winlost-actual_stake) * b.actualrate),'+char(13)
		+'sum(playercomm * b.actualrate),'+char(13)
		+'sum(awinlost * b.actualrate),'+char(13)
		+'sum((comm-playercomm) * b.actualrate),'+char(13)
		+'sum(mwinlost * b.actualrate),'+char(13)
		+'sum((acomm-comm) * b.actualrate),'+char(13)
		+'sum(swinlost * b.actualrate),'+char(13)
		+'sum((scomm-acomm) * b.actualrate),'+char(13)
		+'-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm) * b.actualrate)'+char(13)
	
		+'FROM bettransLC b with (nolock)'+char(13)
		+'INNER JOIN @SportBettype sb ON sb.Bettype = b.gameID'+char(13)	
		+ CASE WHEN @UserRole = 4 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.mrecommend' 
				WHEN @UserRole = 3 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.recommend' 
				WHEN @UserRole = 2 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.custid'
				WHEN @UserRole = -1 THEN 'INNER JOIN CustInfo a ON a.custid = b.srecommend' 
		 ELSE ''
		 END + char(13)		
		+CASE WHEN @SiteID <> 0 THEN 'LEFT JOIN 
										(
										SELECT lct.LicenseeID,lct.CustID
														FROM DBLIC.bodb_licensee.dbo.LicenseeCust lct with (nolock) 
														UNION ALL 
														SELECT tmp.LicenseeID,tmp.CustID
														FROM #tmpLicenseeDummy1  tmp
										)lc   on b.recommend = lc.custid' + char(13)
									+'LEFT JOIN DBLIC.bodb_licensee.dbo.Licensees lic with (nolock) on lc.LicenseeID = lic.LicenseeID' + char(13)
		 ELSE '' 
		 END
		+'WHERE winlostdate  >= @fromdate and winlostdate <= @todate'+char(13)		
		+'AND sb.ProductID = 21' + char(13) -- Allbet	
		+'AND statusid IN (111,112,113)'
		+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
		+ case when @SiteID > 0 then '	AND lc.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND lc.licenseeID is null' else '' end + char(13)
		+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
		+ case when @GameTypeID > 0 then '	AND b.gameID = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter		
		+'GROUP BY b.Currency,'+char(13)
		+'a.UserName'+char(13)
	END
	-- End get AllBet Data
	
	---Querying in DW
	SELECT @TempDataSQLDW = @TempDataSQLDW +
			+'SELECT a.UserName,'+char(13)
			+'b.currency,'+char(13)
			--+'c.actualrate, '+char(13)
			+'SUM(b.betcount), '+char(13)
			+'SUM(b.stake), '+char(13)
			+'SUM(b.TurnoverIBC), '+char(13)
			+'SUM(b.CommissionS), '+char(13)
			+'SUM(b.WinlossP),'+char(13)
			+'SUM(b.CommissionP), '+char(13)
			+'SUM(b.WinlossA), '+char(13)
			+'SUM(b.CommissionA-b.CommissionP), '+char(13)
			+'SUM(b.WinlossM),'+char(13)
			+'SUM(b.CommissionM-b.CommissionA),'+char(13)
			+'SUM(b.WinlossS),'+char(13)
			+'SUM(b.CommissionS-b.CommissionM),'+char(13)
			+'-SUM(winlossIBC+CommissionS),'+char(13)
			
			+'SUM(b.stake * c.actualrate), '+char(13)
			+'SUM(b.TurnoverIBC * c.actualrate), '+char(13)
			+'SUM(b.CommissionS * c.actualrate), '+char(13)
			+'SUM(b.WinlossP * c.actualrate),'+char(13)
			+'SUM(b.CommissionP * c.actualrate), '+char(13)
			+'SUM(b.WinlossA * c.actualrate), '+char(13)
			+'SUM((b.CommissionA-b.CommissionP) * c.actualrate), '+char(13)
			+'SUM(b.WinlossM * c.actualrate),'+char(13)
			+'SUM((b.CommissionM-b.CommissionA) * c.actualrate),'+char(13)
			+'SUM(b.WinlossS * c.actualrate),'+char(13)
			+'SUM((b.CommissionS-b.CommissionM) * c.actualrate),'+char(13)
			+'-SUM((winlossIBC+CommissionS) * c.actualrate)'+char(13)
			
			+'FROM DBDW2.bodb_Account.dbo.mcCustLiveCasinoDaily b with (nolock)'+char(13)
			+'INNER JOIN @SportBettype sb ON sb.Bettype = b.Bettype'+char(13)
			+'INNER JOIN custinfo ci WITH(NOLOCK) ON ci.custid = b.custid'+char(13)
			+'INNER JOIN #tbl_Currency_Daily c with (nolock) on b.rptdate = c.exchangedate AND b.currency = c.exchangeid' + char(13)
			+CASE WHEN @SiteID <> 0 THEN 'LEFT JOIN DBDW2.bodb_Account.dbo.tbl_site s with (nolock) on b.siteid = s.siteid' + char(13)
										+'LEFT JOIN DBLIC.bodb_licensee.dbo.Licensees lic with (nolock) on s.site = lic.licenseeName' + char(13)
			 ELSE '' 
			 END
			+ CASE WHEN @UserRole = 4 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.mrecommend' 
					WHEN @UserRole = 3 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.recommend' 
					WHEN @UserRole = 2 THEN 'INNER JOIN #Agency a ON a.AgencyId = b.custid'
					WHEN @UserRole = -1 THEN 'INNER JOIN CustInfo a ON a.custid = b.srecommend' 
				ELSE ''
			END + char(13)
	+'WHERE rptDate  >= @fromdate AND rptDate <= @todate'+char(13)
	---+'AND b.bettype BETWEEN 1101 AND 1199' + char(13)
	+ CASE WHEN @ProductId <> 0 THEN 'AND sb.ProductID = '+ CONVERT(VARCHAR(3),@ProductId) + char(13) ELSE '' END
	--+'AND b.status IN (3,4,8)' + char(13)
	+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
	+ case when @SiteID > 0 then '	AND lic.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND s.isDeposit = 0' + char(13) else '' end
	+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
	+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
	+ case when @GameTableID > 0 then '	AND b.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else '' end--gametable filter
	+'GROUP BY b.currency,'+char(13)
	+'a.UserName'+char(13)
	--+'c.actualrate'+char(13)
	--DROP TABLE #tmpLicenseeDummy1
END
--------Process data source based on move bet day & balanceup day---------------------------------
select @sql = ''
IF @Todate > @MoveBetDay --get FROM bettrans  
BEGIN  
	IF @FromDate <= @MoveBetDay   
		SET @TempFromDate =  DATEADD(DAY,1,@MoveBetDay)  
	ELSE  
		SET @TempFromDate = @FromDate
		
	SELECT @sql = @sql + char(13) +  'INSERT INTO #Data('+CASE WHEN @ReportBy = 2 OR @ReportBy = 5 THEN 'UserName,' ELSE '' END
														+'Currency,'+char(13)
														--+'Rate,'+char(13)
														+CASE WHEN @ReportBy = 3 THEN 'BettypeId,' ELSE '' END
														+CASE WHEN @ReportBy = 4 THEN 'LeagueId,' ELSE '' END
														+'TotalBets,'+char(13)
														+'TotalTurnover,'+char(13)
														+'CompanyTurnOver,'+char(13)
														+'TotalComm,'+char(13)
														+'Winlost,'+char(13)
														+'PlayerComm,'+char(13)
														+'AWinlost,'+char(13)
														+'Comm,'+char(13)
														+'MWinlost,'+char(13)
														+'AComm,'+char(13)
														+'SWinlost,'+char(13)
														+'SComm,'+char(13)
														+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'TransDate,'+char(13) ELSE '' END
														+'CompanyWinLoss,'+char(13)
														
														+'TotalTurnover_RM,'+char(13)
														+'CompanyTurnOver_RM,'+char(13)
														+'TotalComm_RM,'+char(13)
														+'Winlost_RM,'+char(13)
														+'PlayerComm_RM,'+char(13)
														+'AWinlost_RM,'+char(13)
														+'Comm_RM,'+char(13)
														+'MWinlost_RM,'+char(13)
														+'AComm_RM,'+char(13)
														+'SWinlost_RM,'+char(13)
														+'SComm_RM,'+char(13)
														+'CompanyWinLoss_RM)'+char(13)
														+ @TempDataSQL + char(13)
														
														
	SELECT @sql = REPLACE(@sql, '@fromdate', '''' + convert(varchar(10),@TempFromDate,120) + '''')
	SELECT @sql = REPLACE(@sql, '@todate', '''' + convert(varchar(10),@ToDate,120) + '''')
	--select @sqlTableExchange = REPLACE(@sqlTableExchange, '@fromdate', '''' + convert(varchar(10),@TempFromDate,120) + '''')
	--select @sqlTableExchange = REPLACE(@sqlTableExchange, '@todate', '''' + convert(varchar(10),@ToDate,120) + '''')
END

IF @FromDate <= @MoveBetDay 
BEGIN
	IF @ToDate > @MoveBetDay
			SET @TempToDate = @MoveBetDay
		ELSE
			SET  @TempToDate = @ToDate
	
	select @sql = @sql + char(13) +  'INSERT INTO #Data('+CASE WHEN @ReportBy = 2 OR @ReportBy = 5 THEN 'UserName,' ELSE '' END
														+'Currency,'+char(13)
														--+'Rate,'+char(13)
														+CASE WHEN @ReportBy = 3 THEN 'BettypeId,' ELSE '' END
														+CASE WHEN @ReportBy = 4 THEN 'LeagueId,' ELSE '' END
														+'TotalBets,'+char(13)
														+'TotalTurnover,'+char(13)
														+'CompanyTurnOver,'+char(13)
														+'TotalComm,'+char(13)
														+'Winlost,'+char(13)
														+'PlayerComm,'+char(13)
														+'AWinlost,'+char(13)
														+'Comm,'+char(13)
														+'MWinlost,'+char(13)
														+'AComm,'+char(13)
														+'SWinlost,'+char(13)
														+'SComm,'+char(13)
														+CASE WHEN @ReportBy = 0 OR @ReportBy = 1 THEN 'TransDate,'+char(13) ELSE '' END
														+'CompanyWinLoss,'+char(13)
														
														+'TotalTurnover_RM,'+char(13)
														+'CompanyTurnOver_RM,'+char(13)
														+'TotalComm_RM,'+char(13)
														+'Winlost_RM,'+char(13)
														+'PlayerComm_RM,'+char(13)
														+'AWinlost_RM,'+char(13)
														+'Comm_RM,'+char(13)
														+'MWinlost_RM,'+char(13)
														+'AComm_RM,'+char(13)
														+'SWinlost_RM,'+char(13)
														+'SComm_RM,'+char(13)
														+'CompanyWinLoss_RM)'+char(13)
	-- Enhance Performance: 
	/*IF(@username='' AND @ReportBy <> 2 AND @ReportBy <> 5) -- this case: only read data in mcSiteDaily
	BEGIN
		SELECT @TempDataSQLDW = REPLACE(@TempDataSQLDW,'bodb_Account.dbo.MasterCube','bodb_Account.dbo.mcSiteDaily')
		SELECT @TempDataSQLDW = REPLACE(@TempDataSQLDW,'b.currency','b.currencyId')
		SELECT @sql = @sql + @TempDataSQLDW + char(13)
	END
	ELSE
	BEGIN*/
		select @sql = @sql + @TempDataSQLDW + char(13) 
		--SELECT @sql = @sql + 'UNION' + char(13) + REPLACE(@TempDataSQLDW, 'bodb_Account.dbo.MasterCube', 'bodb_Archive.dbo.MasterCube') + char(13)
	--END
	select @sql = REPLACE(@sql, '@fromdate', '''' + convert(varchar(10),@FromDate,120) + '''')
	select @sql = REPLACE(@sql, '@todate', '''' + convert(varchar(10),@TempToDate,120) + '''')
	--select @sqlTableExchange = REPLACE(@sqlTableExchange, '@fromdate', '''' + convert(varchar(10),@FromDate,120) + '''')
	--select @sqlTableExchange = REPLACE(@sqlTableExchange, '@todate', '''' + convert(varchar(10),@TempToDate,120) + '''')
END


--summary section by currencies + grand total
SELECT @sql = @sql + char(13) 
			+'SELECT d.Currency as CurrencyId,' + char(13)
			+'ex.Currency,' + char(13)
			+CASE WHEN @ReportBy = 5 OR @ReportBy = 2 THEN 'username,' 
					WHEN @ReportBy = 0 THEN 'CONVERT(varchar,TransDate,111) as Date,'
					WHEN @ReportBy = 1 THEN 'CAST(YEAR(TransDate) AS VARCHAR) +''-''+ CAST(MONTH(TransDate) AS VARCHAR) AS Month,'
					WHEN @ReportBy = 3 THEN 'BettypeId AS GameType,'
					WHEN @ReportBy = 4 THEN 'LeagueId AS GameTable,'
				ELSE '' 
			 END + char(13)
			+ 'SUM(TotalBets) AS "Bets",' + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(TotalTurnover_RM) AS "RollingTO",' ELSE 'SUM(TotalTurnover) AS "RollingTO",' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(CompanyTurnOver_RM) AS "CompanyTO",' ELSE 'SUM(CompanyTurnOver) AS "CompanyTO",' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(TotalComm_RM) AS "GrossComm",' ELSE 'SUM(TotalComm) AS "GrossComm",' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(Winlost_RM) AS Winloss,' ELSE 'SUM(Winlost) AS Winloss,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(PlayerComm_RM) AS PlayerComm,' ELSE 'SUM(PlayerComm) AS PlayerComm,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(AWinlost_RM) AS AWinloss,' ELSE 'SUM(AWinlost) AS AWinloss,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(Comm_RM) AS Comm,' ELSE 'SUM(Comm) AS Comm,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(MWinlost_RM) AS MWinloss,' ELSE 'SUM(MWinlost) AS MWinloss,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(AComm_RM) AS AComm,' ELSE 'SUM(AComm) AS AComm,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(SWinlost_RM) AS SWinloss,' ELSE 'SUM(SWinlost) AS SWinloss,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(SComm_RM) AS SComm,' ELSE 'SUM(SComm) AS SComm,' END + char(13)
			+ CASE WHEN @currency = -1 THEN 'SUM(CompanyWinLoss_RM) AS CompanyWinLoss' ELSE 'SUM(CompanyWinLoss) AS CompanyWinLoss' END +char(13)
			+ 'FROM #Data d' + char(13)
			+ 'INNER JOIN exchange AS ex WITH (NOLOCK) ON ex.exchangeid = d.Currency'+char(13)
			+ 'GROUP BY d.Currency,ex.Currency,' + char(13)
			+ CASE WHEN @ReportBy = 0 THEN 'CONVERT(varchar,TransDate,111)'
					WHEN @ReportBy = 1 THEN 'YEAR(TransDate),MONTH(TransDate)'
					WHEN @ReportBy = 3 THEN 'BettypeId'
					WHEN @ReportBy = 4 THEN 'LeagueId'
					WHEN @ReportBy = 5 OR @ReportBy = 2 THEN 'username' 
			 ELSE '' 
			 END + char(13)

IF(@currency=-1)
BEGIN
	SELECT @sql = @sql + char(13)
			+ 'SELECT CAST(d.Currency AS varchar)  as CurrencyId,' + char(13)
			+ 'ex.Currency,' + char(13)
			+ 'SUM(TotalBets) AS "Bets",' + char(13)
			+ 'SUM(TotalTurnover_RM) AS "RollingTO",' + char(13)
			+ 'SUM(CompanyTurnOver_RM) AS "CompanyTO",' + char(13)
			+ 'SUM(TotalComm_RM) AS "GrossComm",' + char(13)
			+ 'SUM(Winlost_RM) AS Winloss,' + char(13)
			+ 'SUM(PlayerComm_RM) AS PlayerComm,' + char(13)
			+ 'SUM(AWinlost_RM) AS AWinloss,' + char(13)
			+ 'SUM(Comm_RM) AS Comm,' + char(13)
			+ 'SUM(MWinlost_RM) AS MWinloss,' + char(13)
			+ 'SUM(AComm_RM) AS AComm,' + char(13)
			+ 'SUM(SWinlost_RM) AS SWinloss,' + char(13)
			+ 'SUM(SComm_RM) AS SComm,' + char(13)
			+ 'SUM(CompanyWinLoss_RM) AS CompanyWinLoss'+char(13)
			+ 'FROM #Data d' + char(13)
			+ 'INNER JOIN exchange AS ex WITH (NOLOCK) ON ex.exchangeid = d.Currency'+char(13)
			+ 'GROUP BY d.Currency,ex.Currency' + char(13)
END
ELSE
BEGIN
	SELECT @sql = @sql + char(13)
			+ 'SELECT CAST(d.Currency AS varchar) as CurrencyId,' + char(13)
			+ 'ex.Currency,' + char(13)
			+ 'SUM(TotalBets) AS "Bets",' + char(13)
			+ 'SUM(TotalTurnover) AS "RollingTO",' + char(13)
			+ 'SUM(CompanyTurnOver) AS "CompanyTO",' + char(13)
			+ 'SUM(TotalComm) AS "GrossComm",' + char(13)
			+ 'SUM(Winlost) AS Winloss,' + char(13)
			+ 'SUM(PlayerComm) AS PlayerComm,' + char(13)
			+ 'SUM(AWinlost) AS AWinloss,' + char(13)
			+ 'SUM(Comm) AS Comm,' + char(13)
			+ 'SUM(MWinlost) AS MWinloss,' + char(13)
			+ 'SUM(AComm) AS AComm,' + char(13)
			+ 'SUM(SWinlost) AS SWinloss,' + char(13)
			+ 'SUM(SComm) AS SComm,' + char(13)
			+ 'SUM(CompanyWinLoss) AS CompanyWinLoss'+char(13)
			+ 'FROM #Data d' + char(13)
			+ 'INNER JOIN exchange AS ex WITH (NOLOCK) ON ex.exchangeid = d.Currency'+char(13)
			+ 'GROUP BY d.Currency,ex.Currency' + char(13)
			
END
-----------------Process Grandtotal-----------------------
SELECT @sql = @sql + char(13)
			+ 'UNION'+char(13)
			+ 'SELECT ''ZZZGRANDTOTALRM'' as GRANDTOTALRM ,'+char(13)
			+ '''ZZZAll'' as "All",'+char(13)
			+ 'SUM(TotalBets) AS "Bets",' + char(13)
			+ 'SUM(TotalTurnover_RM) AS "RollingTO",' + char(13)
			+ 'SUM(CompanyTurnOver_RM) AS "CompanyTO",' + char(13)
			+ 'SUM(TotalComm_RM) AS "GrossComm",' + char(13)
			+ 'SUM(Winlost_RM) AS Winloss,' + char(13)
			+ 'SUM(PlayerComm_RM) AS PlayerComm,' + char(13)
			+ 'SUM(AWinlost_RM) AS AWinloss,' + char(13)
			+ 'SUM(Comm_RM) AS Comm,' + char(13)
			+ 'SUM(MWinlost_RM) AS MWinloss,' + char(13)
			+ 'SUM(AComm_RM) AS AComm,' + char(13)
			+ 'SUM(SWinlost_RM) AS SWinloss,' + char(13)
			+ 'SUM(SComm_RM) AS SComm,' + char(13)
			+ 'SUM(CompanyWinLoss_RM) AS CompanyWinLoss'+char(13)
			+ 'FROM #Data' + char(13)
			+ 'ORDER BY ex.Currency ASC' + char(13)

SELECT @sql = @sql + 'SELECT '+CASE WHEN @UserRole = -1 THEN '4 AS ShowDetail' WHEN @UserRole IS NULL THEN '-2 AS ShowDetail' ELSE cast( (@UserRole-1) AS varchar(4)) +' AS ShowDetail' END
SELECT @sql = @sqlTableExchange + @sql

 
IF(@Debug=1)
	print @sql

EXEC (@sql)


/*
exec age_selBalanceupday
Acc_Rpt_LiveCasino_GameStatistics_GameTableSel

exec [dbo].Acc_Rpt_LiveCasino_AgencyWinLoss
	@fromdate = '2012-8-15',
	@todate = '2012-8-31',
	@username = '',
	@excludeTest = 1,
	@SiteID = 0,	
	@GameTypeID = 0,
	@GameTableID = 0,--leagueid
	@currency = 0,
	@ReportBy = 3,
	@MoveBetDay = '2012-08-17',
    @Debug = 1

select [ExchangeDate], [ExchangeId],[ActualRate] 
    from ExchangeDailyOanda with (nolock) 
    where exchangedate between '2012-08-01' AND '2012-08-15'
    AND ExchangeId = 16
*/

DROP TABLE #Data
DROP TABLE #Agency


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LiveCasino_AgencyWinLoss] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_LiveCasino_AgencyWinLoss] TO [bodbAdminNet]
GO 
