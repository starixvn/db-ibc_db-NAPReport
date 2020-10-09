/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_PGS_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created: 20200818@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Integrate PG Soft - Deposit
	
	Revisions:  
		- 20200818@Percy: Initialize SP [RedmineID: #137764]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'PGS'
END
GO