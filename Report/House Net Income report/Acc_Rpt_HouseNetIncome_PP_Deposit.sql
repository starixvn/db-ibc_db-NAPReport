/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PP_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created:	20180612@Harper  
    Task :		House month-to-date Net Income report for Pramatic product
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20180618@Harper - HDWL Letstalk - Implement report for Pramatic product [#RedmineID: 94403]
		- 20190822@Robert: #115465 - Exclude bettype 4300 (Promotion Prize) from House Income, Pay to Supplier of Pragmatic
		- 20191121@Robert: #123733 - Email/Letstalk Reports - Integrate PP Tournament (Exclude bettype 4299)
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200529@Percy: PayToSupplier - Apply nested SP [RedmineID: #134867]
		- 20200715@Percy: Integrate PP Jackpot [RedmineID: #137280]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'PP'
END
GO