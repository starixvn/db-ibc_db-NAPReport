/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_I4D_Deposit]
	@FromDate    DATE
   ,@ToDate      DATE
AS

/*
	Created:	20200324@Percy
    Task:		Integrate Indo 4D product [RedmineID: #130882]
    DB:			DBEXT-bodb02

    Revisions:
	   - 20200324@Percy: #130882 - House Net Income - Integrate Indo 4D product
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'I4D'
END
GO