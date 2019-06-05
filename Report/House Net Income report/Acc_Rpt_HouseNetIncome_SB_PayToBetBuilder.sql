/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder
	@FromDate       DATE = '20190501'
   , @ToDate         DATE = '20190510'
   , @DepositType    SMALLINT = 2
AS
/*  
    Created: Robert  
    Date: 2019-05-27  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions:		
		- 20190527@Robert: 107164 - House Net Income Email/Letstalk/Margin Chart - Integrate Bet Builder

	Param's Explanation:  
		  - DepositType  
				    = 2 All
				    = 1 Deposit Only 
				    = 0 Credit Only 

	EXEC Acc_Rpt_HouseNetIncome_SB_PayToBetBuilder '2017-12-01', '2017-12-31'
*/

BEGIN
    SET NOCOUNT ON;

    DECLARE @FDate      DATE
		, @TDate      DATE
		, @tmpDate    DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate
	    , @tmpDate = @FDate;

    DECLARE @ExchangeOANDA TABLE(
	    ExchangeDate    DATE
	  , ExchangeID      INT
	  , Rate            FLOAT);

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


    DECLARE @BetBuilderData TABLE(
	    rptDate    DATETIME
	  , WinLoss    MONEY
	  , Scomm      MONEY);

    DECLARE @FinalResult TABLE(
	    RptDate        VARCHAR(10)
	  , PayToGenius    MONEY);

    INSERT INTO @FinalResult(rptDate
					  , PayToGenius)
		 (
			SELECT 'FullRange'
				, 0 AS PayToGenius
		 );

    INSERT INTO @BetBuilderData(rptDate
						, WinLoss
						, Scomm)
		 (
			SELECT b.rptDate
				, SUM(ISNULL(b.WinlossP, 0) * e.Rate) AS WinLoss
				, SUM(ISNULL(b.CommissionS, 0) * e.Rate) AS SComm
			FROM dbwh.bodb_Account.dbo.FactSiteWinloss AS b WITH (NOLOCK)
			    INNER JOIN dbwh.bodb_Account.dbo.tbl_Site AS s WITH (NOLOCK) ON b.SiteID = s.siteid
			    INNER JOIN @ExchangeOANDA AS e ON b.rptDate = e.ExchangeDate
										   AND b.CurrencyId = e.ExchangeID
			WHERE b.rptDate BETWEEN @FDate AND @TDate
				 AND b.CurrencyID <> 20
				 AND b.CurrencyID NOT IN(27, 28)
				 AND b.Bettype = 38
				 AND b.TicketStatus NOT IN(10, 14)
				 AND s.isDeposit = CASE
								   WHEN @DepositType = 2
								   THEN s.isDeposit
								   ELSE @DepositType
							    END
			GROUP BY b.rptDate
		 );

    WHILE @tmpDate <= @TDate
	   BEGIN
		  INSERT INTO @FinalResult(RptDate
							, PayToGenius)
			    (
				   SELECT CONVERT(VARCHAR(2), @tmpDate, 106) AS RptDate
					   ,
						(
						    SELECT ISNULL(SUM((WinLoss + Scomm) * 0.04), 0)
						    FROM @BetBuilderData
						    WHERE rptDate = @tmpDate
						) AS PayToGenius
			    );

		  SELECT @tmpDate = DATEADD(DAY, 1, @tmpDate);
	   END;
-- Update Full range value
    UPDATE @FinalResult
		 SET
			PayToGenius =
			(
			    SELECT CASE
						WHEN SUM(-(WinLoss + Scomm)) < 0
						THEN 0
						ELSE SUM((WinLoss + Scomm) * 0.04)
					 END
			    FROM @BetBuilderData
			)
    WHERE RptDate LIKE 'FullRange';

    SELECT * FROM @FinalResult;
END;