/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_FW_Deposit]
	@FromDate	DATE
   ,@ToDate		DATE
AS

/*
	Created:	20170213@Harper
	DB:			DBEXT-bodb02
	Task:		House month-to-date Net Income report for Fishing World
	
	Revisions:  
	   - 20181019@Robert: Nap Reports - House Net Income - Pay to Supplier(Month-to-date) of Gold Deluxe & Fishing World is incorrect [#103380]
	   - 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
	   - 20200521@Percy: Re-integrate FW [RedmineID: #134533]
	   - 20200529@Percy: PayToSupplier - Apply nested SP [RedmineID: #134867]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'FW'
END
GO