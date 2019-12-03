/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_GD_Supplier]
	@FromDate DATE ,
	@ToDate	DATE ,
	@DepositType SMALLINT = 2
AS  

/*  	
    Created:		20191202@Robert
    Description:	HDWL Letstalk - Implement Chart of NonSport product margin
    Source :		Acc_Rpt_HouseNetIncome_MarginChart_GD_Deposit
    DB:			DBEXT/bodb02  
   
    Revisions:		
		- 20191202@Robert - Non - Sport Margin chart: data of Allbet and Gold Deluxe should be corrected [124697]
		
	Param's Explanation:   

	Acc_Rpt_HouseNetIncome_MarginChart_GD_Supplier '2018-04-01', '2018-04-30'
  
*/ 

BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    DECLARE @tmpParty TABLE(
	    PartyID       INT
	  , IsDeposit     BIT
	  , LicenseeID    INT
	  , ParentID      INT
	  , Rate          FLOAT
	  , ChargeType    INT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit
				    , LicenseeID
				    , ParentID)
		 SELECT DISTINCT 
			   p.PartyID
			 , pd.IsDeposit
			 , CASE
				  WHEN ISNULL(pd.IsDeposit, 0) = 1
				  THEN p.OldRefID
				  ELSE lb.LabelID
			   END AS LicenseeID
			 , CASE
				  WHEN ISNULL(pd.IsDeposit, 0) = 0
				  THEN 999
				  ELSE ci.ToParty
			   END /* credit*/
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID
																			AND map.SystemID = 2 /* LA*/
			LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeID
		 WHERE p.PartyType = 1 /* Licensee*/
			  AND ci.ProductID = 11 /* GD			*/
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
				  AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = CASE
					 WHEN @DepositType = 2
					 THEN IsDeposit
					 ELSE @DepositType
				  END;
    /* End region*/

    DECLARE @PartyChargeInfo AS TABLE(
	    PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT
	  , ChargeType    TINYINT);

    INSERT INTO @PartyChargeInfo(PartyId
						 , LicenseeId
						 , IsDeposit
						 , ProductID
						 , Rate
						 , Fromdate
						 , Todate
						 , Bettype
						 , ChargeType)
		 (
			SELECT ci.PartyID
				, ci.LicenseeID
				, ci.isDeposit
				, ci.ProductID
				, ci.DI_Rate
				, ci.Fromdate
				, ci.ToDate
				, ISNULL(sbr.Bettype, ci.Bettype)
				, ci.ChargeType
			FROM bodb_licensee.dbo.LA_f_ChargeInfo
				(@PartyIDs, @FDate, @TDate, 'GD', 'OA', 1) AS ci
			    LEFT JOIN bodb_licensee..Sport_Bettype_Reference AS sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
			WHERE ci.isDeposit = CASE
								WHEN @DepositType = 2
								THEN ci.isDeposit
								ELSE @DepositType
							 END
				 AND DI_Rate > 0
				 AND ProductId <> 1 /*exclude RB */
		 );

    CREATE TABLE #ExchangeOANDA(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    INSERT INTO #ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 SELECT ExchangeDate
			 , ExchangeID
			 , BaseCurrencyRate
		 FROM bodb02.dbo.LA_f_ExchangeDailySel
			 (@FDate, @TDate, 'MYR');

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , PayToSupplier    MONEY);
    /* Pay to Supplier for Credit + Deposit*/

    DECLARE @DailyPayAmt TABLE(
	    RptDate        DATE
	  , IsDeposit      INT
	  , AmountDaily    MONEY);

    DECLARE @CommissionRate    FLOAT;

    SELECT @CommissionRate = ci.DI_Rate
    FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd
	    (@FDate, @TDate, 'GD', 'OA') AS ci
    WHERE ci.ChargeType = 11;

    DECLARE @PartyChargeInfo_3rd TABLE(
	    IsDeposit     INT
	  , ProductID     INT
	  , DI_Rate       MONEY
	  , Fromdate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , ChargeType    INT
	  , LicenseeID    INT);

    INSERT INTO @PartyChargeInfo_3rd(IsDeposit
							, ProductID
							, DI_Rate
							, Fromdate
							, ToDate
							, ChargeType
							, LicenseeID)
		 SELECT DISTINCT 
			   ci.IsDeposit
			 , ci.ProductID
			 , ci.DI_Rate
			 , ci.Fromdate
			 , ci.ToDate
			 , ci.ChargeType
			 , p.LicenseeID
		 FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd
			 (@FDate, @TDate, 'GD', 'OA') AS ci
			INNER JOIN @tmpParty AS p ON p.ParentID = ci.PartyID
		 WHERE ci.ChargeType IN(1, 9, 10, 12)
			  AND ci.IsDeposit = CASE
								WHEN @DepositType = 2
								THEN ci.IsDeposit
								ELSE @DepositType
							 END;

    UPDATE c_3rd
		 SET 
			c_3rd.Fromdate = c.Fromdate
		   , c_3rd.ToDate = c.ToDate
    FROM @PartyChargeInfo_3rd c_3rd
	   INNER JOIN @PartyChargeInfo c ON c_3rd.LicenseeID = c.LicenseeID;

    INSERT INTO @DailyPayAmt(RptDate
					  , IsDeposit
					  , AmountDaily)
		 (
			SELECT b.RptDate
				, p.IsDeposit
				, SUM(CASE
						WHEN p.ChargeType IN(1, 9)
						THEN b.MemberWL * oanda.Rate * p.DI_Rate
						ELSE(b.MemberWL + CASE
										  WHEN p.IsDeposit = 1
											  AND b.StatusId = 103
										  THEN 0
										  ELSE b.ValidBetAmount
									   END * @CommissionRate) * oanda.Rate * p.DI_Rate
					 END)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH(NOLOCK)
			    INNER JOIN @PartyChargeInfo_3rd AS p ON p.LicenseeID = b.SiteID
											    AND b.ProductId = p.ProductID
											    AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			    INNER JOIN #ExchangeOANDA AS oanda ON b.RptDate = oanda.ExchangeDate
											  AND b.CurrencyId = oanda.ExchangeID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 101, 102) /* Exclude Reject , Void 				*/
				 AND b.Bettype = -1
				 AND p.ChargeType <> 12
			GROUP BY b.RptDate
				  , p.IsDeposit
			UNION ALL
			SELECT b.RptDate
				, p.IsDeposit
				, SUM(b.MemberWL * oanda.Rate * p.DI_Rate)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH(NOLOCK)
			    INNER JOIN @PartyChargeInfo_3rd AS p ON p.LicenseeID = b.SiteID
											    AND b.ProductId = p.ProductID
											    AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			    INNER JOIN #ExchangeOANDA AS oanda ON b.RptDate = oanda.ExchangeDate
											  AND b.CurrencyId = oanda.ExchangeID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 101, 102) /* Exclude Reject , Void 				*/
				 AND b.Bettype = 1706
				 AND p.ChargeType = 12
			GROUP BY b.RptDate
				  , p.IsDeposit
		 );

    INSERT INTO #FinalResult(rptDate
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , 0;

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToSupplier)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    ,
					 (
						SELECT SUM(AmountDaily)
						FROM @DailyPayAmt
						WHERE RptDate = @tmpDate
					 ) AS PayToSupplier;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;
    
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +							
							'(SELECT ''GD'', 4, ''Pay to supplier'', PayToSupplier) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult
END
GO

