/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_WM_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created: 20200922@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Integrate WM Live Casino - Deposit
	
	Revisions:  
		- 20200922@Percy: Initialize SP [RedmineID: #131593]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'WM'
END
GO