/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_VG_Deposit]
	@FromDate DATE ,
	@ToDate	DATE 
AS  
/*  
    Created:	20200317@Kean
    Task :		Integrate Virtual Games product [#126465]
    DB:			DBEXT/bodb02  
   
    Revisions:  
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200901@Percy: Refactor code to enhance performance [RedmineID: #140677]
*/

BEGIN
    EXEC dbo.Acc_Rpt_HouseNetIncome_Product_Deposit
		@FromDate		= @FromDate
		,@ToDate		= @ToDate
		,@ProductList	= 'VRG'
END
GO