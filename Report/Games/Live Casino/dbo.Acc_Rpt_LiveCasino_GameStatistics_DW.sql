ALTER PROCEDURE [dbo].[Acc_Rpt_LiveCasino_GameStatistics_DW]
	@fromdate datetime,
	@todate datetime,
	@username varchar(50) = '',
	@excludeTest BIT = 0,
	@SiteID smallint = 0,	
	@GameTypeID smallint = 0,
	@GameTableID smallint = 0,--leagueid
	@currency smallint = 0,
	@ReportBy tinyint = 0,
	@MoveBetDay smalldatetime,
    @Debug BIT = 0
AS
/*
Created: 20120216@Daniel
Task : SP for Live Casino Game statistic report
DB: DBDW2 + Get recent live data from DB06

Revisions:
			20120507@Minzy: Replace @custfilter by temporary table
			20120523@Dom:  Add another 2 columns - Company T/O and Company Comm
		Daniel@20120606: Change to get ex rate from IBC's exchangedaily to improve performance
		Daniel@20120611: Use new separated table to speed up report
		Daniel@20120710: Move SP from DB06 to DBDW2 to avoid high-loading remote query from DBDW2 to DB06
Param's Explanation:

 - @username: 
    + Search by keyword, member only

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
  5: Company (Site IBC/Licesees)
  6: currency
*/

DECLARE @sql varchar(max), @sqlTableExchange nvarchar(max), @sqlbettrans nvarchar(max), @sqlDW nvarchar(max), @TempFromDate smalldatetime, @TempToDate smalldatetime, @TempTable nvarchar(max)
DECLARE @ColumnList varchar(1500)--, @custfilter nvarchar(max)
DECLARE @groupBy varchar(max)
DECLARE @MemIDs varchar(max)
DECLARE @SqlMatch varchar(max)
CREATE TABLE #Temp_MemIDs(MemID INT)

SELECT @sqlTableExchange = 'create table #tbl_Currency_Daily
    (
     [ExchangeDate] smalldatetime,
     [ExchangeId] int,
     [ActualRate] float
    )
    create clustered index #IX_curr ON #tbl_Currency_Daily([ExchangeDate],[ExchangeId])

    insert into #tbl_Currency_Daily
    select [ExchangeDate], [ExchangeId],[ActualRate] 
    from bodb02.dbo.ExchangeDailyOanda with (nolock) 
    where exchangedate between '''+convert(varchar(10),@fromdate,120)+''' AND '''+convert(varchar(10),@todate,120)+'''' + char(13)


SELECT @TempTable = 'CREATE TABLE #TempLC' + char(13) + '(' + char(13) + '	' +
	case @ReportBy
        when 0 then '[Date] smalldatetime,' + char(13)
        when 1 then '[Year] smallint, [Month] tinyint,' + char(13)
        when 2 then 'custid int,' + char(13)
        when 3 then 'bettype int,' + char(13)
        when 4 then 'leagueid int,' + char(13)
		when 5 then 'company varchar(50),' + char(13)
		when 6 then 'Currency int,' + char(13)
        else ''
    end
	--+ '	matchid int,' + char(13)
	+ case when @reportby <> 2 then '	custid int,' + char(13) else '' end
	+ case when @reportby <> 6 then '	currency int,' + char(13) else '' end
	+ '	TotalBets money,' + char(13)
	+ '	TotalWins money,' + char(13)
	+ '	TotalRefund money,' + char(13)
	+ '	CompanyNetIncome money,' + char(13)
	+ ' CompanyTurnOver money,' + char(13)
	+ ' CompanyComm money,' + char(13)
	+ ' CompanyTurnOver_RM money,' + char(13)
	+ ' CompanyComm_RM money,' + char(13)
	+ '	TotalBets_RM money,' + char(13)
	+ '	TotalWins_RM money,' + char(13)
	+ '	TotalRefund_RM money,' + char(13)
	+ '	CompanyNetIncome_RM money' + char(13) + ')' + char(13)


