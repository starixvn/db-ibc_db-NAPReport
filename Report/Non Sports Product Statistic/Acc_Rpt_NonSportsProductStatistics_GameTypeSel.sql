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
*/
 
BEGIN
SET NOCOUNT ON 
	
					  
	--------Get Sport Bettype Matrix------
	 -- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	CREATE TABLE #SportBettype (ProductId INT, TypeId INT, TypeName NVARCHAR(1000), IsTest BIT DEFAULT(0))
 
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName)
	SELECT	s.ProductID, s.Bettype as TypeId, b.typenamee AS TypeName
	FROM	dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
	INNER JOIN dbo.Bettype b ON s.Bettype = B.TypeId 
	WHERE  CasinoType IN (1,2) 
		   OR ProductID IN (8, 24, 28) 	 

	
	--- ProductID = 3 - Number Game get LeagueId
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName, IsTest)
	SELECT  3 as ProductId,
			leagueid as TypeId ,
			leaguename as TypeName,
			IsTest
	FROM	dbo.league WITH (NOLOCK)
	WHERE	sporttype = 161 
		 
	--- ProductID = 5 - Virtual Sports get Sporttype
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName)
	SELECT	5 as ProductId,
			Sporttype as TypeId ,
			SportName as TypeName
	FROM	dbo.Sports WITH (NOLOCK)
	WHERE	sporttype BETWEEN 180 AND 186	
	UNION --ProductID = 27 - Betradar Virtual Sports
	SELECT	27 as ProductId,
			Sporttype as TypeId ,
			SportName as TypeName
	FROM	dbo.Sports WITH (NOLOCK)
	WHERE	sporttype BETWEEN 190 AND 196	 
	
	SELECT	* 
	FROM	#SportBettype
	ORDER BY ProductId, TypeName

END

 
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTypeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTypeSel] TO [vnteam]
GO