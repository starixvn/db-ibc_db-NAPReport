/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_KN_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created: Victor  
	Date: 2016-08-15  
    Task : House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20160916@Harper - #64211 - Add (-1) when caculate value for PayToSupplier
		- 20160923@Harper - #64582 - PayToSupplier should use ExchangeOANDA
		- 20160926@Harper - #64744 - Full Range should be SUM from 2 Keno Rate
		- 20180917@Harper - #101314 - Commercial Terms change for Keno & Lottery (0.05 => 0.03)
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'KN'
END
GO