SELECT @TempTable = @TempTable + char(13) + 
'CREATE CLUSTERED INDEX #IX_TempLC ON #TempLC' + char(13) + '(' + char(13) + '	' +
	case @ReportBy
        when 0 then '[Date],' + char(13)
        when 1 then '[Year], [Month],' + char(13)
        when 2 then 'custid,' + char(13)
        when 3 then 'bettype,' + char(13)
        when 4 then 'leagueid,' + char(13)
		when 5 then 'company,' + char(13)
        else ''
    end
	--+ '	matchid,' + char(13)
	+ case when @reportby <> 2 then '	custid,' + char(13) else '' end
	+ '	currency' + char(13)
    + char(13) + ')WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON)'  + char(13)

SELECT @TempTable = @TempTable + char(13) 
+ 'create table #matches ('+case @ReportBy
								when 0 then '[Date] datetime,' + char(13)
								when 1 then '[Year] int, [Month] int,' + char(13)
								when 2 then 'custid int,' + char(13)
								when 3 then 'bettype int,' + char(13)
								when 4 then 'leagueid int,' + char(13)
								when 5 then 'company varchar(50),' + char(13)
								else ''
							END+CHAR(13)
							+'currency int ,matchid int)'+CHAR(13)

SELECT @TempTable = @TempTable + char(13) 
+ 'create table #countmatches ('+case @ReportBy
								when 0 then '[Date] datetime,' + char(13)
								when 1 then '[Year] int, [Month] int,' + char(13)
								when 2 then 'custid int,' + char(13)
								when 3 then 'bettype int,' + char(13)
								when 4 then 'leagueid int,' + char(13)
								when 5 then 'company varchar(50),' + char(13)
								else ''
							END+CHAR(13)
							+'currency int ,numofgames bigint)'+CHAR(13)



+ 'create table #countmatchesbycurrency (currency int ,numofgames bigint)'+CHAR(13)

SELECT @TempTable = @TempTable + char(13) 
+'CREATE TABLE #AllMatches(numofgames bigint)'+CHAR(13)							

if(isnull(@username,'') <> '')
BEGIN
	INSERT INTO #Temp_MemIDs(MemID)
    SELECT custid
    FROM bodb02.dbo.custinfo with (nolock)
    WHERE username like + @username + '%' and roleid = 1	
END

-------------get from bettrans---------------------------------------------------------------
SELECT @groupBy = char(13) + '	' +
    case @ReportBy
        when 0 then 'winlostdate,'
        when 1 then 'year(winlostdate) [Year], month(winlostdate) [Month],'
        when 2 then 'b.custid,'
        when 3 then 'b.bettype,'
        when 4 then 'm.leagueid,'
		when 5 then 'case when lc.custid is null then ''IBC'' else lic.LicenseeName end company,'
		when 6 then 'b.currency,'
        else ''
    end + char(13) --+ '	b.matchid,' + char(13)
	+ case when @ReportBy <> 2 then'	b.custid,' else '' end
	+ case when @ReportBy <> 6 then'	b.currency,' else '' end

SELECT @ColumnList = @groupBy + char(13)
+ '	sum(case when statusid IN(101,102,103) then 0 else stake end) TotalBets,' + char(13)
+ '	sum(case when statusid IN(101,102,103) then 0 else winlost end) TotalWins,' + char(13)
+ '	sum(case when statusid IN(101,102,103) then stake else 0 end) TotalRefund,' + char(13)
+ '	-sum(winlost-actual_stake+awinlost+mwinlost+swinlost+scomm) CompanyNetIncome,' + char(13)
+ ' sum((1-tpositiontaking)*stake) CompanyTurnOver,' + char(13)
+ ' -sum(scomm) CompanyComm,' + char(13)
+ ' sum((1-tpositiontaking)*stake*b.actualrate) CompanyTurnOver_RM,' + char(13)
+ ' -sum(scomm*b.actualrate) CompanyComm_RM,' + char(13)
+ '	sum(case when statusid IN(101,102,103) then 0 else stake end*b.actualrate) TotalBets_RM,' + char(13)
+ '	sum(case when statusid IN(101,102,103) then 0 else winlost end*b.actualrate) TotalWins_RM,' + char(13)
+ '	sum(case when statusid IN(101,102,103) then stake else 0 end*b.actualrate) TotalRefund_RM,' + char(13)
+ '	-sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*b.actualrate) CompanyNetIncome_RM'


