/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_LT_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  Created: 20170905@Harper  
    Task : House month-to-date Net Income report for Lottery [RedmineID: #79612]
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20170905@Harper: Create new SP for LT	[RedmineID: #79612]	
		- 20180917@Harper - #101314 - Commercial Terms change for Keno & Lottery (0.05 => 0.03)
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'LT'
END
GO