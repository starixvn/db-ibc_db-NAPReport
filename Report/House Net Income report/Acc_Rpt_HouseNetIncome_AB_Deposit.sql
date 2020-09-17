/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_AB_Deposit]
	@FromDate	DATE
   ,@ToDate		DATE
AS

/*
	Created:	20170213@Harper
	DB:			DBEXT-bodb02
	Task:		House month-to-date Net Income report for Allbet
	
	Revisions:  
		- 20170505@Harper: Change formula for Currency Play [RedmineID: #76156]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20200102@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200521@Percy: PayToSupplier - Apply nested SP [RedmineID: #134533]
		- 20200529@Percy: Special members for AB [RedmineID: #134867]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'AB'
END
GO