 
CREATE  PROCEDURE [dbo].[Acc_Rpt_LicNumberGameWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME
AS      
  
/*  
 * Created by : [20121122@Henry]  
 * Task  : Get Number Game Winloss 
 * DB   : DB052.bodb02  
 * Original: OA_Rpt_NumberGameWinloss
 * Revisions :  
	- 20121212@Henry: reset official launch date for Alog to 23/Nov/2012
	- 20121213@Henry: reset official launch date for Bodog to 05/Nov/2012
	- 20121213@henry: change to use Effectivedate from LicenseeProduct3rd instead of hard-code
	- 20130612@Jim: change condition AffectedDate,EffectiveDate
	- 20130719@Jim: exclude status "void","reject","done"
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


CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  ResellerID int, LicenseeID int,turnover MONEY, MemberWinloss MONEY,LicenseeWL MONEY, Betcount INT)
CREATE TABLE #Result (ResellerID INT,LicenseeID int,turnover MONEY, MemberWinloss MONEY,GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT,LupineRevenue MONEY, OneworksRevenue MONEY,DistributorsChargeRate MONEY, LupineChargeRate MONEY,OneworksChargeRate MONEY)
DECLARE @Exchange TABLE(ExchangeDate SMALLDATETIME, ExchangeId INT,  Rate FLOAT, PRIMARY KEY(ExchangeDate,ExchangeId))


--Get normal licensee list:
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate )
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
	INSERT INTO @tmpLicenseeReseller (ResellerID, LicenseeID,AffectedDate )   
	SELECT lr.ResellerID, lr.LicenseeID,
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
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss, sum(winlossA) AS LicenseeWL,SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
		INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd p (NOLOCK) ON lic.LicenseeID=p.LicenseeID AND p.ProductID=2
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND lr.ResellerID<>3
		AND lic.isdeposit=1
		AND sl.IsActive = 1
		AND s.SystemName='Accounting'
		AND b.status NOT IN (-1,101,102,103,121)
		AND CurrencyID<>20
		AND bettype BETWEEN 81 AND 120
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)
BEGIN
	--PIH + FDL
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss, 0 AS LicenseeWL,SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		INNER JOIN bodb_Licensee.dbo.LicenseeProduct3rd p (NOLOCK) ON lr.LicenseeID=p.LicenseeID AND p.ProductID=2
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND b.status NOT IN (-1,101,102,103,121)
		AND lr.ResellerID IN (4,8)
		AND CurrencyID<>20
		AND bettype BETWEEN 81 AND 120
		AND b.customercategory NOT IN (27,28) 
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid	
	
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

INSERT INTO #Result(ResellerID,LicenseeID,turnover, MemberWinloss,GrossWinloss, DistributorRevenue, Betcount,LupineRevenue,OneworksRevenue,DistributorsChargeRate, LupineChargeRate,OneworksChargeRate)
SELECT	
	r.ResellerID,d.LicenseeID,
	CAST(isnull(SUM(d.turnover * e.Rate),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(d.MemberWinloss * e.Rate),0) AS MONEY) AS MemberWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.Rate),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.Rate),0) END AS money) AS GrossWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.Rate),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.Rate * isnull(DI.ChargeRate,0)),0) END AS money) AS DistributorRevenue,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.Rate),0) < 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.Rate * isnull(DI.ChargeRate,0) * isnull(LUP.ChargeRate,0) ),0) END AS money) AS LupineRevenue,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.Rate),0) < 0 THEN 0 ELSE isnull(SUM(-1 * d.MemberWinloss * e.Rate * isnull(DI.ChargeRate,0) * isnull(LUP.ChargeRate,0) * isnull(OW.ChargeRate,0)),0) END AS money) AS OneworksRevenue,
	isnull(DI.ChargeRate,0) as DistributorsChargeRate,
	isnull(LUP.ChargeRate,0) as LupineChargeRate,
	isnull(OW.ChargeRate,0) as OneworksChargeRate
FROM #Data d
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
	INNER JOIN @Exchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange LUP ON d.ResellerID = LUP.ResellerID AND LUP.PartyID = 3 AND LUP.ProductID = 2 AND d.winlostdate BETWEEN LUP.FromDate AND LUP.ToDate	
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange OW ON d.ResellerID = OW.ResellerID AND OW.PartyID = 1 AND OW.ProductID = 2 AND d.winlostdate BETWEEN OW.FromDate AND OW.ToDate
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange DI ON d.ResellerID = DI.ResellerID AND DI.PartyID = 4 AND DI.ProductID = 2 AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
GROUP BY
	r.ResellerID,d.LicenseeID,DI.ChargeRate,LUP.ChargeRate,OW.ChargeRate
	
--return the result
SELECT	
	r.ResellerID,r.ResellerName,r.ResellerType,
	CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END AS LicenseeName,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
	CAST(isnull(SUM(re.GrossWinloss),0) AS MONEY) AS GrossWinloss,
	CAST(isnull(SUM(re.DistributorRevenue),0) AS MONEY) AS DistributorRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.LupineRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * LupineChargeRate END  AS MONEY) AS LupineRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.OneworksRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * LupineChargeRate * OneworksChargeRate END  AS MONEY) AS OneworksRevenue,
	DistributorsChargeRate,
	LupineChargeRate,
	OneworksChargeRate
FROM #Result re
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = re.ResellerID
	LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = re.LicenseeID
		
GROUP BY
	r.ResellerType,r.ResellerID,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END,
	DistributorsChargeRate,LupineChargeRate,OneworksChargeRate	
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
 GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LicNumberGameWinloss] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Acc_Rpt_LicNumberGameWinloss] TO [bodbAdminNet]
GO 
