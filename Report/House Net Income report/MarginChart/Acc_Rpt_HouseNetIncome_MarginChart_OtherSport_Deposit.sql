/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  	
	Created: 20180126@Harper 
	Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 89632]
    Source : Acc_Rpt_HouseNetIncome_SB_Deposit
    DB: DBEXT/bodb02  
   
    Revisions:
		- 20180126@Harper - HDWL Letstalk - Implement Chart of SB margin Other Sport[#RedmineID: 89632]
		- 20190121@Robert: Letstalk Margin Charts - Separate Letstalk group for credit & Deposit (Soccer & Other Sports) [#108220]
		
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit '2017-12-01', '2017-12-31'
  
*/    
BEGIN  
    SET NOCOUNT ON;

    DECLARE @FDate    DATE
		, @TDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;
    -- Region: Get exchange rate info	

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
    -- End region		

    -- Region: Handle data of Soccer

    CREATE TABLE #FinalResult(
	    RptDate          VARCHAR(10)
	  , PayToMuayThai    MONEY
	  , HouseWL          MONEY DEFAULT 0
	  , ExtraPT          MONEY DEFAULT 0
	  , TurnOver         MONEY DEFAULT 0);

    INSERT INTO #FinalResult(rptDate
					  , PayToMuayThai)
		 SELECT 'FullRange'
			 , 0;
    -- Date list to draw chart

    DECLARE @tmpDate     DATE
		, @DateList    VARCHAR(200);

    SELECT @tmpDate = @FDate;

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO #FinalResult(RptDate
							, PayToMuayThai)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;

    SELECT @DateList = COALESCE(@DateList+',', '')+'['+CONVERT(VARCHAR(10), RptDate)+']'
    FROM #FinalResult;
    ---------------------------------------------------- Pay to Muay Thai -------------------------------------------------------
    -- Region: Get Party list, including credit licensees	

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT);

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit)
		 SELECT DISTINCT
			   ci.FromParty
			 , pd.IsDeposit
		 FROM bodb_licensee.dbo.OAS_Party AS p WITH (NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo AS ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping AS map ON map.ChargeID = ci.ChargeID
																  AND map.SystemID = 2
		 WHERE p.PartyType = 1
			  AND ci.ProductId = 0 -- SB
			  AND
				 (ci.FromDate BETWEEN @FDate AND @TDate
				  OR ci.ToDate BETWEEN @FDate AND @TDate
				  OR ci.FromDate < @FDate
				  AND @TDate < ci.ToDate);

    DECLARE @PartyIDs    VARCHAR(1000);

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty;

    DECLARE @PartyChargeInfo AS TABLE(
	    PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

    INSERT INTO @PartyChargeInfo(PartyId
						 , LicenseeId
						 , IsDeposit
						 , ProductID
						 , Rate
						 , Fromdate
						 , Todate)
		 SELECT PartyID
			 , LicenseeID
			 , isDeposit
			 , ProductID
			 , DI_Rate
			 , Fromdate
			 , Todate
		 FROM bodb_licensee.dbo.LA_f_ChargeInfo
			 (@PartyIds, @FDate, @TDate, 'SB', 'OA', 0);
    -- End Region: Get Party list, including credit licensees		

    DECLARE @MuayThaiData TABLE(
	    rptDate           DATE
	  , AmtDueMuayThai    MONEY);

    DECLARE @ShareRate    MONEY = 0.03;

    DECLARE @CutOfDate      SMALLDATETIME
		, @TmpFromDate    SMALLDATETIME
		, @TmpToDate      SMALLDATETIME; 

    SELECT @CutOfDate = '2017-09-30'; -- New formula when caculate muaythai ticket be applied	

    IF @FDate < @CutOfDate -- Old Data: incase when handle script by hand for regen past email
	   BEGIN
		  INSERT INTO @MuayThaiData
			    SELECT b.rptDate
				    , SUM(ISNULL(b.WLShare * e.Rate, 0) + ISNULL(b.CommShare * e.Rate, 0)) AS AmtDueMuayThai
			    FROM bodb_LicenseeReport.dbo.rpt_BettingBySport AS b WITH (NOLOCK)
				   INNER JOIN @PartyChargeInfo AS p ON b.ProductID = p.ProductID
											    AND b.SiteID = p.LicenseeId
											    AND b.rptDate BETWEEN p.FromDate AND p.ToDate
				   INNER JOIN #ExchangeOANDA AS e ON e.ExchangeDate = b.rptDate
											  AND e.ExchangeID = b.CurrencyId
			    WHERE b.rptDate BETWEEN @FDate AND @TDate
					AND b.CurrencyID <> 20
					AND b.StatusId BETWEEN 111 AND 113
					AND b.customercategory NOT IN(27, 28)
					AND b.SportType = 44 -- Muay Thai
			    GROUP BY b.rptdate;
	   END;
	   ELSE
	   BEGIN
		  INSERT INTO @MuayThaiData
		  SELECT b.rptDate
			  , SUM(ISNULL(b.AdjustedCustomerWL * e.Rate * (-@ShareRate), 0) + ISNULL(b.AdjustedCommShare * e.Rate, 0)) AS AmtDueMuayThai
		  FROM bodb_LicenseeReport.dbo.rpt_BettingBySport AS b WITH (NOLOCK)
			 INNER JOIN @PartyChargeInfo AS p ON b.ProductID = p.ProductID
										  AND b.SiteID = p.LicenseeId
										  AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			 INNER JOIN #ExchangeOANDA AS e ON e.ExchangeDate = b.rptDate
										AND e.ExchangeID = b.CurrencyId
		  WHERE b.rptDate BETWEEN @FDate AND @TDate
			   AND b.CurrencyID <> 20
			   AND b.StatusId BETWEEN 111 AND 113
			   AND b.customercategory NOT IN(27, 28)
			   AND b.SportType = 44 -- Muay Thai
		  GROUP BY b.rptdate;
	   END;
    -- Update daily amount

    UPDATE r
		 SET
			PayToMuayThai = -d.AmtDueMuayThai
    FROM #FinalResult r
	   INNER JOIN @MuayThaiData d ON r.RptDate = CONVERT(VARCHAR(2), d.RptDate, 106);
    --- GET TO & House Income

    CREATE TABLE #TmpHouseWL(
	    rptDate     VARCHAR(10)
	  , HouseWL     MONEY
	  , TurnOver    MONEY
	  , ExtraPT     MONEY);

    INSERT INTO #TmpHouseWL(rptDate
					 , HouseWL					 
					 , ExtraPT
					 , TurnOver)

    EXEC dbwh.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Sub
	    @FDate
	  , @TDate
	  , @IsDeposit = 1;

    UPDATE f
		 SET
			f.HouseWL = ISNULL(f.HouseWL, 0) + ISNULL(wl.HouseWL, 0)
		   , f.TurnOver = ISNULL(f.TurnOver, 0) + ISNULL(wl.TurnOver, 0)
		   , f.ExtraPT = ISNULL(f.ExtraPT, 0) + ISNULL(wl.ExtraPT, 0)
    FROM #FinalResult f
	   INNER JOIN #TmpHouseWL wl ON wl.rptDate = f.RptDate;
	---------------------------------------------------- Select the output -------------------------------------------------------
	DECLARE @SQL VARCHAR(1000)
	SELECT @SQL =	'SELECT * ' + CHAR(13) +
					'FROM	(SELECT ProductCode, [Order], [RptDate], Figure, ISNULL(value, 0) value FROM #FinalResult' + CHAR(13) +
							'CROSS APPLY' + CHAR(13) +
							'(SELECT ''OtherSport'', 1, ''House Income'', HouseWL' + CHAR(13) +
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 8, ''Turn Over'', TurnOver' + CHAR(13) +							
							'UNION ALL' + CHAR(13) +
							'SELECT ''OtherSport'', 6, ''Pay to Muay Thai'', PayToMuayThai) c (ProductCode, [Order], Figure, value)) a' + CHAR(13) +
					'PIVOT' + CHAR(13) +
					'(' + CHAR(13) +
						'MAX(value)' + CHAR(13) +
						'FOR [RptDate] in (' + @DateList + ')' + CHAR(13) +
					') piv' + CHAR(13) +
					'ORDER BY [Order]'

	EXEC(@SQL)

	DROP TABLE #ExchangeOANDA
	DROP TABLE #FinalResult	
	DROP TABLE #TmpHouseWL
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_MarginChart_OtherSport_Deposit] TO [bodbAdminNet]
GO

