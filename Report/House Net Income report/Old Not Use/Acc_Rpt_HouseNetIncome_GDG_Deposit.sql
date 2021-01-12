/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_GDG_Deposit]
	@FromDate	DATE
   ,@ToDate		DATE
AS

/*
	Created: 20201201@Percy
	DB: DBEXT-bodb02
	Task: House Net Income - Gold Diamond Gaming
	
	Revisions:  
		- 20201201@Percy: Initialize SP [RedmineID: #144106]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'GDG'
END
GO