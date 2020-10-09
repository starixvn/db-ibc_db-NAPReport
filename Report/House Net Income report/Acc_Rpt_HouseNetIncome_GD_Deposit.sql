/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_GD_Deposit]
	@FromDate DATE 
	, @ToDate	DATE 
AS  
/*  
	Created:	20170213@Harper  
    Task :		House month-to-date Net Income report for Gold Deluxe
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20181019@Robert: DHWL & Margin Chart Email Letstalk - Change GD Formula for Credit and Deposit[#103476]
		- 20181113@Robert: DHWL Email/Letstalk/Margin Chart - Integrate Bidme & Sicbo[#104145]
		- 20190308@Robert: 109770 - House Net Income - Change formula for MTD values and add old month data into a new sheet
		- 20200102@Robert: #125762 - DHWL Letstalk - Support to add Margin report into the current DHWL Letstalk report
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'GD'
END
GO