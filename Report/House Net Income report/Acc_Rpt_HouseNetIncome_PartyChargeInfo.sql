/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_PartyChargeInfo 
	@FromDate     DATE
   , @ToDate       DATE
   , @ProductId    INT
AS  
/*  
	Created:	20200316@Robert
    Task :		Get ChargeInfo By Product
    DB:			DBEXT/bodb02  
   
    Revisions:  		
		- 20200316@Robert: #126465 - DHWL House Net Income, Margin Charts, DCWL Email/Letstalk - Integrate Virtual Games and Change the "Pay to supplier" formula of SG
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_PartyChargeInfo '20180601', '20180630', 32   
*/

    BEGIN
	   SET NOCOUNT ON;

	   DECLARE @FDate            DATE
		    , @TDate            DATE
		    , @ProductPrefix    VARCHAR(10) = '';
	   SELECT @FDate = @FromDate
		   , @TDate = @ToDate
		   , @ProductPrefix = p.ProductPrefix
	   FROM bodb02.dbo.Products AS p WITH(NOLOCK)
	   WHERE p.ProductID = @ProductId;
	   -- Region: Active licensees
	   DECLARE @tmpParty TABLE(
		   PartyID      INT
		 , IsDeposit    BIT
		 , ParentID     INT);
	   INSERT INTO @tmpParty(PartyID
					   , IsDeposit
					   , ParentID)
			SELECT DISTINCT 
				  ci.FromParty
				, pd.IsDeposit
				, ci.ToParty
			FROM bodb_licensee.dbo.OAS_Party AS p WITH(NOLOCK)
			    INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
			    INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH(NOLOCK) ON p.PartyID = ci.FromParty
			    INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																	 AND map.SystemID = 2
			WHERE p.PartyType = 1
				 AND pd.IsDeposit = 1
				 AND ci.ProductId = @ProductId
				 AND
					(ci.FromDate BETWEEN @FDate AND @TDate
					 OR ci.ToDate BETWEEN @FDate AND @TDate
					 OR ci.FromDate < @FDate
					 AND @TDate < ci.ToDate);

	   DECLARE @PartyIDs    VARCHAR(1000);
	   SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
	   FROM @tmpParty
	   WHERE IsDeposit = 1;
	   -- End region
	   -- Region: Get Licensees has charge rate
	   DECLARE @PartyChargeInfo AS TABLE(
		   ChargeId      INT
		 , PartyId       INT
		 , LicenseeId    INT
		 , ParentID      INT
		 , Rate          MONEY
		 , FromDate      SMALLDATETIME
		 , ToDate        SMALLDATETIME
		 , ProductID     INT);

	   INSERT INTO @PartyChargeInfo(ChargeId
							, PartyId
							, LicenseeId
							, ParentID
							, Rate
							, Fromdate
							, Todate
							, ProductID)
			(
			    SELECT ci.ChargeId
				    , ci.PartyID
				    , ci.LicenseeID
				    , p.ParentID
				    , ci.DI_Rate
				    , ci.Fromdate
				    , ci.ToDate
				    , ci.ProductID
			    FROM bodb_licensee.dbo.LA_f_ChargeInfo
				    (@PartyIDs, @FDate, @TDate, @ProductPrefix, 'OA', 1) AS ci
				   INNER JOIN @tmpParty AS p ON ci.PartyID = p.PartyID
			    WHERE DI_Rate > 0
					AND ci.ChargeType = 1 -- get PT
			);

	   SELECT p.FromDate
		   , p.ToDate
		   , p.Rate
		   , p.ProductID
		   , s.IbcSiteID AS SiteId
		   , s.SiteName
	   FROM @PartyChargeInfo AS p
		  INNER JOIN bodb_licensee.dbo.view_site_list AS s ON p.LicenseeId = s.SiteID
	   ORDER BY s.SiteName;
    END;
GO