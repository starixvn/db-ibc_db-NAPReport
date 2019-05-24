/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_HouseNetIncome_SB_PayToMuayThai
	@FromDate       DATE
   , @ToDate         DATE
   , @DepositType    SMALLINT = 2
AS
/*  	
    Created: 20190526@Robert
    Description: HDWL Letstalk - Implement Chart of SB margin [#RedmineID: 107164]
    Source : Acc_Rpt_HouseNetIncome_SB_Deposit
    DB: DBEXT/bodb02  
   
    Revisions:		
	   - 20190406@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder
		
	Param's Explanation:   
	   - DepositType  
				    = 2 All
				    = 1 Deposit Only 
				    = 0 Credit Only 

	EXEC Acc_Rpt_HouseNetIncome_SB_PayToMuaytThai '2017-12-01', '2017-12-31'
  
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @FDate        DATE
		, @TDate        DATE
		, @PartyIDs     VARCHAR(1000) = ''
		, @ShareRate    MONEY         = 0.03
		, @tmpDate      DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate
	    , @tmpDate = @FDate;

    DECLARE @tmpParty TABLE(
	    PartyID      INT
	  , IsDeposit    BIT);

    DECLARE @PartyChargeInfo AS TABLE(
	    PartyId       INT
	  , LicenseeId    INT
	  , IsDeposit     BIT
	  , ProductID     INT
	  , Rate          MONEY
	  , FromDate      SMALLDATETIME
	  , ToDate        SMALLDATETIME
	  , Bettype       INT);

    DECLARE @MuayThaiData TABLE(
	    rptDate           DATE
	  , AmtDueMuayThai    MONEY);

    DECLARE @ExchangeOANDA TABLE(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

    DECLARE @FinalResult TABLE(
	    RptDate          VARCHAR(10)
	  , PayToMuayThai    MONEY);

    INSERT INTO @FinalResult(rptDate
					  , PayToMuayThai)
		 (
			SELECT 'FullRange'
				, 0 AS PayToMuayThai
		 );

    INSERT INTO @ExchangeOANDA(ExchangeDate
					    , ExchangeID
					    , Rate)
		 (
			SELECT ExchangeDate
				, ExchangeID
				, BaseCurrencyRate
			FROM bodb02.dbo.LA_f_ExchangeDailySel
				(@FDate, @TDate, 'MYR')
		 );

    INSERT INTO @tmpParty(PartyID
				    , IsDeposit)
		 (
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
				 AND pd.IsDeposit = CASE
								    WHEN @DepositType = 2
								    THEN pd.IsDeposit
								    ELSE @DepositType
								END
				 AND
					(ci.FromDate BETWEEN @FDate AND @TDate
					 OR ci.ToDate BETWEEN @FDate AND @TDate
					 OR ci.FromDate < @FDate
					 AND @TDate < ci.ToDate)
		 );

    SELECT @PartyIDs = COALESCE(@PartyIDs+',', '')+CONVERT(VARCHAR(10), PartyId)
    FROM @tmpParty;

    INSERT INTO @PartyChargeInfo(PartyId
						 , LicenseeId
						 , IsDeposit
						 , ProductID
						 , Rate
						 , Fromdate
						 , Todate)
		 (
			SELECT PartyID
				, LicenseeID
				, isDeposit
				, ProductID
				, DI_Rate
				, Fromdate
				, Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfo
				(@PartyIds, @FDate, @TDate, 'SB', 'OA', 0)
		 );

    INSERT INTO @MuayThaiData(rptDate
					   , AmtDueMuayThai)
		 (
			SELECT b.rptDate AS rptDate
				, SUM(ISNULL(b.AdjustedCustomerWL * e.Rate * (-@ShareRate), 0) + ISNULL(b.AdjustedCommShare * e.Rate, 0)) AS AmtDueMuayThai
			FROM bodb_LicenseeReport.dbo.rpt_BettingBySport AS b WITH (NOLOCK)
			    INNER JOIN @PartyChargeInfo AS p ON b.ProductID = p.ProductID
											AND b.SiteID = p.LicenseeId
											AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			    INNER JOIN @ExchangeOANDA AS e ON e.ExchangeDate = b.rptDate
										   AND e.ExchangeID = b.CurrencyId
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.StatusId BETWEEN 111 AND 113
				 AND b.customercategory NOT IN(27, 28)
				 AND b.SportType = 44 -- Muay Thai
			GROUP BY b.rptdate
		 );

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO @FinalResult(RptDate
							, PayToMuayThai)
			    SELECT CONVERT(VARCHAR(2), @tmpDate, 106)
				    , 0 AS PayToMuayThai;

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;


    UPDATE r
		 SET
			r.PayToMuayThai = -d.AmtDueMuayThai
    FROM @FinalResult r
	   INNER JOIN @MuayThaiData d ON r.RptDate = CONVERT(VARCHAR(2), d.RptDate, 106);

    UPDATE @FinalResult
		 SET
			PayToMuayThai = -
			(
			    SELECT ISNULL(SUM(AmtDueMuayThai), 0)
			    FROM @MuayThaiData
			)
    WHERE RptDate LIKE 'FullRange';

    SELECT RptDate
	    , PayToMuayThai
    FROM @FinalResult;
END;