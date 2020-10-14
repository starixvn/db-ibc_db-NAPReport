/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_CC_Deposit]
	@FromDate	DATE,
	@ToDate		DATE
AS

/*
	Created:	20190819@Robert
    Task:		House month-to-date Net Income report for Card Club
    DB:			DBEXT-bodb02  
   
    Revisions:  
		- 20190819@Robert - NAP Report - Integrate Card Club on NAP Report [#115465]
		- 20200108@Percy: #124755 - Support billing terms by product & currency instead of product only
		- 20200313@Kean - Change the "Pay to supplier" formula of CC(New Bettype 1902) - #126465
		- 20200403@Percy: Integrate Xoc Dia - CC (Bettype 1903) [RedmineID: #131507]
		- 20200422@Percy: Integrate 3D Lottery - CC (Bettype 1904) [RedmineID: #132790]
		- 20200519@Percy: Integrate Midas Hi-Lo - CC (Bettype 1905) [RedmineID: #133594]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'CC'
END
GO