SELECT @sqlbettrans = 'SELECT ' + @ColumnList + char(13) + 'from DB06.bodb02.dbo.bettrans b with (nolock)' + char(13) 


if (@ReportBy = 2)--get customer info if search/group by username
    SELECT @sqlbettrans = @sqlbettrans + '   inner join bodb02.dbo.custinfo ci with (nolock) on b.custid = ci.custid' + char(13)     

if (@ReportBy = 4 or @GameTableID > 0)--by game table
    SELECT @sqlbettrans = @sqlbettrans + '   inner join bodb02.dbo.match m with (nolock) on b.matchid = m.matchid' + char(13)

if (@ReportBy = 5 or @SiteID <> 0)--if group by comany or have site filter then get licenseeID
    SELECT @sqlbettrans = @sqlbettrans + '   left join DB052.bodb_licensee.dbo.LicenseeCust lc with (nolock) on b.recommend = lc.custid' + char(13)

if (@ReportBy = 5)--by Company: Get licensee name
	SELECT @sqlbettrans = @sqlbettrans + '   left join DB052.bodb_licensee.dbo.Licensees lic with (nolock) on lc.LicenseeID = lic.LicenseeID' + char(13)

select @sqlbettrans = @sqlbettrans + '  inner join bodb02.dbo.exchange e with (nolock) on b.currency = e.exchangeid' + char(13)

if(isnull(@username,'') <> '')
	select @sqlbettrans = @sqlbettrans + '  inner join #Temp_MemIDs t with (nolock) on b.custid = t.MemID' + char(13)


SELECT @sqlbettrans = @sqlbettrans 
+ 'WHERE b.bettype BETWEEN 1101 AND 1199 AND b.ruben = 1 AND statusid <> 121' + char(13) --+ @custfilter
+ '	AND winlostdate between @fromdate AND @todate' + char(13)
+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
+ case when @SiteID > 0 then '	AND lc.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND lc.licenseeID is null' else '' end
+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
+ case when @GameTableID > 0 then '	AND m.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else char(13) end--gametable filter


--process groupby clause
SELECT @groupBy = REPLACE(@groupBy, '[Month]', '')
SELECT @groupBy = REPLACE(@groupBy, '[Year]', '')
SELECT @groupBy = REPLACE(@groupBy, 'company', '')
SELECT @groupBy = LEFT(@groupBy, LEN(@groupBy)-1)    

SELECT @sqlbettrans = @sqlbettrans + 'group by ' + @groupBy

-------------end get from bettrans---------------------------------------------------------------


-----------------Get from DW---------------------------------------------------------------------

										
SELECT @groupBy = char(13) + '	' +
    case @ReportBy
        when 0 then 'rptdate,'
        when 1 then 'year(rptdate) [Year], month(rptdate) [Month],'
        when 2 then 'b.custid,'
        when 3 then 'b.bettype,'
        when 4 then 'b.leagueid,'
		when 5 then 'case when s.IsDeposit = 0 then ''IBC'' else lic.LicenseeName end company,'
		when 6 then 'b.currency,'
        else ''
    end + char(13) --+ '	b.matchid,' + char(13)
	+ case when @ReportBy <> 2 then'	b.custid,' else '' end
	+ case when @ReportBy <> 6 then'	b.currency,' else '' end

