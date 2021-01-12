/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_MacauGames_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created:	20170213@Harper
    Task:		House month-to-date Net Income report for Macau Game
    DB:			DBEXT-bodb02
   
    Revisions:
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200403@Percy: Integrate Blueprint's games - Macau Games [RedmineID: #131755]
		- 20200827@Percy: Use table to apply Blueprint's games - Macau Games [RedmineID: #140459]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'VB'
END
GO