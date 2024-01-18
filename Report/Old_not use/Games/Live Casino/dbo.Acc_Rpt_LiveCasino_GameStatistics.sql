ALTER PROCEDURE [dbo].[Acc_Rpt_LiveCasino_GameStatistics]
@Fromdate SMALLDATETIME, 
@Todate SMALLDATETIME,
@Username NVARCHAR(50),
@ExcludeTest BIT = 1,
@Site INT = 0,
@Bettype INT = 1101,
@GameTable NVARCHAR(100) = 'ALL',
@Currency INT,
@ReportType TINYINT=1,
@MoveBetsDay  SMALLDATETIME,
@BalanceUpDate SMALLDATETIME,
@ErrCode INT = 0,
@ErrMsg NVARCHAR(4000)= '' OUTPUT 
AS 

/*  Created:  Sophia
	Date:  20120207
    Task : Report Game Statistics for Live Casino
    DB: DB06.bodb02  
   
    Revisions:  
		
	Param's Explanation:  
	  + @ReportType: 1: Daily, 2: Monthly, 3: Username, 4: GameType, 5: Gametable, 6: Company, 7: Currency  
	  + @Currency: 	0: ALL,	-1: Base Currency RM,...
	  + @site: 0:All,  -1:IBC Group
	  + @Bettype: 0 : ALL
	  + @GameTable: 'ALL' : ALL
	
*/ 

SET NOCOUNT ON

DECLARE @TempFromDate DATETIME 
DECLARE @TempToDate DATETIME 
  

DECLARE @Winlost AS TABLE (  
winlostdate SMALLDATETIME,
Username	NVARCHAR(50),
bettype		SMALLINT,
GameTable	NVARCHAR(50),
--Site		INT,
CustID		INT,
srecommend	BIGINT,
statusID	INT,
Currency	INT,
completedgame  int,
Turnover	MONEY,
Refunds		MONEY,
Winlost		MONEY,
Company		MONEY
)


----*********************Check Valid Username
DECLARE @CustID INT, @RoleID SMALLINT
SET @CustID = 0

SELECT  @CustID = ISNULL(CustID,0),  @RoleID = ISNULL(RoleID,0)
FROM	CustInfo WITH (NOLOCK)
WHERE	Username = @Username AND RoleID <=4

IF @CustID = 0
BEGIN 
	SELECT @ErrCode = 1, @ErrMsg = 'Invalid username.'
	RETURN
END 

----------------
DECLARE @LeagueName NVARCHAR(100)


SELECT	@LeagueName = CASE WHEN @GameTable = 'ALL' THEN typenamee  + ' - ' + '%' ELSE typenamee  + ' - ' +@GameTable END 
FROM	bettype WITH (NOLOCK)
WHERE	typeID = @bettype
------------------

IF @Todate > @MoveBetsDay
BEGIN		
		SELECT  @TempFromDate = @MoveBetsDay

		INSERT INTO @Winlost  
		SELECT		b.winlostdate, b.Username, b.bettype, RIGHT(LeagueName,8) as GameTable, 
					b.CustID, b.srecommend, b.statusID, b.Currency, CASE WHEN StatusID = 0 THEN 0 ELSE 1 END as completedgame,
					SUM(ABS(stake)) as Turnover,
					SUM( CASE WHEN statusID  IN (101,102,103) THEN ABS(stake) ELSE 0 END ) Refunds,
					SUM( winlost-actual_stake ) as Winlost,
					(-1)*SUM((winlost-actual_stake)+ awinlost + mwinlost + swinlost + scomm) Company
		FROM	bettrans b WITH (NOLOCK)
			INNER JOIN Match m WITH (NOLOCK) ON m.matchid = b.matchid
			INNER JOIN 	league l WITH (NOLOCK) ON l.leagueid =m.leagueid
		WHERE	Bettype = CASE WHEN @Bettype = 0 THEN Bettype ELSE @Bettype END 
				AND m.sporttype = 162
				AND winlostdate between @TempFromDate AND @Todate
				AND CASE @RoleID 
						WHEN 1 THEN CustID
						WHEN 2 THEN Recommend
						WHEN 3 THEN Mrecommend
						WHEN 4 THEN Srecommend
					END = @Custid
				AND CASE WHEN @Currency NOT IN (0, -1) THEN @Currency ELSE Currency END = Currency
				AND l.leaguename LIKE '%'+@LeagueName+'%'
		GROUP BY b.winlostdate, b.Username, b.bettype, l.leaguename,  
				 b.CustID, b.srecommend, b.statusID,  b.Currency , b.matchid


