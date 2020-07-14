ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome_WL_TO_CN88_ALL 
	@FromDate    SMALLDATETIME
   , @ToDate      SMALLDATETIME
AS
/*
Creator: Robert
Date: 20191224
Task:  DHWL Letstalk - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report [125762]
DB: DBWH.bodb_dwrs

Revisions:
	20191224@Robert: Initialize SP	
	20200113@Ned.Le: DHWL Letstalk Reports - Break SB into Soccer, OS and Parlay (#126634)
	20200202@Robert: #126634 DHWL - break OS into Basketball, E-sports, Tennis and Other Sports
Example:

EXEC [Acc_Rpt_HouseNetIncome_WL_TO_CN88_ALL] @@FromDate='20190801',@@ToDate='20190801'
*/

    BEGIN
	   SET NOCOUNT ON;

	   DECLARE @SiteCN88    INT;

	   SELECT TOP 1 @SiteCN88 = SiteId
	   FROM bodb_Account.dbo.tbl_Site WITH(NOLOCK)
	   WHERE site = 'CN88';

	   CREATE TABLE #CurrencyDaily(
		   ExchangeDate    DATE
		 , Currency        INT
		 , Rate            FLOAT);

	   INSERT INTO #CurrencyDaily
			SELECT ExchangeDate
				, Currency
				, Rate
			FROM bodb_account.dbo.tbl_currency_daily AS ex WITH(NOLOCK)
			WHERE ExchangeDate BETWEEN @FromDate AND @ToDate;

	   CREATE CLUSTERED INDEX PK_tmp_CurrencyDaily ON #CurrencyDaily(ExchangeDate, Currency);

	   CREATE TABLE #SportBettypesMatrix(
		   ProductPrefix    VARCHAR(20)
		 , ProductId        TINYINT
		 , SportType        SMALLINT
		 , Bettype          SMALLINT
		 , SubProduct       VARCHAR(50));

	   INSERT INTO #SportBettypesMatrix(ProductPrefix
							    , ProductId
							    , SportType
							    , Bettype
							    , SubProduct)
	   EXEC Acc_Rpt_HouseNetIncome_SportBettypesMatrix;

	   CREATE NONCLUSTERED INDEX IX_SportBettypesMatrix_SportType_BetType ON #SportBettypesMatrix(SportType, BetType);

	   CREATE TABLE #RawData(
		   ProductPrefix    VARCHAR(50)
		 , rptDate          DATE
		 , CreditTO         DECIMAL(18, 8)
		 , DepositTO        DECIMAL(18, 8)
		 , TOCN88           DECIMAL(18, 8)
		 , WinLossCN88      DECIMAL(18, 8));

	   INSERT INTO #RawData(ProductPrefix
					  , rptDate
					  , CreditTO
					  , DepositTO
					  , TOCN88
					  , WinLossCN88)
			SELECT CASE
					 WHEN sb.ProductPrefix = 'SB'
					 THEN CASE
							WHEN sb.SportType = 1
							THEN 'Soccer'
							WHEN sb.SportType = 2
							THEN 'Basketball'
							WHEN sb.SportType = 5
							THEN 'Tennis'
							WHEN sb.SportType = 43
							THEN 'E-Sports'
							ELSE 'OS'
						 END
					 ELSE sb.ProductPrefix
				  END AS ProductPrefix
				, sd.RptDate
				, SUM(CASE
						WHEN s.isDeposit = 0
						THEN CASE
							    WHEN TurnoverIBC = 0
							    THEN 0
							    ELSE TurnoverIBC - ExtraTO
							END * CASE
									WHEN VarianceVR > 0
									THEN VarianceVR + 1
									ELSE 1
								 END * ex.Rate
						ELSE 0
					 END) AS CreditTO
				, SUM(CASE
						WHEN s.isDeposit = 1
						THEN CASE
							    WHEN TurnoverIBC = 0
							    THEN 0
							    ELSE TurnoverIBC - ExtraTO
							END * CASE
									WHEN VarianceVR > 0
									THEN VarianceVR + 1
									ELSE 1
								 END * ex.Rate
						ELSE 0
					 END) AS DepositTO
				, SUM(CASE
						WHEN s.siteid = @SiteCN88
						THEN CASE
							    WHEN TurnoverIBC = 0
							    THEN 0
							    ELSE TurnoverIBC - ExtraTO
							END * CASE
									WHEN VarianceVR > 0
									THEN VarianceVR + 1
									ELSE 1
								 END * ex.Rate
						ELSE 0
					 END) AS TOCN88
				, -SUM(CASE
						 WHEN s.siteid = @SiteCN88
						 THEN(WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate
						 ELSE 0
					  END) AS WinLossCN88
			FROM bodb_Account.dbo.FactSiteWinloss AS sd WITH(NOLOCK)
			    INNER JOIN #SportBettypesMatrix AS sb ON sd.BetType = sb.BetType
												AND sd.SportType = sb.SportType
			    LEFT JOIN #CurrencyDaily AS ex WITH(NOLOCK) ON sd.rptDate = ex.ExchangeDate
													 AND sd.CurrencyID = ex.Currency
			    LEFT JOIN bodb_Account.dbo.tbl_Site AS s WITH(NOLOCK) ON sd.SiteID = s.siteid
			WHERE sd.rptdate >= CAST(@FromDate AS DATE)
				 AND rptdate <= CAST(@ToDate AS DATE)
				 AND sd.TicketStatus NOT IN(-1, 18, 9, 10, 14)
				 AND sd.CurrencyID <> 20
				 AND sd.BetType NOT IN(9, 29)
			GROUP BY CASE
					   WHEN sb.ProductPrefix = 'SB'
					   THEN CASE
							  WHEN sb.SportType = 1
							  THEN 'Soccer'
							  WHEN sb.SportType = 2
							  THEN 'Basketball'
							  WHEN sb.SportType = 5
							  THEN 'Tennis'
							  WHEN sb.SportType = 43
							  THEN 'E-Sports'
							  ELSE 'OS'
						   END
					   ELSE sb.ProductPrefix
				    END
				  , sd.RptDate;

	   INSERT INTO #RawData(ProductPrefix
					  , rptDate
					  , CreditTO
					  , DepositTO
					  , TOCN88
					  , WinLossCN88)
			SELECT 'Parlay'
				, sd.RptDate
				, SUM(CASE
						WHEN s.isDeposit = 0
						THEN CASE
							    WHEN TurnoverIBC = 0
							    THEN 0
							    ELSE TurnoverIBC - ExtraTO
							END * CASE
									WHEN VarianceVR > 0
									THEN VarianceVR + 1
									ELSE 1
								 END * ex.Rate
						ELSE 0
					 END) AS CreditTO
				, SUM(CASE
						WHEN s.isDeposit = 1
						THEN CASE
							    WHEN TurnoverIBC = 0
							    THEN 0
							    ELSE TurnoverIBC - ExtraTO
							END * CASE
									WHEN VarianceVR > 0
									THEN VarianceVR + 1
									ELSE 1
								 END * ex.Rate
						ELSE 0
					 END) AS DepositTO
				, SUM(CASE
						WHEN s.siteid = @SiteCN88
						THEN CASE
							    WHEN TurnoverIBC = 0
							    THEN 0
							    ELSE TurnoverIBC - ExtraTO
							END * CASE
									WHEN VarianceVR > 0
									THEN VarianceVR + 1
									ELSE 1
								 END * ex.Rate
						ELSE 0
					 END) AS TOCN88
				, -SUM(CASE
						 WHEN s.siteid = @SiteCN88
						 THEN(WinlossIBC - ExtraWL + CommissionS - ExtraComm) * ex.rate
						 ELSE 0
					  END) AS WinLossCN88
			FROM bodb_Account.dbo.FactSiteWinloss AS sd WITH(NOLOCK)
			    LEFT JOIN #CurrencyDaily AS ex WITH(NOLOCK) ON sd.rptDate = ex.ExchangeDate
													 AND sd.CurrencyID = ex.Currency
			    LEFT JOIN bodb_Account.dbo.tbl_Site AS s WITH(NOLOCK) ON sd.SiteID = s.siteid
			WHERE sd.rptdate >= CAST(@FromDate AS DATE)
				 AND rptdate <= CAST(@ToDate AS DATE)
				 AND sd.TicketStatus NOT IN(-1, 18, 9, 10, 14)
				 AND sd.CurrencyID <> 20
				 AND sd.BetType IN(9, 29)
			GROUP BY sd.RptDate;

	   SELECT ProductPrefix
		   , rptDate
		   , SUM(CreditTO) AS CreditTO
		   , SUM(DepositTO) AS DepositTO
		   , SUM(TOCN88) AS TOCN88
		   , SUM(WinLossCN88) AS WinLossCN88
	   FROM #RawData
	   GROUP BY ProductPrefix
			, rptDate
	   ORDER BY ProductPrefix
			, rptDate;

	   DROP TABLE #CurrencyDaily;
	   DROP TABLE #RawData;
	   DROP TABLE #SportBettypesMatrix;
    END;
GO