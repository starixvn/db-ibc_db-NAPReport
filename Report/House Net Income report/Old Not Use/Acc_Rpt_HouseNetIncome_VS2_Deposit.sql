/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_VS2_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  Created: 20170825@Harper  
    Task: House month-to-date Net Income report for Virtual Sports 2 (VS2) [RedmineID: #79612]
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20170825@Harper: Create new SP for VS2 [RedmineID: #79612]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'VS2'
END
GO