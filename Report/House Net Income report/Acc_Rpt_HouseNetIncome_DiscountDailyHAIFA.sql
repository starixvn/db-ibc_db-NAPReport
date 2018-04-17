/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA]
	@FromDate DATE,
	@ToDate	DATE,
	@ProductCodes VARCHAR(100) = 'SB'
AS  
/*  
	Created:	Harper@20161024
	Task:		Caculate discount daily for HAIFA
	DB:			DBEXT.bodb02

	Revisions:
		- 20180201@Harper: Create new SP [#RedmineID: 90263]
		
	Param's Explanation:

	EXEC Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA @FromDate = '2017-12-01', @ToDate = '2017-12-31'
*/  
BEGIN  
	SET NOCOUNT ON
	
	DECLARE @FDate DATE, @TDate DATE
	SELECT @FDate = @FromDate, @TDate = @ToDate

	CREATE	TABLE #Exchange	(ExchangeDate DATE, ExchangeID INT, Rate FLOAT)

	INSERT INTO #Exchange (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, Currency, Rate
	FROM DBWH.bodb_account.dbo.tbl_Currency_Daily WITH (NOLOCK) 
	WHERE ExchangeDate BETWEEN @FDate AND @TDate

	CREATE TABLE #DiscountGroupHeader (	DiscountGroupId		INT,
										DiscountGroupType	TINYINT,
										PartyId				INT,
										CurrencyId			INT,
										FromDate			DATETIME,
										ToDate				DATETIME)

	INSERT INTO #DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate)
	(
		SELECT	dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate
		FROM	bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	@FDate <= ToDate AND FromDate <= @TDate AND dg.DiscountGroupType = 1 -- Get discount winloss only
				AND dga.PartyID IN (SELECT p.PartyID FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyName = 'HAIFA')
	)

	DELETE	d FROM #DiscountGroupHeader d
	WHERE	d.ToDate < (SELECT	MAX(g.ToDate)
						FROM	#DiscountGroupHeader g
						WHERE	d.PartyId = g.PartyId)			

	CREATE TABLE #DiscountGroup(DiscountGroupId		SMALLINT,
								DiscountGroupType	TINYINT,
								FromAmount			MONEY,
								ToAmount			MONEY,
								Rate				MONEY,
								PartyId				INT,
								ProductId			TINYINT,
								BaseCurrency		INT)

	INSERT INTO #DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId , BaseCurrency)	
	(
		SELECT	dg.DiscountGroupId,
				dg.DiscountGroupType,
				dgd.FromAmount,
				dgd.ToAmount,
				dgd.Rate,
				dg.PartyID,
				dgp.ProductId,
				dg.CurrencyId
		FROM	#DiscountGroupHeader dg 
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
	)

	DECLARE @ProductList VARCHAR(1000) = NULL

	SELECT @ProductList = COALESCE(@ProductList + ',', '') + CONVERT(VARCHAR(10), ProductPrefix) 
	FROM (
			SELECT DISTINCT CASE WHEN d.ProductId = 0 THEN 'SB' ELSE p.ProductPrefix END AS ProductPrefix
			FROM #DiscountGroup d
				LEFT JOIN bodb_licensee.dbo.Product3rd p WITH (NOLOCK) ON p.Productid = d.ProductId
		) t	
	
	-- Convert discount amount to base currency
	UPDATE d SET
		d.FromAmount = d.FromAmount * e.Rate,
		d.ToAmount = d.ToAmount * e.Rate
	FROM #DiscountGroup d
	INNER JOIN #Exchange e ON
		e.ExchangeDate = @TDate AND
		d.BaseCurrency = e.ExchangeID AND
		d.DiscountGroupType = 1 -- discount = 1
	
	SELECT d.DiscountGroupId, d.DiscountGroupType, d.FromAmount, d.ToAmount, d.Rate, d.PartyId, d.ProductId, d.BaseCurrency
	FROM #DiscountGroup d

	DROP TABLE #Exchange
	DROP TABLE #DiscountGroupHeader
	DROP TABLE #DiscountGroup
	
END
GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA] TO [bodbAdminNet]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_HouseNetIncome_DiscountDailyHAIFA] TO vnteam
GO