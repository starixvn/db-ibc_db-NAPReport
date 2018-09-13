USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_GamesActive_Products]
AS  
/*
 Created: Jim
 Task : Get Product List for Report Number of Active Game
 DB: DBAGE/bodb02  
 Original:  
  
 Revisions:
	- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
	- 20151210@Percy: Add new product: Cockfighting Sabong [Redmine: #49027]
	- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
	- 20160411@Robert: Integrate Voidbridge Credit - Single Wallet model [RedmineID: #55589]
	- 20160916@Robert:
		1. Integrate new product NG2 [RedmindID: #63460]
		2. Remove Cockfighting - ProductID = 19
	- 20180830@Cherry: Integrate Poker Games (#97830)
*/
SELECT
	CONVERT(INT,-1) ProductID
	,'MG-SuperLive' ProductName
UNION ALL
SELECT
	ProductID
	,ProductName
FROM dbo.Products WITH (NOLOCK)
WHERE ProductID IN (3,6,7,8,4,11,12,13,17,14,15,21,22,23,33)

GO
GRANT ALTER ON [dbo].[Acc_Rpt_GamesActive_Products] TO [bodbAdminNet] AS [dbo]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_GamesActive_Products] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_GamesActive_Products] TO [vnteam] AS [dbo]
GO