END 
--IF @Fromdate <= @MoveBetsDay
--BEGIN
--			SELECT @TempToDate = @MoveBetsDay
--		
--			INSERT INTO @Winlost  
--			SELECT	b.winlostdate, b.Username, b.bettype, @GameTable as GameTable, 
--					b.CustID, b.srecommend, b.statusID, b.Currency,
--					SUM(ABS(stake)) as Turnover,
--					SUM( CASE WHEN statusID  IN (101,102,103) THEN ABS(stake) ELSE 0 END ) Refunds,
--					SUM( winlost-actual_stake ) as Winlost,
--					(-1)*SUM((winlost-actual_stake)+ awinlost + mwinlost + swinlost + scomm) Company
--			FROM	bettrans14 b WITH (NOLOCK)
--				INNER JOIN Match14 m WITH (NOLOCK) ON m.matchid = b.matchid
--				INNER JOIN 	league l WITH (NOLOCK)  ON l.leagueid =m.leagueid
--			WHERE	Bettype = CASE WHEN @Bettype = 0 THEN Bettype ELSE @Bettype END 
--					AND m.sporttype = 162
--					AND winlostdate between @FromDate AND @TempToDate
--					AND CASE @RoleID 
--							WHEN 1 THEN CustID
--							WHEN 2 THEN Recommend
--							WHEN 3 THEN Mrecommend
--							WHEN 4 THEN Srecommend
--						END = @Custid
--					AND CASE WHEN @Currency NOT IN (0, -1) THEN @Currency ELSE Currency END = Currency
--					AND l.leaguename LIKE '%'+@LeagueName+'%'
--			GROUP BY b.winlostdate, b.Username, b.bettype, l.leaguename,  
--					 b.CustID, b.srecommend, b.statusID,  b.Currency 
--END
--		
--
--IF @FromDate < @BalanceUpDate
--
--BEGIN
--
--	IF @Todate >= DATEADD(dd, -1, @BalanceUpDate)
--	BEGIN
--		SELECT @ToDate = DATEADD(dd, -1, @BalanceUpDate)
--	END
--
--		INSERT INTO @Winlost  
--		SELECT		b.winlostdate, c.Username, b.bettype, @GameTable as GameTable, 
--					b.CustID, b.srecommend, b.statusID, b.Currency, 
--					SUM(ABS(stake)) as Turnover,
--					SUM( CASE WHEN statusID  IN (101,102,103) THEN ABS(stake) ELSE 0 END ) Refunds,
--					SUM( winlost-actual_stake ) as Winlost,
--					(-1)*SUM((winlost-actual_stake)+ awinlost + mwinlost + swinlost + scomm) Company
--		FROM	 bodb_archive.dbo.bettrans_bk b WITH (NOLOCK)
--			INNER JOIN custInfo c WITH (NOLOCK) ON c.custid = b.custid
--			INNER JOIN bodb_archive.dbo.match_bk m WITH (NOLOCK) ON m.matchid = b.matchid
--			INNER JOIN 	league l WITH (NOLOCK) ON l.leagueid =m.leagueid
--		WHERE	Bettype = CASE WHEN @Bettype = 0 THEN Bettype ELSE @Bettype END 
--				AND m.sporttype = 162
--				AND winlostdate between @FromDate AND @BalanceUpDate
--				AND CASE @RoleID 
--						WHEN 1 THEN b.CustID
--						WHEN 2 THEN b.Recommend
--						WHEN 3 THEN b.Mrecommend
--						WHEN 4 THEN b.Srecommend
--					END = @Custid
--				AND CASE WHEN @Currency NOT IN (0, -1) THEN @Currency ELSE b.Currency END = b.Currency
--				AND l.leaguename LIKE '%'+@LeagueName+'%'
--		GROUP BY b.winlostdate, c.Username, b.bettype, l.leaguename,  
--				 b.CustID, b.srecommend, b.statusID,  b.Currency 
--	 
--END
			
IF @ExcludeTest=1
BEGIN
DELETE FROM @Winlost WHERE Currency = 20
END 

IF @Site = -1  --- IBC GROUP ONLY 
BEGIN
DELETE FROM @Winlost WHERE srecommend IN ( SELECT custid FROM dbo.f_DepSuper_1 ('all')) --- NOT IN LICENSEES
END 
 

--===================================================================
SELECT
		CASE WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)  
			WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)  
			WHEN @ReportType = 3 THEN CONVERT(VARCHAR(50),w.username)
			WHEN @ReportType = 4 THEN CONVERT(VARCHAR(10),w.bettype)
			WHEN @ReportType = 5 THEN CONVERT(VARCHAR(100),w.GameTable)
			WHEN @ReportType = 6 THEN CONVERT(VARCHAR(5),'IBC')
			WHEN @ReportType = 7 THEN CONVERT(VARCHAR(5),w.Currency)
			ELSE '' END ReportType,  

		COUNT( DISTINCT w.CustID ) as NoPlayers,
		SUM ( w.completedgame ) as NoGames,
		w.Currency,  
		SUM (Turnover - Refunds) as TotalBets,
		SUM (Winlost) as TotalWins,
		SUM (refunds) as TotalRefund,
		SUM (Company) as Company,

		SUM ((Turnover - Refunds)*h.actualrate) as TotalBetsRM,
		SUM (Winlost*h.actualrate) as TotalWinsRM,
		SUM (refunds*h.actualrate) as TotalRefundRM,
		SUM (Company*h.actualrate) as CompanyRM
FROM	@winlost w
	left JOIN ExchangeDaily h WITH (NOLOCK) ON w.winlostdate = h.ExchangeDate AND h.ExchangeId = w.Currency
	

GROUP BY   
		CASE WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)  
			WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)  
			WHEN @ReportType = 3 THEN CONVERT(VARCHAR(50),w.username)
			WHEN @ReportType = 4 THEN CONVERT(VARCHAR(10),w.bettype)
			WHEN @ReportType = 5 THEN CONVERT(VARCHAR(100),w.GameTable)
			WHEN @ReportType = 6 THEN CONVERT(VARCHAR(5),'IBC')
			WHEN @ReportType = 7 THEN CONVERT(VARCHAR(5),w.Currency)
			ELSE '' END ,  
 w.Currency 
ORDER BY ReportType , w.Currency


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_LiveCasino_GameStatistics] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LiveCasino_GameStatistics] TO [vnteam] 
go
 



 