SELECT @ColumnList = @groupBy + char(13)
+ '	sum(stake) TotalBets,' + char(13)
+ '	sum(winlossP+stake) TotalWins,' + char(13)
+ '	sum(stakerefund) TotalRefund,' + char(13)
+ '	-sum(winlossIBC+CommissionS) CompanyNetIncome,' + char(13)
+ ' sum(TurnoverIBC) CompanyTurnOver,' + char(13)
+ ' -sum(CommissionS) CompanyComm,' + char(13)
+ ' sum(TurnoverIBC*c.actualrate) CompanyTurnOver_RM,' + char(13)
+ ' -sum(CommissionS*c.actualrate) CompanyComm_RM,' + char(13)
+ '	sum(stake*c.actualrate) TotalBets_RM,' + char(13)
+ '	sum((winlossP+stake)*c.actualrate) TotalWins_RM,' + char(13)
+ '	sum(stakerefund*c.actualrate) TotalRefund_RM,' + char(13)
+ '	-sum((winlossIBC+CommissionS)*c.actualrate) CompanyNetIncome_RM'
/*
if(@currency > 0)
    SELECT @ColumnList = REPLACE(@ColumnList,'*c.actualrate','')
*/

SELECT @sqlDW = 'SELECT ' + @ColumnList + char(13) + 'from bodb_account.dbo.mcCustLiveCasinoDaily b with (nolock)' + char(13) 

SELECT @sqlDW = @sqlDW + '   inner join #tbl_Currency_Daily c with (nolock) on b.rptdate = c.exchangedate AND b.currency = c.exchangeid' + char(13)
--	+ '	left join DBDW2.bodb_account.dbo.league l with (nolock) on b.leagueid = l.leagueid' + char(13)

if (@ReportBy = 2)--get customer info if group by username
    SELECT @sqlDW = @sqlDW + '   left join bodb02.dbo.custinfo ci with (nolock) on b.custid = ci.custid' + char(13)     

if (@ReportBy = 5 or @SiteID <> 0)--if group by company or have site filter then get licenseeID
    SELECT @sqlDW = @sqlDW
    + '   left join bodb_Account.dbo.tbl_site s with (nolock) on b.siteid = s.siteid' + char(13)
	+ '   left join DB052.bodb_licensee.dbo.Licensees lic with (nolock) on s.site = lic.licenseeName' + char(13)

select @sqlDW = @sqlDW + '  inner join bodb02.dbo.exchange e with (nolock) on b.currency = e.exchangeid' + char(13)

if(isnull(@username,'') <> '')
	select @sqlDW = @sqlDW + '  inner join #Temp_MemIDs t with (nolock) on b.custid = t.MemID' + char(13)


SELECT @sqlDW = @sqlDW 
+ '	WHERE rptdate between @fromdate AND @todate' + char(13)
--+ '	and l.sportid = 162	and isLive = 0' + char(13) 
+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
+ case when @SiteID > 0 then '	AND lic.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND s.isDeposit = 0' + char(13) else '' end
+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
+ case when @GameTableID > 0 then '	AND b.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else char(13) end--gametable filter

--process groupby clause
SELECT @groupBy = REPLACE(@groupBy, '[Month]', '')
SELECT @groupBy = REPLACE(@groupBy, '[Year]', '')
SELECT @groupBy = REPLACE(@groupBy, 'company', '')
SELECT @groupBy = LEFT(@groupBy, LEN(@groupBy)-1)    

SELECT @sqlDW = @sqlDW
+ 'group by ' + @groupBy

-----------------Get from DW---------------------------------------------------------------------


