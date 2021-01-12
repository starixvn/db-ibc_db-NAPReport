/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_GD_PayToSupplier 
	@FromDate       DATE 
   , @ToDate         DATE 
   , @DepositType    SMALLINT = 2
   , @Site       VARCHAR(20) = ''
AS  
/*  
	Created:	20200102@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
    Task :		House month-to-date Net Income report for Gold Deluxe
    DB:			DBEXT/bodb02  
   
    Revisions:  	   
	   - 20200102@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
	   - 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]

	Param's Explanation:   
	- DepositType  
				    = 2 All
				    = 1 Deposit Only
				    = 0 Credit

	EXEC Acc_Rpt_HouseNetIncome_GD_PayToSupplier '20180601', '20180619', 0, '' -- All site of Credit
	EXEC Acc_Rpt_HouseNetIncome_GD_PayToSupplier '20180601', '20180619', 1, '' -- All site of Deposit
	EXEC Acc_Rpt_HouseNetIncome_GD_PayToSupplier '20180601', '20180619', 1, '789Y' -- 789Y site of Credit
	   
	Note:
	   20181023Robert: remove the checking
		  - Credit licensees before Dec-16: Member WL x 2%; 0 if Member WL > 0.
		  - Credit licensees after Dec-16: (Member WL + Valid Bet Amt x 1%) x 3.5%
*/

    BEGIN
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

    DECLARE @TmpPartyList AS TABLE(
	    PartyID      INT
	  , PartyName    VARCHAR(200)
	  , BrandName    VARCHAR(200)
	  , ParentID     INT);

    INSERT INTO @TmpPartyList
    EXECUTE bodb_licensee..LA_PartyListSel;

    DECLARE @tmpParty TABLE(
	    PartyID       INT
	  , IsDeposit     BIT
	  , LicenseeID    INT
	  , ParentID      INT
	  , Rate          FLOAT
	  , ChargeType    INT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit
				    , LicenseeID)
		 SELECT DISTINCT 
			   p.PartyID
			 , pd.IsDeposit
			 , CASE
				  WHEN ISNULL(pd.IsDeposit, 0) = 1
				  THEN p.OldRefID
				  ELSE lb.LabelID
			   END AS LicenseeID
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map WITH(NOLOCK) ON map.ChargeID = ci.ChargeID
																			AND map.SystemID = 2 /* LA*/
			LEFT JOIN bodb_licensee.dbo.Labels AS lb WITH(NOLOCK) ON p.OldRefID = lb.LicenseeID
		 WHERE p.PartyType = 1 /* Licensee*/
			  AND ci.ProductID = 11 /* GD		*/
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
				  AND @TDate < ci.ToDate);

    UPDATE p
		 SET 
			p.ParentID = pa.ParentID
    FROM @tmpParty p
	   INNER JOIN @TmpPartyList pa ON pa.PartyID = p.PartyID;

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs + ',', '') + CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty
    WHERE IsDeposit = 1;
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
			WHERE ci.isDeposit = 1
				 AND DI_Rate > 0
				 AND ProductId <> 1 /*exclude RB */
		 );

    DECLARE @ExchangeOANDA TABLE(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    INSERT INTO @ExchangeOANDA(ExchangeDate
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
	  , LicenseeId     INT
	  , CompanyId      INT
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
			c_3rd.Fromdate = c.FromDate
		   , c_3rd.ToDate = c.ToDate
    FROM @PartyChargeInfo_3rd c_3rd
	   INNER JOIN @PartyChargeInfo c ON c.LicenseeId = c_3rd.LicenseeID;

    INSERT INTO @DailyPayAmt(RptDate
					  , IsDeposit
					  , LicenseeID
					  , AmountDaily)
		 (
			SELECT b.RptDate
				, p.IsDeposit
				, p.LicenseeID
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
			    INNER JOIN @ExchangeOANDA AS oanda ON b.RptDate = oanda.ExchangeDate
											  AND b.CurrencyId = oanda.ExchangeID
				INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID NOT IN(20, 27, 28)
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 101, 102) /* Exclude Reject , Void*/
				 AND b.Bettype = -1
				 AND p.ChargeType <> 12
				 AND (@Site = '' OR s.SiteName = @Site) 	
			GROUP BY b.RptDate
				  , p.IsDeposit
				  , p.LicenseeID
			UNION ALL
			SELECT b.RptDate
				, p.IsDeposit
				, p.LicenseeID
				, SUM(b.MemberWL * oanda.Rate * p.DI_Rate)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct AS b WITH(NOLOCK)
			    INNER JOIN @PartyChargeInfo_3rd AS p ON p.LicenseeID = b.SiteID
											    AND b.ProductId = p.ProductID
											    AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			    INNER JOIN @ExchangeOANDA AS oanda ON b.RptDate = oanda.ExchangeDate
											  AND b.CurrencyId = oanda.ExchangeID
				INNER JOIN bodb_licensee.dbo.view_site_list AS s WITH(NOLOCK) ON b.SiteId = s.SiteID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID NOT IN(20, 27, 28)
				 AND b.customercategory NOT IN(27, 28)
				 AND b.StatusId NOT IN(-1, 101, 102) /* Exclude Reject , Void*/
				 AND b.Bettype = 1706
				 AND p.ChargeType = 12
				 AND (@Site = '' OR s.SiteName = @Site)
			GROUP BY b.RptDate
				  , p.IsDeposit
				  , p.LicenseeID
		 );

    UPDATE d
		 SET 
			d.CompanyId = l.LicenseeID
    FROM @DailyPayAmt d
	   INNER JOIN bodb_Licensee.dbo.labels l WITH(NOLOCK) ON d.LicenseeID = l.LabelID;

    DECLARE @tlbPayToSupplier TABLE(
	    LicenseeId       INT
	  , CompanyId        INT
	  , IsDeposit        INT
	  , PayToSupplier    MONEY);

    INSERT INTO @tlbPayToSupplier(LicenseeID
						  , CompanyId
						  , IsDeposit
						  , PayToSupplier)
		 SELECT pay_Sub.LicenseeID
			 , pay_Sub.CompanyId
			 , pay_Sub.IsDeposit
			 , pay_Sub.PayToSupplier
		 FROM
			 (
				SELECT LicenseeID
					, CompanyId
					, IsDeposit
					, SUM(AmountDaily) AS PayToSupplier
				FROM @DailyPayAmt
				WHERE IsDeposit = 1
				GROUP BY LicenseeID
					  , CompanyId
					  , IsDeposit
				UNION ALL
				SELECT 0 AS LicenseeID
					, CompanyId
					, IsDeposit
					, SUM(AmountDaily) AS PayToSupplier
				FROM @DailyPayAmt
				WHERE IsDeposit = 0
				GROUP BY CompanyId
					  , IsDeposit
			 ) AS pay_Sub;

    DECLARE @PayToSupplier    MONEY;

    SET @PayToSupplier =
	   (
		  SELECT SUM(CASE
					  WHEN pay.PayToSupplier > 0
					  THEN 0
					  ELSE pay.PayToSupplier
				   END)
		  FROM @tlbPayToSupplier AS pay
	   );

    INSERT INTO #FinalResult(rptDate
					  , PayToSupplier)
		 SELECT 'FullRange'
			 , @PayToSupplier;

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
					 );

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList + ',', '') + '[' + CONVERT(VARCHAR(10), RptDate) + ']'
    FROM #FinalResult;

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

    DROP TABLE #FinalResult;
    END;
GO