/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

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

	Param's Explanation:
*/ 
BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #tmp (custid INT)

	INSERT INTO #tmp
	SELECT custid  
	FROM custinfo WITH(nolock)
	WHERE custid in (726200,31417,17013688,2437,12663,26136721,47228188,2445,17013911,381638,464627,17062,20025,2454,12677,549062,570598,23147627,249789,1005105,16990409,859085,859093,47228190,2339,12684,772216,17013695,2049419,15184677,15184690,11974134,45036399,2962,17019237,14116130,4133165,8363809)     	
	
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
		and winlostdate BETWEEN @FromDate and @ToDate
		and creator in (select custid from #tmp)
		and statusid in (111,112,113,103)
		and currency <> 20
	GROUP BY creator
	OPTION(RECOMPILE)
	
	INSERT INTO #statistics(creator, cnt)
	SELECT creator, COUNT(1)
	FROM bodb_archive.dbo.bettrans_bk WITH(nolock)
	WHERE betfrom = 'p'
		and statusid in (111,112,113,103)
		and winlostdate BETWEEN @FromDate and @ToDate
		and creator in (select custid from #tmp)
		and currency <> 20
	GROUP BY creator
	OPTION(RECOMPILE)
	
	SELECT c.username as Username ,
		sum(cnt) as TicketNumber
	FROM #statistics s
		INNER JOIN custinfo c WITH(nolock) ON s.creator = c.custid
	GROUP BY c.username
	ORDER BY username
	
	DROP TABLE #tmp
	DROP TABLE #statistics
	
END	