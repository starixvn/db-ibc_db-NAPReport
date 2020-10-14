/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_AGC_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created:	20161125@Harper  
    Task :		House month-to-date Net Income report for AG Casino [RedmineID: #655445] 
    DB:			DBEXT/bodb02  
   
    Revisions:  
	   - 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
	   - 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
	   - 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
	
	Param's Explanation:   

	EXEC Acc_Rpt_HouseNetIncome_AGC_Deposit '20160901', '20160930'
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'AGC'
END
GO