/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SA_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS

/*
	Created:	20200324@Percy
    Task:		Integrate SA Gaming product [RedmineID: #128059]
    DB:			DBEXT-bodb02

    Revisions:
	   - 20200324@Percy: #128059 - House Net Income - Integrate SA Gaming product
	   - 20200529@Percy: PayToSupplier - Apply nested SP [RedmineID: #134867]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'SAG'
END
GO