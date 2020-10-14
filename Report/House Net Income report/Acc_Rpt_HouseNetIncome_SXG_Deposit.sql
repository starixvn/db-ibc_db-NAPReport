/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SXG_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS

/*
	Created:	20200422@Percy
    Task:		Integrate Sexy Gaming product [RedmineID: #132792]
    DB:			DBEXT-bodb02

    Revisions:
	   - 20200422@Percy: House Net Income - Integrate Sexy Gaming product [RedmineID: #132792]
	   - 20200529@Percy: PayToSupplier - Apply nested SP [RedmineID: #134867]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'SXG'
END
GO