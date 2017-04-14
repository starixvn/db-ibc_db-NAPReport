
CREATE PROCEDURE [dbo].[Acc_Rpt_LicVirtualSportWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,    
	@SportList	VARCHAR(1000)
	
AS      
  
/*  
 * Created by : [20121122@Henry]  
 * Task  : Get Virtual Sports Winloss 
 * DB   : DB052.bodb02  
 * Original: OA_Rpt_VirtualSportWinloss
 * Revisions :  
	- 20121129@Henry: add more columns
	- 20130805@Jim: fix bug (add more limit filter status)
	- 20150209@Jim: base on currency GBP
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  - @SportList   : List of Virtual Sports
 *  
 */  
    
BEGIN      

	SET NOCOUNT ON

	DECLARE @sporttype TABLE(sporttype INT)
	DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT,AffectedDate Datetime)

	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  ResellerID int, LicenseeID int,turnover MONEY, MemberWinloss MONEY, Betcount INT)
	CREATE TABLE #Result (ResellerID INT,LicenseeID int,turnover MONEY, MemberWinloss MONEY,GrossWinloss MONEY,DistributorRevenue MONEY, Betcount INT,OneworksIncome MONEY,AmtDueToInspired MONEY,DistributorsChargeRate MONEY,OneworksChargeRate MONEY, InspiredChargeRate MONEY)
	DECLARE @Exchange TABLE(ExchangeDate SMALLDATETIME, ExchangeId INT,  Rate FLOAT, PRIMARY KEY(ExchangeDate,ExchangeId))

	IF (RTRIM(LTRIM(ISNULL(@SportList,'')))) = ''
	BEGIN
		INSERT INTO @sporttype VALUES (180) --Virtual Soccer
	END
	ELSE
	BEGIN
		INSERT INTO @sporttype (sporttype)
		SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@SportList,',')
	END

	--Get normal licensee list:
	IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
	BEGIN
		INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate)
		SELECT lr.ResellerID,lr.LicenseeID,
				CASE WHEN @fromdate<=l.AffectedDate THEN l.AffectedDate ELSE @fromdate END AffectedDate	
		FROM	
			bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
			INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID
			INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID
		WHERE
			r.ResellerID <> 3 
			AND lr.LicenseeID IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@NormalLicensee,','))	
	END		

	-- Operator
	IF LTRIM(RTRIM(ISNULL(@Operator,''))) <> ''
	BEGIN
		INSERT INTO @tmpLicenseeReseller (ResellerID, LicenseeID,AffectedDate)   
		SELECT lr.ResellerID, lr.LicenseeID  ,
					CASE WHEN @fromdate<=l.AffectedDate THEN l.AffectedDate ELSE @fromdate END AffectedDate	 
		FROM 
			bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
			INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID
			INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID
		WHERE
			r.ResellerID IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@Operator,','))		
	END
	  
	--exclude BA & IBC & PIH...
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)
	BEGIN
		INSERT INTO #Data
		SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
		FROM @tmpLicenseeReseller lr
			INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
			INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
			INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
			INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lic.LicenseeID=p.LicenseeID AND p.ProductID=5
		WHERE
			b.rptDate BETWEEN lr.AffectedDate  AND @ToDate
			AND b.rptDate >= ISNULL(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
			AND lr.ResellerID<>3
			AND lic.isdeposit=1
			AND sl.IsActive = 1
			AND s.SystemName='Accounting'
			--AND @FromDate >= ISNULL(lic.AffectedDate,'1999-01-01')
			AND b.status NOT IN (-1,103,101,102,121)
			AND CurrencyID<>20
			AND bettype BETWEEN 1201 AND 1299
			AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
		GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid
	END

	--FDL + PIH...
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)
	BEGIN
		INSERT INTO #Data
		SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
		FROM @tmpLicenseeReseller lr
			INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
			INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lr.LicenseeID=p.LicenseeID AND p.ProductID=5
		WHERE
			b.rptDate BETWEEN lr.AffectedDate AND @ToDate
			AND b.rptDate >= ISNULL(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
			AND b.status NOT IN (-1,103,101,102,121)
			AND lr.ResellerID<>3
			--AND @FromDate >= ISNULL(lb.AffectedDate,'1999-01-01')
			AND CurrencyID<>20
			AND bettype BETWEEN 1201 AND 1299
			AND b.customercategory NOT IN (27,28) 
			AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
		GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid	
	END

	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency)
	DECLARE @ExchangeRate VARCHAR(3)
			,@SqlCmd	  VARCHAR(500) 

	SELECT  @ExchangeRate = Currency
			,@SqlCmd = ''
	FROM dbo.Lrf_f_basecurrency (@ToDate)
	WHERE isdefault = 1

	SELECT @SqlCmd = 
					'SELECT ExchangeDate,ExchangeId,'+CHAR(13)+CONVERT(VARCHAR(3),@ExchangeRate)+CHAR(13)+
					'FROM Lrf_f_GetExchangeDaily('''+CONVERT(VARCHAR,@FromDate,120)+''','''+CONVERT(VARCHAR,@ToDate,120)+''')'+CHAR(13)+
					'WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)'

	INSERT INTO @Exchange(ExchangeDate,ExchangeId,Rate)
	EXEC (@SqlCmd)
	
	INSERT INTO #Result(ResellerID,LicenseeID,turnover, MemberWinloss,GrossWinloss,DistributorRevenue, Betcount,OneworksIncome,AmtDueToInspired,DistributorsChargeRate,OneworksChargeRate, InspiredChargeRate)
	SELECT	
		r.ResellerID,d.LicenseeID,
		CAST(ISNULL(SUM(d.turnover * e.Rate),0) AS MONEY) AS Turnover,
		CAST(ISNULL(SUM(d.MemberWinloss * e.Rate),0) AS MONEY) AS MemberWinloss,
		CAST(CASE WHEN ISNULL(SUM(d.MemberWinloss * e.Rate),0) > 0 THEN 0 ELSE -1 * ISNULL(SUM(d.MemberWinloss * e.Rate),0) END AS money) AS GrossWinloss,
		CAST(CASE WHEN ISNULL(SUM(d.MemberWinloss * e.Rate),0) > 0 THEN 0 ELSE -1 * ISNULL(SUM(d.MemberWinloss * e.Rate * ISNULL(DI.ChargeRate,0)),0) END AS money) AS DistributorRevenue,
		ISNULL(SUM(d.betcount), 0) AS BetCount,
		CAST(CASE WHEN ISNULL(SUM(-1 * d.MemberWinloss * e.Rate * OW.ChargeRate),0) < 0 THEN 0 ELSE ISNULL(SUM(-1 * d.MemberWinloss * e.Rate * OW.ChargeRate),0) END AS money) AS OneworksIncome,
		CAST(CASE WHEN ISNULL(SUM(-1 * d.MemberWinloss * e.Rate * INS.ChargeRate),0) < 0 THEN 0 ELSE ISNULL(SUM(-1 * d.MemberWinloss * e.Rate * INS.ChargeRate),0) END AS money) AS AmtDueToInspired,
		ISNULL(DI.ChargeRate,0) as DistributorsChargeRate,
		ISNULL(OW.ChargeRate,0) as OneworksChargeRate ,
		ISNULL(INS.ChargeRate,0) as InspiredChargeRate
	FROM #Data d
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
		INNER JOIN @Exchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
		LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange OW ON d.ResellerID = OW.ResellerID AND OW.PartyID = 1 AND OW.ProductID = 5 AND d.winlostdate BETWEEN OW.FromDate AND OW.ToDate
		LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange INS ON d.ResellerID = INS.ResellerID AND INS.PartyID = 2 AND INS.ProductID = 5 AND d.winlostdate BETWEEN INS.FromDate AND INS.ToDate	
		LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange DI ON d.ResellerID = DI.ResellerID AND DI.PartyID = 4 AND DI.ProductID = 5 AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
	GROUP BY
		r.ResellerID,d.LicenseeID,DI.ChargeRate,OW.ChargeRate,INS.ChargeRate
		
	--return the result
	SELECT	
		r.ResellerID,r.ResellerName,
		CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END AS LicenseeName,
		r.ResellerType,
		ISNULL(SUM(re.betcount), 0) AS BetCount,
		CAST(ISNULL(SUM(re.turnover),0) AS MONEY) AS Turnover,
		CAST(ISNULL(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
		CAST(ISNULL(SUM(re.GrossWinloss),0) AS MONEY) AS GrossWinloss,
		CAST(ISNULL(SUM(re.DistributorRevenue),0) AS MONEY) AS DistributorRevenue,
		CAST(ISNULL(SUM(re.OneworksIncome),0) AS MONEY) AS OneworksIncome,
		CAST(ISNULL(SUM(re.AmtDueToInspired),0) AS MONEY) AS AmtDueToInspired,
		DistributorsChargeRate,
		OneworksChargeRate, InspiredChargeRate
		
	FROM #Result re
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = re.ResellerID
		LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = re.LicenseeID
			
	GROUP BY
		r.ResellerType,r.ResellerID,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END,DistributorsChargeRate, OneworksChargeRate, InspiredChargeRate	
	ORDER BY
		r.ResellerType DESC,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END
				
	DROP TABLE	#Data
	DROP TABLE	#Result
			
END



GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicVirtualSportWinloss] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_LicVirtualSportWinloss] TO [bodbAdminNet]
GO 
