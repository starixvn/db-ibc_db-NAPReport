/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_PhoneBettingTicket]
	@FromDate    SMALLDATETIME,
	@ToDate      SMALLDATETIME
AS
/*
    Created	: 20201118@Cherry
	Task	: Phone Betting Tickets (#129840)
	DB		: DBACC/bodb02
	
	Revision:		
		20201118@Cherry: Initial (convert from script adhoc #129840 to SP)
		20201218@Cherry: Modify SP
		20220621@Harry: hardcode list users
		20230705@Harry: change to hardcode custid
		20250811@Harry: change to hardcode custid (#235759)

	Param's Explanation:
*/ 
BEGIN
	SET NOCOUNT ON;

	DECLARE @BalanceUpDay date,@MovebetsDay date
	CREATE table #BU (BalanceUpDay date, MovebetsDay date)
	insert into #bu(BalanceUpDay, MovebetsDay)
	exec bodb02.dbo.Age_SelBalanceUpDay
	select @BalanceUpDay=(select BalanceUpDay from #BU)
	select @MovebetsDay=(select MovebetsDay from #BU)

	CREATE TABLE #tmp (custid INT)

	INSERT INTO #tmp
	SELECT custid  
	FROM custinfo WITH(nolock)
	WHERE custid in (13280506,17013688,23738933,26071936,26136721,46389402,47228188,17013911,25157469,381638,464627,37229172,17062,20025,2454,12677,549062,570598,23147627,249789,1005105,16990409,82315227,859085,859093,47228190,772216,29548915,17013695,24302980,66673848,726200,31417,2437,12663,2445,2339,12684,2049419,15184677,15184690,11974134,45036399,2962,17019237,14116130,4133165,8363809)     	
	
	CREATE TABLE #statistics(creator INT, cnt INT)
	
	INSERT INTO #statistics(creator,cnt)
	SELECT creator, COUNT(1)
	FROM bettrans WITH(nolock)
	WHERE betfrom = 'p'
		and winlostdate BETWEEN @FromDate and @ToDate
		and creator in (select custid from #tmp)
		and statusid in (111,112,113,103)
		and currency <> 20
	GROUP BY creator
	OPTION(RECOMPILE)
	
	INSERT INTO #statistics(creator, cnt)
	SELECT creator,  COUNT(1)
	FROM bettrans14 WITH(nolock)
	WHERE betfrom = 'p'
		and winlostdate BETWEEN @BalanceUpDay and @ToDate
		and creator in (select custid from #tmp)
		and statusid in (111,112,113,103)
		and currency <> 20
	GROUP BY creator
	OPTION(RECOMPILE)
	
	WHILE @FromDate < @BalanceUpDay
	BEGIN
		INSERT INTO #statistics(creator, cnt)
		SELECT creator, COUNT(1)
		FROM bodb_archive.dbo.bettrans_bk WITH(nolock)
		WHERE betfrom = 'p'
			and statusid in (111,112,113,103)
			and WinlostDate = @FromDate
			and creator in (select custid from #tmp)
			and currency <> 20
		GROUP BY creator
		OPTION(RECOMPILE)

		SELECT @FromDate = dateadd(DAY,1,@FromDate)
	END 
	
	SELECT c.username as Username ,
		sum(cnt) as TicketNumber
	FROM #statistics s
		INNER JOIN custinfo c WITH(nolock) ON s.creator = c.custid
	GROUP BY c.username
	ORDER BY username
	
	DROP TABLE #tmp
	DROP TABLE #BU
	DROP TABLE #statistics
	
END	

