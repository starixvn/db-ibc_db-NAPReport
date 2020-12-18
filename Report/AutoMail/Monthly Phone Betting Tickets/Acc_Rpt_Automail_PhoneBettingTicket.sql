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

	Param's Explanation:
*/ 
BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #tmp (custid INT)

	INSERT INTO #tmp
	SELECT custid  
	FROM DBCUST.NAP_UserControl.dbo.NAP_Users acc WITH(nolock)
		INNER JOIN vw_Customer ci WITH(nolock) on ci.custid= acc.UserId
	WHERE  username like 'CMTD%'
	
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
		INNER join custinfo c WITH(nolock) ON s.creator = c.custid
	GROUP BY c.username
	ORDER BY username
	
	DROP TABLE #tmp
	DROP TABLE #statistics
	
END	