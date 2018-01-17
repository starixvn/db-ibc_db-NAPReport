USE bodb02	
GO 
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTypeSel]
AS
/*
	Created by: 20160908@Sophia.Nguyen
	Task : Get Game Type (Bettype of Products) and (LeagueID of NumberGame) and (Sporttype of Virtual Sports) [Redmine: #62430]
	DB: DBACC/bodb02
 
	Revisions:	
		- 20170215@Percy: Integrate Fishing World [RedmineID: #71616]
		- 20170626@Cherry: Integrate Keno Lottery and Betradar Virtual Sports (#78184, #78495)
		- 20170926@Cherry: Integrate Lucky 3 (#83101)
		- 20171003@Cherry: Add Number Game Bettype (#83101)
		- 20171116@Cherry: Integrate Bullfighting (#85946)
		- 20180116@Cherry: Integrate OneRNG Jackpot, except bettype (2199, 2399, 2999)
*/
 
BEGIN
SET NOCOUNT ON 
	
					  
	--------Get Sport Bettype Matrix------
	 -- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	CREATE TABLE #SportBettype (ProductId INT, TypeId INT, TypeName NVARCHAR(1000), IsTest BIT DEFAULT(0), GameType TINYINT) --GameType: SportType=1, Bettype=2, League=3
 
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName, GameType)
	SELECT	s.ProductID, s.Bettype as TypeId, b.typenamee AS TypeName, 2 AS GameType
	FROM	dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN dbo.Bettype b ON s.Bettype = b.TypeId 
	WHERE  CasinoType IN (1,2) 
		   OR ProductID IN (8, 24, 26, 28, 30) 	 
		   AND b.TypeId NOT IN (2199, 2399, 2999)

	
	--- ProductID = 3 - Number Game get LeagueId
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName, IsTest, GameType)
	SELECT  3 as ProductId,
			leagueid as TypeId ,
			leaguename as TypeName,
			IsTest,
			3 AS GameType
	FROM	dbo.league WITH (NOLOCK)
	WHERE	sporttype = 161 
		 
	--- ProductID = 5, 27 - Virtual Sports, Virtual Sports 2 get Sporttype
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName, GameType)
	SELECT DISTINCT sb.ProductID, sb.SportType, s.SportName, 1 AS GameType
	FROM dbo.SportBettypeMatrix sb WITH (NOLOCK)
		INNER JOIN dbo.Sports s WITH (NOLOCK) ON sb.SportType = s.SportType 
	WHERE sb.ProductID IN (5,27)
		AND (sb.IsTest = 0 OR sb.IsTest = @isTest)	
		
	-- ProductID = 3 - Number Game get Bettype
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName, GameType)
	SELECT	s.ProductID, s.Bettype as TypeId, b.typenamee AS TypeName, 2 AS GameType
	FROM	dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN dbo.Bettype b ON s.Bettype = B.TypeId 
	WHERE s.ProductID = 3
	
	SELECT	* 
	FROM	#SportBettype
	ORDER BY ProductId, TypeName
	
	DROP TABLE #SportBettype

END

 
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTypeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTypeSel] TO [vnteam]
GO