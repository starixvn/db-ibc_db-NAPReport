/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistic_CurrencySel]
	@SiteType INT = -1,
	@ExcludeTest BIT = 0
AS
/*
	Created by: 20201020@Cherry
	Task: Get Currency dropdown by Site [Redmine: #140386]
	DB: DBACC.bodb02
	
	Revisions:
		20201020@Cherry: Get Currency dropdown by Site [Redmine: #140386]
		
	Param: 
		@SiteType = -1 : All, 0: Credit, 1: Deposit

*/

BEGIN
	SET NOCOUNT ON
	
	SELECT ExchangeId, Currency 
	FROM dbo.exchange WITH(NOLOCK) 
	WHERE IsActive = 1
		AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND exchangeid <> 20))
		AND (@SiteType = -1
			OR (@SiteType = 0 AND OfferSite IN (0,1)) 
			OR (@SiteType = 1 AND OfferSite IN (0,2))
			)
	
END 
GO