--------Process data source based on move bet day & balanceup day------------------------------------------------
select @sql = ''
SELECT @SqlMatch = ''
IF @Todate > @MoveBetDay --get FROM bettrans  
BEGIN  
	IF @FromDate <= @MoveBetDay   
		SET @TempFromDate =  DATEADD(DAY,1,@MoveBetDay)  
	ELSE  
		SET @TempFromDate = @FromDate
	--{Dom.Cao}---Process Match count--------------------------
	SELECT @SqlMatch = @SqlMatch +CHAR(13)
			+'insert into #matches'+CHAR(13)
			+' select distinct '+case @ReportBy
									when 0 then 'winlostdate [date],'
									when 1 then 'year(winlostdate) [Year], month(winlostdate) [Month],'
									when 2 then 'b.custid,'
									when 3 then 'b.bettype,'
									when 4 then 'm.leagueid,'
									when 5 then 'case when lc.custid is null then ''IBC'' else lic.LicenseeName end,'
									else ''
								end + 'b.currency, b.matchid'+CHAR(13)
			+'from DB06.bodb02.dbo.bettrans b with (nolock)'+CHAR(13)
			+CASE WHEN @ReportBy = 4 OR @GameTableID > 0 THEN  
				'inner join bodb02.dbo.match m with (nolock) on b.matchid = m.matchid'+CHAR(13) 
			ELSE '' END
			+CASE WHEN @ReportBy=5 OR @SiteID <> 0 THEN 
				'left join DB052.bodb_licensee.dbo.LicenseeCust lc with (nolock) on b.recommend = lc.custid'+CHAR(13)
			ELSE '' END
			+CASE WHEN @ReportBy=5 THEN 
				'left join DB052.bodb_licensee.dbo.Licensees lic with (nolock) on lc.LicenseeID = lic.LicenseeID'+CHAR(13)
			ELSE '' END
			+CASE WHEN ISNULL(@username,'') <> '' THEN
				'inner join #Temp_MemIDs t with (nolock) on b.custid = t.MemID'+CHAR(13)
			ELSE '' END
			+'where b.winlostdate between @fromdate and @todate'+CHAR(13)		
			+'AND b.bettype BETWEEN 1101 AND 1199 AND b.ruben = 1 AND statusid <> 121'+CHAR(13)
			+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
			+ case when @SiteID > 0 then '	AND lc.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND lc.licenseeID is null' else '' end
			+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
			+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
			+ case when @GameTableID > 0 then '	AND m.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else char(13) end--gametable filter
	--{/Dom.Cao}
	select @sql = @sql + char(13) + 'INSERT INTO #TempLC' + char(13) + @sqlbettrans	+ char(13) + @SqlMatch + CHAR(13)
	select @sql = REPLACE(@sql, '@fromdate', '''' + convert(varchar(10),@TempFromDate,120) + '''')
	select @sql = REPLACE(@sql, '@todate', '''' + convert(varchar(10),@ToDate,120) + '''')
END		
		
IF @FromDate <= @MoveBetDay 
BEGIN
	IF @ToDate > @MoveBetDay
			SET @TempToDate = @MoveBetDay
		ELSE
			SET  @TempToDate = @ToDate
	--{Dom.Cao}---Process Match count--------------------------
	SELECT @SqlMatch = ''
	SELECT @SqlMatch = @SqlMatch +CHAR(13)
			+'insert into #matches'+CHAR(13)
			+' select distinct '+case @ReportBy
									when 0 then 'rptdate [date],'
									when 1 then 'year(rptdate) [Year], month(rptdate) [Month],'
									when 2 then 'b.custid,'
									when 3 then 'b.bettype,'
									when 4 then 'b.leagueid,'
									when 5 then 'case when s.IsDeposit = 0 then ''IBC'' else lic.LicenseeName end company,'
									else ''
								end + 'b.currency, matchid'+CHAR(13)
			+'from bodb_account.dbo.mcCustLiveCasinoDaily b with (nolock)'+CHAR(13)
			+CASE WHEN @ReportBy=5 OR @SiteID <> 0 THEN 
				'left join bodb_Account.dbo.tbl_site s with (nolock) on b.siteid = s.siteid' + char(13)
				+'left join DB052.bodb_licensee.dbo.Licensees lic with (nolock) on s.site = lic.licenseeName' + char(13)
			ELSE '' END
			+CASE WHEN ISNULL(@username,'')<>'' THEN
				+'inner join #Temp_MemIDs t with (nolock) on b.custid = t.MemID'+CHAR(13)
			ELSE '' END
			+'where b.rptdate between @fromdate and @todate'+CHAR(13)
			+ case when @excludeTest = 1 then '	AND	b.currency <> 20' + char(13) else '' end
			+ case when @SiteID > 0 then '	AND lic.licenseeID = ' + convert(varchar(3),@SiteID) + char(13) when @siteid = -1 then 'AND s.isDeposit = 0' + char(13) else '' end
			+ case when @currency > 0 then '	AND b.currency = ' + convert(varchar(2),@currency) + char(13) else '' end
			+ case when @GameTypeID > 0 then '	AND b.bettype = ' + convert(varchar(5),@GameTypeID) + char(13) else '' end--gametype filter
			+ case when @GameTableID > 0 then '	AND b.leagueid = ' + convert(varchar(5),@GameTableID) + char(13) else char(13) end--gametable filter
			
	--{/Dom.Cao}
				
	select @sql = @sql + char(13) + 'INSERT INTO #TempLC' + char(13) + @sqlDW	+ char(13) + @SqlMatch + CHAR(13)
	select @sql = REPLACE(@sql, '@fromdate', '''' + convert(varchar(10),@FromDate,120) + '''')
	select @sql = REPLACE(@sql, '@todate', '''' + convert(varchar(10),@TempToDate,120) + '''')	
END

--{Dom.Cao} process total match
DECLARE @sqlNumMatches VARCHAR(MAX)
SELECT @sqlNumMatches = ''
SELECT @sqlNumMatches = @sqlNumMatches +'INSERT INTO #countmatches'+CHAR(13) 
										+'SELECT '+ case @ReportBy
														when 0 then '[date],'
														when 1 then '[Year], [Month],'
														when 2 then 'b.custid,'
														when 3 then 'b.bettype,'
														when 4 then 'b.leagueid,'
														when 5 then 'b.company,'
														else ''
													END + 'b.currency, count(distinct matchid) numofgames' + CHAR(13)
										+'FROM #matches b with (nolock)'+CHAR(13)
										+'GROUP BY '+case @ReportBy
														when 0 then '[date],'
														when 1 then '[Year], [Month],'
														when 2 then 'b.custid,'
														when 3 then 'b.bettype,'
														when 4 then 'b.leagueid,'
														when 5 then 'b.company,'
														else ''
													END+'b.currency'+CHAR(13)
													
										+'INSERT INTO #CountMatchesByCurrency'+CHAR(13)
										+'SELECT b.currency, count(distinct matchid) numofgames' + CHAR(13)
										+'FROM #matches b with (nolock)'+CHAR(13)
										+'GROUP BY b.currency'+CHAR(13)
										
										+'INSERT INTO #AllMatches'+CHAR(13)
										+'SELECT count(distinct matchid) numofgames' + CHAR(13)
										+'FROM #matches b with (nolock)'+CHAR(13)
										
select @sql = @sql+CHAR(13)+@sqlNumMatches
--{/Dom.Cao}


select @sql = @sql + 'SELECT ' + char(13) +
    case @ReportBy
        when 0 then 'b.[Date],'
        when 1 then 'b.[Year], b.[Month],'
        when 2 then 'ci.username,'
        when 3 then 'b.bettype gametypeid,'
        when 4 then 'b.leagueid gametableid,'
		when 5 then 'b.company,'
		when 6 then 'e.Currency,'
        else ''
    end + char(13)
	+ case when @ReportBy <> 2 then '	COUNT(DISTINCT b.custid) NoOfPlayers,' + char(13) else '' end
	+ '	min(numofgames) NoOfGames,' + char(13)
	+ case when @ReportBy <> 6 then '	e.Currency,' + char(13) else '' end
	+ '	SUM(TotalBets@Convert) TotalBets,' + char(13)
	+ '	SUM(TotalBets_RM) TotalBets_RM,' + char(13)
	+ '	SUM(TotalWins@Convert) TotalWins,' + char(13)
	+ '	SUM(TotalWins_RM) TotalWins_RM,' + char(13)
	+ '	SUM(TotalBets@Convert) - SUM(TotalWins@Convert) GameIncome,' + char(13)
	+ '	SUM(TotalBets_RM) - SUM(TotalWins_RM) GameIncome_RM,' + char(13)
	+ '	case when sum(TotalBets@Convert) = 0 then 0 else (SUM(TotalWins@Convert)*100)/sum(TotalBets@Convert) end GamePayout,' + char(13)	
	+ '	case when sum(TotalBets_RM) = 0 then 0 else (SUM(TotalWins_RM)*100)/sum(TotalBets_RM) end GamePayout_RM,' + char(13)	
	+ '	SUM(TotalRefund@Convert) TotalRefund,' + char(13)
    + '	SUM(TotalRefund_RM) TotalRefund_RM,' + char(13)	
	+ '	SUM(CompanyNetIncome@Convert) CompanyNetIncome,' + char(13)
    + '	SUM(CompanyNetIncome_RM) CompanyNetIncome_RM,' + char(13)
	+ ' SUM(CompanyTurnOver@Convert) CompanyTurnOver,' + char(13)
	+ ' SUM(CompanyTurnOver_RM) CompanyTurnOver_RM,' + char(13)
	+ ' SUM(CompanyComm@Convert) CompanyComm,' + char(13)
	+ ' SUM(CompanyComm_RM) CompanyComm_RM' + char(13)
	+ 'FROM #TempLC b' + char(13)
	+ 'left JOIN #CountMatches n ON n.currency = b.currency '+ case @ReportBy
																		when 0 then ' and b.[Date] = n.date'
																		when 1 then ' and b.[Year]=n.year and b.[Month] = n.month'
																		when 2 then ' and b.custid = n.custid'
																		when 3 then ' and b.bettype = n.bettype'
																		when 4 then ' and b.leagueid = n.leagueid'
																		when 5 then ' and b.company = n.company'
																		else ''
																	end +CHAR(13)
    + CASE WHEN @ReportBy=2 THEN  
    	'   left join bodb02.dbo.custinfo ci with (nolock) on b.custid = ci.custid' + char(13)
    ELSE '' END
	+ 'inner join bodb02.dbo.exchange e with (nolock) on b.currency = e.exchangeid' + char(13)
	+ 'GROUP BY' + char(13) + '	' +
	case @ReportBy
        when 0 then 'b.[Date],'
        when 1 then 'b.[Year], b.[Month],'
        when 2 then 'ci.username,'
        when 3 then 'b.bettype,'
        when 4 then 'b.leagueid,'
		when 5 then 'b.company,'
		when 6 then 'e.Currency,'
        else ''
    end 
	+ case when @ReportBy <> 6 then char(13) + '	e.currency,' else '' end


SELECT @sql = LEFT(@sql, LEN(@sql)-1)
SELECT @sql = @sql + char(13) + '	ORDER BY ' +
	case @ReportBy
        when 0 then 'b.[Date]'
        when 1 then 'b.[Year], b.[Month]'
        when 2 then 'ci.username'
        when 3 then 'b.bettype'
        when 4 then 'b.leagueid'
		when 5 then 'company'
		when 6 then 'e.Currency'
        else ''
    end 

--summary section by currencies + grand total
select @sql = @sql + char(13) + 'SELECT e.Currency,' + char(13)
	+ case when @ReportBy <> 2 then '	COUNT(DISTINCT custid) NoOfPlayers,' + char(13) else '' end
	+ '	min(numofgames) NoOfGames,' + char(13)
	+ case when @ReportBy <> 6 then '	e.Currency,' + char(13) else '' end
	+ '	SUM(TotalBets@Convert) TotalBets,' + char(13)
	+ '	SUM(TotalWins@Convert) TotalWins,' + char(13)
	+ '	SUM(TotalBets@Convert) - SUM(TotalWins@Convert) GameIncome,' + char(13)
	+ '	case when sum(TotalBets@Convert) = 0 then 0 else (SUM(TotalWins@Convert)*100)/sum(TotalBets@Convert) end GamePayout,' + char(13)	+ '	SUM(TotalRefund@Convert) TotalRefund,' + char(13)
	+ '	SUM(CompanyNetIncome@Convert) CompanyNetIncome,' + char(13)
	+ ' SUM(CompanyTurnOver@Convert) CompanyTurnOver,' + char(13)
	+ ' SUM(CompanyComm@Convert) CompanyComm' + char(13)
	+ 'FROM #TempLC b' + char(13)
	+ 'left JOIN #CountMatchesByCurrency n ON n.currency = b.currency'+ char(13)
	+ 'INNER JOIN bodb02.dbo.exchange e with (nolock) on b.currency = e.exchangeid' + char(13)
	+ 'GROUP BY	e.currency'

if(@currency = -1)--choose All - based RM
    SELECT @sql = REPLACE(@sql,'@Convert','_RM')
else
	SELECT @sql = REPLACE(@sql,'@Convert','')

--GrandTotal row - based RM
select @sql = @sql + char(13) + 'UNION' + char(13) + 'SELECT ''zGrandTotalRM'',' + char(13)
	+ case when @ReportBy <> 2 then '	COUNT(DISTINCT custid) NoOfPlayers,' + char(13) else '' end
	+ '	min(n.numofgames ) NoOfGames,' + char(13)
	+ case when @ReportBy <> 6 then '	''RM'',' + char(13) else '' end
	+ '	SUM(TotalBets_RM) TotalBets,' + char(13)
	+ '	SUM(TotalWins_RM) TotalWins,' + char(13)
	+ '	SUM(TotalBets_RM) - SUM(TotalWins_RM) GameIncome,' + char(13)
	+ '	case when sum(TotalBets_RM) = 0 then 0 else (SUM(TotalWins_RM)*100)/sum(TotalBets_RM) end GamePayout,' + char(13)
	+ '	SUM(TotalRefund_RM) TotalRefund,' + char(13)
	+ '	SUM(CompanyNetIncome_RM) CompanyNetIncome,' + char(13)
	+ ' SUM(CompanyTurnOver_RM) CompanyTurnOver,' + char(13)
	+ ' SUM(CompanyComm_RM) CompanyComm' + char(13)
	+ 'FROM #TempLC,#AllMatches n' + char(13) 
	+ 'DROP TABLE #TempLC DROP TABLE #AllMatches DROP TABLE #tbl_Currency_Daily DROP TABLE #matches DROP TABLE #countmatches DROP TABLE #countmatchesbycurrency'

select @sql = @sqlTableExchange + @TempTable + char(13) + @sql

if (@debug = 1) PRINT @sql
	
exec (@sql)

/*
exec age_selBalanceupday
Acc_Rpt_LiveCasino_GameStatistics_GameTableSel

exec [dbo].Acc_Rpt_LiveCasino_GameStatistics_DW
	@fromdate = '2012-09-15',
	@todate = '2012-9-30',
	@username = '',
	@excludeTest = 1,
	@SiteID = 0,	
	@GameTypeID = 0,
	@GameTableID = 0,--leagueid
	@currency = 0,
	@ReportBy = 4,
	@MoveBetDay = '2012-10-1',
    @Debug = 1


*/

DROP TABLE #Temp_MemIDs