/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CO_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS  
/*  
	Created:	20170518@Harper  
    Task :		House month-to-date Net Income report for Cashout
    DB:			DBEXT.bodb02  
   
    Revisions:  
		- 20170518@Harper: Create new SP for House Daily Winloss [RedmineID: #76695]
		- 20171019@Harper: Change for CO 100% [RedmineID: #84331]
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'CO'
END
GO