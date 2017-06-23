USE bodb02
GO 
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistic_ProductSel]
AS
/*
	Created by: 20160908@Sophia.Nguyen
	Task : Get Product applied for Non Sports Statistic Report
	DB: DBACC/bodb02
	
	Revisions:
		- 20170215@Percy: Integrate Fishing World [RedmineID: #71616]
		- 20170626@Cherry: Integrate Keno Lottery and Betradar Virtual Sports (#78184, #78495)

	Param Explaination:
		* Live Casino:
					SLI - Live Casino
					Gold Deluxe
					Allbet
					AG Casino
					Microgaming - Live Casino

		* RNG Casino:
					RNG Casino
					Microgaming - RNG Casino
					Macau
					Macau Games
		* Number Game

		* Virtual Sports
		* Keno

*/

BEGIN
SET NOCOUNT ON

	SELECT ProductId, CASE WHEN ProductId = 4 THEN 'SLI' ELSE ProductName END AS ProductName, CasinoType
	FROM  dbo.Products WITH (NOLOCK)
	WHERE CasinoType IN (1,2) 
		 OR ProductID IN (3, 5, 8, 24, 27, 28)
	ORDER BY ProductName 

END 
 

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistic_ProductSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistic_ProductSel] TO [vnteam]
GO