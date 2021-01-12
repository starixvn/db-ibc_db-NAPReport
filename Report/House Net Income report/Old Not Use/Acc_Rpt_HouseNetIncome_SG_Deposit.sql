/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_SG_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created:	20200224@Kean  
    Task :		Integrate SG (Spadegaming) product [RedmineID: #123734] 
    DB:			DBEXT/bodb02  
   
    Revisions:  
	   - 20200224@Kean: #123734 - House Net Income - Integrate SG (Spadegaming) product
	   - 20200327@Kean: #131239 - Email/Letstalk Reports: Pay to supplier of Boping&Zelianta are wrongly
	   - 20200529@Percy: PayToSupplier - Apply nested SP [RedmineID: #134867]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'SG'
END
GO