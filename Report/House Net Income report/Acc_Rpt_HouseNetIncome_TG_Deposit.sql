/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_TG_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS

/*  
	Created:	20200403@Percy
    Task:		Integrate Table Games product [RedmineID: #129447]
    DB:			DBEXT-bodb02
   
    Revisions:
		- 20200403@Percy: Integrate Table Games products [RedmineID: #129447]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'TG'
END
GO