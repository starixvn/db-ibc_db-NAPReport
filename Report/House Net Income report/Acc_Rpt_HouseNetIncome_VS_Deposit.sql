/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_VS_Deposit]
	@FromDate	DATE
	,@ToDate	DATE
AS

/*  
	Created: Victor  
	Date: 2016-08-15  
    Task: House month-to-date Net Income report
    DB: DBEXT/bodb02  
   
    Revisions: 
		- 20160915@Harper - #64211 - Rebate and Discount should be included when calculating the Pay to Suplplier
		- 20160919@Harper - #64338 - PayToSupplier of FullMonth is incorrect
		- 20160923@Harper - #64582 - PayToSupplier should use ExchangeOANDA
		- 20161024@Harper - #65699: HAIFA - Apply new charge rate discount for HNI report
		- 20180327@Harper - #91291 - Virtual Sports - Change of commercial terms between company and provider
		- 20190222@Robert: #109196 - House Net Income - Arrange Email notification for Licensee Figures
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'VS'
END
GO