/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CS_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created: Victor  
	Date: 2016-08-15  
    Task: House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20160922@Harper - #63926 - Remove IsApplyMinFee
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'CS'
END
GO