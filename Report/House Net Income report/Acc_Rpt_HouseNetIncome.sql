/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE dbo.Acc_Rpt_HouseNetIncome @FromDate DATE,
										   @ToDate DATE,
										   @ProductList VARCHAR(MAX) = 'ALL',
										   @DepositType	TINYINT = 2,
										   @IsOldView BIT = 0,
										   @IsLicperf		BIT = 0,
										   @BaseCurrencyName  VARCHAR(10) = 'RMB'

AS

/*
	Created:	20201117@Ned.Le
    Task:		Synthesize all data from child SPs for Hosue Net Income report
    DB:			DBWH/bodb_dwrs
   
    Revisions:
		20201117@Ned.Le: DHWL Email/Letstalk - Restructure source code to improve performance & Separate House Income into Credit Income and Licensee Income (#143208)
		20210616@Danny: Support Licensee Performance view mode (#156727)

	Param's Explanation:
		@ProductList: 'ALL' - Get data of all product
					  'SB'  - Get data of Sportsbook
		              Other - References to column ProductPrefix of table HNISettings
		@DepositType: 0 Credit Only
					  1 Deposit Only
					  2 All
	
	Example:
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome '20200901', '20200930', 'ALL', 2, 0
*/

BEGIN
	
	IF @IsLicperf = 1
	BEGIN
			-- Acc_Rpt_HouseNetIncome_Deposit
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Deposit		 @FromDate = @FromDate,
																 @ToDate = @ToDate,
																 @ProductList = @ProductList,
																 @IsLicperf = @IsLicperf,
																 @BaseCurrencyName = @BaseCurrencyName

		-- Acc_Rpt_HouseNetIncome_PayToSupplier
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_PayToSupplier	 @FromDate = @FromDate,
																 @ToDate = @ToDate,
																 @ProductList = @ProductList,
																 @DepositType = 1,
																 @IsOldView = @IsOldView,
																 @IsLicperf = @IsLicperf,
																 @BaseCurrencyName = @BaseCurrencyName
	END
	ELSE
	BEGIN
		-- Acc_Rpt_HouseNetIncome_Credit
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Credit		 @FromDate = @FromDate,
																 @ToDate = @ToDate,
																 @ProductList = @ProductList

		-- Acc_Rpt_HouseNetIncome_Deposit
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_Deposit		 @FromDate = @FromDate,
																 @ToDate = @ToDate,
																 @ProductList = @ProductList

		-- Acc_Rpt_HouseNetIncome_PayToSupplier
		EXEC bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_PayToSupplier	 @FromDate = @FromDate,
																 @ToDate = @ToDate,
																 @ProductList = @ProductList,
																 @DepositType = @DepositType,
																 @IsOldView = @IsOldView
	 END

END
