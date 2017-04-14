
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Acc_Rpt_LicLiveCasinoWinloss    Script Date: 3/12/2015 10:28:53 AM ******/
 CREATE  PROCEDURE [dbo].[Acc_Rpt_LicLiveCasinoWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@GameType  INT=0,
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME
	
AS      
  
/*  
 * Created by : [20121122@Henry]  
 * Task  : Get Live Casino Winloss 
 * DB   : DB052.bodb02  
 * Original: OA_Rpt_LiveCasinoWinloss
 * Revisions :  
	- 20130219@Jim: add more filter for Licensee From table LicenseeProduct3rd
	- 20130508@Jim: add more filter gametype
	- 20130613@Jim: change condition AffectedDate,EffectiveDate
	- 20131030@Jim: offer all Live Casino bettype
	- 20150209@Jim: base on currency GBP
	
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 
 *  
 */  
    
BEGIN      

SET NOCOUNT ON

DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT,AffectedDate Datetime)

CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,bettype INT,  ResellerID int, LicenseeID int,turnover MONEY, MemberWinloss MONEY, Betcount INT)
CREATE TABLE #Result (ResellerID INT,LicenseeID int,turnover MONEY, MemberWinloss MONEY,GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT,StarExpressRevenue MONEY, OneworksRevenue MONEY,DistributorsChargeRate MONEY, StarExpressChargeRate MONEY,OneworksChargeRate MONEY)
DECLARE @Exchange TABLE(ExchangeDate SMALLDATETIME, ExchangeId INT,  Rate FLOAT, PRIMARY KEY(ExchangeDate,ExchangeId))

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
	SELECT  b.rptDate,b.currencyID,b.bettype,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss, SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
		INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lic.LicenseeID=p.LicenseeID AND p.ProductID=4
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND lr.ResellerID<>3
		AND lic.isdeposit=1
		AND sl.IsActive = 1
		AND s.SystemName='Accounting'
		AND b.status NOT IN (-1,103)
		AND CurrencyID<>20
		AND bettype BETWEEN 1101 AND 1199
	GROUP BY b.rptDate,b.currencyID,b.bettype, lr.ResellerID, lr.licenseeid
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,b.bettype,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss, SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lr.LicenseeID=p.LicenseeID AND p.ProductID=4
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND b.status NOT IN (-1,103)
		AND lr.ResellerID<>3
		AND CurrencyID<>20
		AND bettype BETWEEN 1101 AND 1199
		AND b.customercategory NOT IN (27,28) 
	GROUP BY b.rptDate,b.currencyID, b.bettype,lr.ResellerID, lr.licenseeid	
END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)

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

INSERT INTO #Result(ResellerID,LicenseeID,turnover, MemberWinloss,GrossWinloss, DistributorRevenue, Betcount,StarExpressRevenue,OneworksRevenue,DistributorsChargeRate, StarExpressChargeRate,OneworksChargeRate)
SELECT	
	r.ResellerID,d.LicenseeID,
	CAST(isnull(SUM(d.turnover * e.Rate),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(d.MemberWinloss * e.Rate),0) AS MONEY) AS MemberWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.Rate),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.Rate),0) END AS money) AS GrossWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.Rate),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.Rate * isnull(DI.ChargeRate,0)),0) END AS money) AS DistributorRevenue,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.Rate),0) < 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.Rate * isnull(DI.ChargeRate,0) * isnull(STAR.ChargeRate,0) ),0) END AS money) AS StarExpressRevenue,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.Rate),0) < 0 THEN 0 ELSE isnull(SUM(-1 * d.MemberWinloss * e.Rate * isnull(DI.ChargeRate,0) * isnull(STAR.ChargeRate,0) * isnull(OW.ChargeRate,0)),0) END AS money) AS OneworksRevenue,
	isnull(DI.ChargeRate,0) as DistributorsChargeRate,
	isnull(STAR.ChargeRate,0) as StarExpressChargeRate,
	isnull(OW.ChargeRate,0) as OneworksChargeRate
FROM #Data d
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
	INNER JOIN @Exchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange STAR ON d.ResellerID = STAR.ResellerID AND STAR.PartyID = 5 AND STAR.ProductID = 4 AND d.winlostdate BETWEEN STAR.FromDate AND STAR.ToDate	
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange OW ON d.ResellerID = OW.ResellerID AND OW.PartyID = 1 AND OW.ProductID = 4 AND d.winlostdate BETWEEN OW.FromDate AND OW.ToDate
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange DI ON d.ResellerID = DI.ResellerID AND DI.PartyID = 4 AND DI.ProductID = 4 AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
WHERE ((@GameType=0) OR (@GameType<>0 AND d.bettype=@GameType))	
GROUP BY
	r.ResellerID,d.LicenseeID,DI.ChargeRate,STAR.ChargeRate,OW.ChargeRate
	
--return the result
SELECT	
	r.ResellerID,r.ResellerName,r.ResellerType,
	CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END AS LicenseeName,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
	CAST(isnull(SUM(re.GrossWinloss),0) AS MONEY) AS GrossWinloss,
	CAST(isnull(SUM(re.DistributorRevenue),0) AS MONEY) AS DistributorRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.StarExpressRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * StarExpressChargeRate END  AS MONEY) AS StarExpressRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.OneworksRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * StarExpressChargeRate * OneworksChargeRate END  AS MONEY) AS OneworksRevenue,
	DistributorsChargeRate,
	StarExpressChargeRate,
	OneworksChargeRate
FROM #Result re
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = re.ResellerID
	LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = re.LicenseeID
		
GROUP BY
	r.ResellerType,r.ResellerID,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END,
	DistributorsChargeRate,StarExpressChargeRate,OneworksChargeRate	
ORDER BY
	r.ResellerType DESC,r.ResellerName,DistributorsChargeRate DESC, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END
			
DROP TABLE	#Data
DROP TABLE	#Result
 
END 


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicLiveCasinoWinloss] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_LicLiveCasinoWinloss] TO [bodbAdminNet]
GO 
