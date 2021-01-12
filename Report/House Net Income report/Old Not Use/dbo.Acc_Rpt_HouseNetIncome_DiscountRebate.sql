    DECLARE @FDate    DATE
		, @TDate    DATE;

    DECLARE @DiscountGroupHeader TABLE (DiscountGroupId SMALLINT, PartyId INT)
	INSERT INTO @DiscountGroupHeader (DiscountGroupId, PartyId)
	SELECT DiscountGroupId, PartyId
	FROM (
		SELECT dh.DiscountGroupId, da.PartyId
			,ROW_NUMBER() OVER(PARTITION BY dh.DiscountGroupId ORDER BY dh.ToDate DESC) AS RN
		FROM bodb_Licensee.dbo.LA_DiscountGroupHeader dh WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment da WITH (NOLOCK) ON da.DiscountGroupId = dh.DiscountGroupId
		WHERE dh.FromDate <= @TDate AND dh.ToDate >= @FDate
	) d
	WHERE RN = 1

	DECLARE @DiscountGroup TABLE (PartyId INT, ProductCode VARCHAR(50))
	SELECT dh.PartyId, dp.ProductId
	FROM @DiscountGroupHeader dh
		INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dp WITH (NOLOCK) ON dp.DiscountGroupId = dh.DiscountGroupId
	
	;WITH CTE_PartyId AS (SELECT DISTINCT PartyId FROM @DiscountGroup)
	SELECT @Discount_PartyIds = COALESCE(@Discount_PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM CTE_PartyId

	;WITH CTE_ProductCode AS (SELECT DISTINCT ProductCode FROM @DiscountGroup)
	SELECT @Discount_ProductCodes = COALESCE(@Discount_ProductCodes + ',', '') + ProductCode FROM CTE_ProductCode

    DECLARE @DiscountData TABLE
	(
		PartyId				INT
		,ProductId			INT
		,Winloss			MONEY
		,Fee				MONEY
		,NegativeFee		MONEY
		,Minfee				MONEY
		,IsChargedByMinFee	BIT
		,Discount			MONEY
		,DiscountRate		MONEY
		,DiscountRemark		NVARCHAR(MAX)
		,Rebate				MONEY
		,RebateRate			MONEY
		,RebateRemark		VARCHAR(MAX)

	)
    INSERT INTO @DiscountData
	(
		PartyId
		,ProductId
		,Winloss
		,Fee
		,NegativeFee
		,Minfee
		,IsChargedByMinFee
		,Discount
		,DiscountRate
		,DiscountRemark
		,Rebate
		,RebateRate
		,RebateRemark
	)
    EXEC bodb_licensee.dbo.LA_AmountToCompanySel
		@FromDate		= @FDate
		,@ToDate		= @TDate
		,@PartyIds		= @Discount_PartyIds
		,@ProductCodes	= @Discount_ProductCodes
		,@BaseCurrency	= 'MYR'
		,@CurrencyId	= 0


END;
GO
