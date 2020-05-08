/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_DiscountRebate
	@FromDate    DATE 
   , @ToDate      DATE 
AS
/*  
	Created: Victor  
	Date: 2016-06-24  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20160909@Harper - #63899 - Rebate and Discount should be included when calculating the Pay to Suplplier
		- 20160922@Harper - #64527 - Cannot calculate the Rebate of Keno and Number Game
		- 20161024@Harper - #65699 - HAIFA - Apply new charge rate discount for HNI report
		- 20170323@Harper - #67065 - Add more product to calculate discount & rebate
		- 20170825@Harper - #79612 - Add VS2 to caculate Discount
		- 20181202@Robert: #104579 - House Net Income Email/Letstalk/Margin Chart - Integrate Happy 5
		- 20190214@Robert: #97564 - House Net Income & Margin Charts - Apply new changing on discount and update calculation formula for related products
		- 20190918@Robert: Remove inactive products (#120215)
		- 20200508#Robert: #133842 DHWL - Support old data from Jan - Mar 2020


	Param's Explanation:   
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;
    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    CREATE TABLE #DiscountGroupHeader(
	    DiscountGroupId      INT
	  , DiscountGroupType    TINYINT
	  , PartyId              INT
	  , CurrencyId           INT
	  , FromDate             DATETIME
	  , ToDate               DATETIME);

    INSERT INTO #DiscountGroupHeader(DiscountGroupId
							, DiscountGroupType
							, PartyId
							, CurrencyId
							, FromDate
							, ToDate)
		 (
			SELECT dg.DiscountGroupId
				, dg.DiscountGroupType
				, dga.PartyId
				, dg.CurrencyId
				, dg.FromDate
				, dg.ToDate
			FROM bodb_Licensee.dbo.LA_DiscountGroupHeader AS dg WITH (NOLOCK)
			    INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment AS dga WITH (NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
			WHERE @FDate <= ToDate
				 AND FromDate <= @TDate
		 );

    DELETE d
    FROM #DiscountGroupHeader d
    WHERE d.ToDate <
		(
		    SELECT MAX(g.ToDate)
		    FROM #DiscountGroupHeader AS g
		    WHERE g.DiscountGroupType = 1
				AND d.PartyId = g.PartyId
		)
		AND d.DiscountGroupType = 1;

    DELETE d
    FROM #DiscountGroupHeader d
    WHERE d.ToDate <
		(
		    SELECT MAX(g.ToDate)
		    FROM #DiscountGroupHeader AS g
		    WHERE g.DiscountGroupType = 2
				AND d.PartyId = g.PartyId
		)
		AND d.DiscountGroupType = 2;

    DELETE d
    FROM #DiscountGroupHeader d
    WHERE d.ToDate <
		(
		    SELECT MAX(g.ToDate)
		    FROM #DiscountGroupHeader AS g
		    WHERE g.DiscountGroupType = 3
				AND d.PartyId = g.PartyId
		)
		AND d.DiscountGroupType = 3;

    CREATE TABLE #DiscountGroup(
	    DiscountGroupId      SMALLINT
	  , DiscountGroupType    TINYINT
	  , FromAmount           MONEY
	  , ToAmount             MONEY
	  , Rate                 MONEY
	  , PartyId              INT
	  , ProductId            TINYINT
	  , BaseCurrency         INT);

    INSERT INTO #DiscountGroup(DiscountGroupId
					    , DiscountGroupType
					    , FromAmount
					    , ToAmount
					    , Rate
					    , PartyId
					    , ProductId
					    , BaseCurrency)
		 (
			SELECT dg.DiscountGroupId
				, dg.DiscountGroupType
				, dgd.FromAmount
				, dgd.ToAmount
				, dgd.Rate
				, dg.PartyID
				, dgp.ProductId
				, dg.CurrencyId
			FROM #DiscountGroupHeader AS dg
			    INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail AS dgd WITH (NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
			    INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct AS dgp WITH (NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
		 );

    DECLARE @ProductList    VARCHAR(1000) = NULL;

    SELECT @ProductList = COALESCE(@ProductList+',', '')+CONVERT(VARCHAR(10), ProductPrefix)
    FROM
	    (
		   SELECT DISTINCT
				CASE
				    WHEN d.ProductId = 0
				    THEN 'SB'
				    ELSE p.ProductPrefix
				END AS ProductPrefix
		   FROM #DiscountGroup AS d
			  LEFT JOIN bodb_licensee.dbo.Product3rd AS p WITH (NOLOCK) ON p.Productid = d.ProductId
	    ) AS t;

    DECLARE @PartyIDs    VARCHAR(1000);
    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM
	    (
		   SELECT DISTINCT
				PartyId
		   FROM #DiscountGroup
	    ) AS PartyIds;

    CREATE TABLE #TmpData_LA(
	    PartyId              INT
	  , ProductId            INT
	  , Winloss              MONEY
	  , Fee                  MONEY
	  , NegativeFee          MONEY
	  , Minfee               MONEY
	  , IsChargedByMinFee    BIT
	  , Discount             MONEY
	  , DiscountRate         MONEY
	  , DiscountRemark       NVARCHAR(MAX)
	  , Rebate               MONEY
	  , RebateRate           MONEY
	  , RebateRemark         VARCHAR(MAX));

    INSERT INTO #TmpData_LA(PartyId
					 , ProductId
					 , Winloss
					 , Fee
					 , NegativeFee
					 , Minfee
					 , IsChargedByMinFee
					 , Discount
					 , DiscountRate
					 , DiscountRemark
					 , Rebate
					 , RebateRate
					 , RebateRemark)
    EXEC bodb_licensee.dbo.LA_AmountToCompanySel
	    @FromDate = @FromDate
	  , @ToDate = @ToDate
	  , @PartyIds = @PartyIDs
	  , @ProductCodes = @ProductList
	  , @BaseCurrency = 'MYR'
	  , @CurrencyId = 0;


    CREATE TABLE #RebateDiscount(
	    ProductId      INT
	  , ProductCode    VARCHAR(10)
	  , [Order]        INT
	  , Figure         VARCHAR(200)
	  , FullRange      MONEY);

    INSERT INTO #RebateDiscount(ProductId
						, ProductCode
						, [Order]
						, Figure
						, FullRange)
		 SELECT s.ProductId
			 , CASE
				  WHEN s.ProductId = 0
				  THEN 'SB'				 
				  ELSE p.ProductPrefix
			   END AS ProductCode
			 , CASE
				  WHEN s.ProductId = 0
				  THEN 4
				  ELSE 3
			   END AS [Order]
			 , 'Rebate & Discount' AS Figure
			 , -SUM(s.Rebate + s.Discount) AS FullRange
		 FROM #TmpData_LA AS s
			LEFT JOIN bodb_licensee.dbo.Product3rd AS p ON p.Productid = s.ProductId
		 GROUP BY s.ProductId
			   , CASE
				    WHEN s.ProductId = 0
				    THEN 'SB'				    
				    ELSE p.ProductPrefix
				END
			   , CASE
				    WHEN s.ProductId = 0
				    THEN 4
				    ELSE 3
				END
		 UNION ALL
		 SELECT ProductId
			 , ProductPrefix AS ProductCode
			 , 3 AS [Order]
			 , 'Rebate & Discount' AS Figure
			 , 0 AS FullRange
		 FROM bodb_licensee.dbo.Product3rd WITH (NOLOCK)
		 WHERE Productid NOT IN
						    (
							   SELECT DISTINCT
									ProductID
							   FROM #TmpData_LA
						    )
			  AND Productid IN(2, 5, 6, 8, 22, 11, 21, 24)
		 UNION ALL
		 SELECT 0
			 , 'SB' AS ProductCode
			 , 4 AS [Order]
			 , 'Rebate & Discount' AS Figure
			 , 0 AS FullRange
		 WHERE NOT EXISTS
					   (
						  SELECT 1
						  FROM #TmpData_LA
						  WHERE ProductId = 0
					   );
    SELECT r.ProductCode
	    , r.[Order]
	    , r.Figure
	    , SUM(r.FullRange) AS FullRange
    FROM #RebateDiscount AS r
    GROUP BY r.ProductCode
		 , r.[Order]
		 , r.Figure
    UNION ALL
/* NG & LC need to inlude Rebate Discount value to PayToSupplier*/
    SELECT r.ProductCode
	    , 4 AS [Order]
	    , 'Pay to supplier' AS Figure
	    , ISNULL(r.FullRange, 0) * -0.4 AS FullRange
    FROM #RebateDiscount AS r
    WHERE r.ProductId IN(2); /* NG, LC*/

    DROP TABLE #DiscountGroupHeader;
    DROP TABLE #DiscountGroup;
    DROP TABLE #RebateDiscount;
    DROP TABLE #TmpData_LA;
END;
GO
