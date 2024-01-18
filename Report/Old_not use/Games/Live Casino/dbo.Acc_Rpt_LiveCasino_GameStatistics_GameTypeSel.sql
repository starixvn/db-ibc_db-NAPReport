ALTER PROCEDURE [dbo].[Acc_Rpt_LiveCasino_GameStatistics_GameTypeSel]
	@ProductID TINYINT = 0  
AS
SET NOCOUNT ON
/*
	Created by: Daniel
	Date: 2012-02-17
	Task : Retrieve Live Casino Bettypes and Gold Deluxe
	DB: DBACC/bodb02
	Original:

	Revisions:
		- 20150601@Sophia: Apply Gold Deluxe [#35359] 
		- 20150702@Sophia: Apply Microgaming and SuperBalance [#38168]
		- 20151111@Percy: Change the sport type: MGC_LC-RNG to LC and RNG [RedmineID: #46576]
		- 20160223@Robert: Add new range bettype for Allbet Live Casino #50921
	Parameters Explanation:
		- @ProductID = 0 : All
					 = 4 : Live Casino
					 = 12: Gold Deluxe
					 = 11: AG Casino
					 = 13: Microgaming [<> RNG casino]

*/
SET NOCOUNT ON

	----Get Sport Bettype Matrix------
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,EventType INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	EXEC bodb02.dbo.Acc_SportBettypeMatrix_Sel @mode = 5 

	DELETE @SportBettype 
	WHERE ProductID NOT IN (4,11,12,13,21) 
		  

	SELECT	s.ProductId, b.typeID, b.typenamee 
	FROM	bettype b WITH (NOLOCK) 
		INNER JOIN @SportBettype s 
			ON s.Bettype = b.typeid
	WHERE	s.ProductId = @ProductID 
			OR @ProductID = 0
	ORDER BY s.ProductId, b.typeID ASC

 



GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_LiveCasino_GameStatistics_GameTypeSel] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_LiveCasino_GameStatistics_GameTypeSel] TO [vnteam] AS [dbo]
GO