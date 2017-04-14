 
CREATE PROCEDURE [dbo].[Acc_Rpt_KenoLicenseeWinLoss]
	@LicenseeIDList	NVARCHAR(500),
	@BettypeID		INT = 0,
	@Currency		VARCHAR(3)='0',
	@FromDate		SMALLDATETIME,
	@ToDate			SMALLDATETIME
AS
/*
	Created: Kyan
	Task : Get Licensee win/loss for Keno product
	DB: DBLIC/bodb_licensee 
	
	Revision :
			-20140610@Jim: fix bug #17114 ( regardless effective date of Keno)
			-20140617@Jim: +Report changed to support group by currency
						   +Hard-code  launch date  for all Credit Customers (belong to 2 licensees FDL, PIH) 	
			-20150211@Jim: support to base on currency GBP			   
	Param's Explanation:  
	  + @@LicenseeIDList: list of LicenseeID, seperate by ',' 
	  +	@BettypeID: Keno Bettype, if this value is 0 - All Keno Bettypes
	  + @Currency : character, ='0' when all currencies have been selected
*/
/*
	 	 exec Acc_Rpt_KenoLicenseeWinLoss 
		@LicenseeIDList=N'1'
		,@Currency='0'
		,@BettypeID=0
		,@FromDate='2014-04-01 00:00:00'
		,@ToDate='2014-04-01 00:00:00'
 
*/
BEGIN
	SET NOCOUNT ON
	
	-- declare variable
	CREATE TABLE #LicenseeList(licenseeID INT
							  ,launchdate DATETIME
							  )
	CREATE TABLE #LicIDList(licenseeID INT)
	CREATE TABLE #Currency (CurrencyID INT
							,CurrencyCode VARCHAR(3)
							)
	CREATE TABLE #tmpResult (rptDate DATETIME
							,CurrencyID INT
							,CurrencyCode VARCHAR(3)
							,TurnOver MONEY
							,MemberWinloss MONEY
							,BetCount INT
							)
	-- init variable
	IF  @Currency='INH'	
	SET @Currency='VND'
	
	INSERT INTO #Currency (CurrencyID,CurrencyCode)
	SELECT 
			exchangeid CurrencyID
			,Code     CurrencyCode
	FROM bodb02.dbo.Exchange WITH (NOLOCK)
	WHERE	( ISNULL(@Currency,'')='0' AND exchangeid<>20
			)
			OR Code=@Currency	
	
	INSERT INTO #LicIDList(licenseeID)
	SELECT VAL LicenseeID FROM bodb02.dbo.strSplit(@LicenseeIDList,',')
	
	INSERT INTO #LicenseeList (LicenseeId,launchdate )
	SELECT  
			l.licenseeID
			,lp.EffectiveDate launchdate
	FROM dbo.Licensees l WITH (NOLOCK)
		INNER JOIN dbo.LicenseeProduct3rd lp WITH (NOLOCK) ON l.licenseeID=lp.LicenseeID AND lp.ProductId=8 --- KENO
		INNER JOIN #LicIDList lid ON l.LicenseeId=lid.LicenseeID
	WHERE 
		 l.LicenseeID NOT IN (13,18) -- exclude FDL, PIH
	UNION
	SELECT 
		   DISTINCT
		   LabelID AS licenseeID,
		   lp3.EffectiveDate launchdate
	FROM dbo.Labels lb WITH (NOLOCK)
		INNER JOIN #LicIDList   lID ON lID.licenseeID = lb.LicenseeID
		INNER JOIN dbo.LicenseeProduct3rd lp3 WITH (NOLOCK)  ON lid.LicenseeId=lp3.LicenseeID AND lp3.ProductId=8 --- KENO
	WHERE lb.LicenseeID in (13,18)
	  
	INSERT INTO #tmpResult (rptDate,CurrencyId,CurrencyCode,TurnOver,MemberWinloss,BetCount)
	SELECT  
			b.rptDate
			,b.CurrencyId
			,c.CurrencyCode
			,SUM(Turnover ) AS TurnOver
			,SUM(b.Winloss) AS MemberWinloss
			,SUM(BetCount) AS BetCount
	
	FROM dbo.rpt_Betting b WITH (NOLOCK,INDEX=CIX_rpt_Betting)
	INNER JOIN #LicenseeList l on l.LicenseeID = b.SiteID
	INNER JOIN #Currency c ON b.CurrencyID=c.CurrencyID 
	INNER JOIN bodb02.dbo.GameType g WITH (NOLOCK) ON b.Bettype=g.IBCBetTypeID
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate
		 AND b.rptDate>=ISNULL(l.launchdate,DATEADD(DAY,1,@ToDate))
		 AND b.CurrencyId NOT IN (20,27,28)
		 AND (b.Bettype = @BettypeID 
				OR (@BettypeID = 0 AND b.bettype BETWEEN 1501 AND 1599)
			 )
		 AND b.STATUS NOT IN (-1,103)
		 AND b.customercategory NOT IN (27,28)
		 AND g.IsDisabled=0
	GROUP BY b.rptDate
			,b.CurrencyId	
			,c.CurrencyCode
			
	UPDATE #tmpResult
	SET CurrencyCode='INH'
	WHERE CurrencyCode='VND'	
	-- detail
	SELECT 
		   rptDate
		   ,CurrencyCode 	 	AS	Currency
		   ,SUM(TurnOver )   	AS TurnOver
		   ,SUM(BetCount)    	AS TotalTransaction
		   ,SUM(MemberWinloss)  AS CustomerWL
	FROM #tmpResult
	GROUP BY rptDate
			,CurrencyCode
	ORDER BY  rptDate
			 ,CurrencyCode
	--- table sum 
	SELECT   CurrencyCode Currency
			,SUM(TurnOver) TurnOver
			,SUM(BetCount) TotalTransaction
			,SUM(MemberWinloss) CustomerWL
	FROM #tmpResult
	GROUP BY  CurrencyCode
	ORDER BY CurrencyCode
	--- Total (base on EUR/MYR/GBP )
	SELECT *
	INTO #Exchange	
	FROM bodb02.dbo.Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
	WHERE exchangeid IN (SELECT DISTINCT CurrencyID FROM #tmpResult)
			 
	SELECT 
		 SUM(d.TurnOver*ex.EUR)		  AS ToTalTurnOverEUR
		 ,SUM(d.TurnOver*ex.MYR) 	  AS ToTalTurnOverMYR
		 ,SUM(d.TurnOver*ex.GBP) 	  AS ToTalTurnOverGBP
		 ,SUM(d.BetCount) 			  AS TotalTransaction
		 ,SUM(d.MemberWinloss*ex.EUR) AS CustomerWLEUR
		 ,SUM(d.MemberWinloss*ex.MYR) AS CustomerWLMYR
		 ,SUM(d.MemberWinloss*ex.GBP) AS CustomerWLGBP
	FROM #tmpResult d
	INNER JOIN #Exchange ex ON d.rptDate = ex.exchangedate AND d.CurrencyID = ex.ExchangeId
	
	-------
	DROP TABLE #LicenseeList
	DROP TABLE #LicIDList
	DROP TABLE #Currency 
	DROP TABLE #tmpResult 
	DROP TABLE #Exchange
END

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_KenoLicenseeWinLoss] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_KenoLicenseeWinLoss] TO [bodbAdminNet]
GO 
