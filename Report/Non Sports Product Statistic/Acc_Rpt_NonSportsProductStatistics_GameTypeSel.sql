/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO 
 
ALTER PROCEDURE [dbo].[Acc_Rpt_NonSportsProductStatistics_GameTypeSel]
AS
/*
	Created by: 20160908@Sophia.Nguyen
	Task : Get Game Type (Bettype of Products) and (LeagueID of NumberGame) and (Sporttype of Virtual Sports) [Redmine: #62430]
	DB: DBACC/bodb02
 
	Revisions:	
		20170215@Percy: Integrate Fishing World [RedmineID: #71616]
		20170626@Cherry: Integrate Keno Lottery and Betradar Virtual Sports (#78184, #78495)
		20170926@Cherry: Integrate Lucky 3 (#83101)
		20171003@Cherry: Add Number Game Bettype (#83101)
		20171116@Cherry: Integrate Bullfighting (#85946)
		20180116@Cherry: Integrate OneRNG Jackpot, except bettype (2199, 2399, 2999)
		20180808@Cherry: Integrate Poker Games (#97809)
		20181004@Cherry: Integrate ColosusBet and NG2 (#102229)
		20181130@Cherry: Integrate Happy 5 (#103498)
		20190328@Cherry: Integrate Promotion Prize (#109203)
		20191115@Cherry: Integrate PP Tournament (#123660)
		20200220@Cherry: Integrate Virtual Games (#124753)
		20200828@Cherry: Integrate Saba.club Free Bet (#140109)
		20201224@Cherry: Integrate Happy 5 Linked Games (#146537)
		20210120@Cherry: Integrate Saba Jackpot (#148293)
		20210506@Cherry: Integrate VGaming Jackpot (#154250)
		20230801@Cherry: Integrate Virtual Sports 3 (#189202)
*/
 
BEGIN
SET NOCOUNT ON 
	
					  
	--------Get Sport Bettype Matrix------
	 -- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	CREATE TABLE #SportBettype (ProductId INT, TypeId INT, TypeName NVARCHAR(1000), IsTest BIT DEFAULT(0), GameType TINYINT) --GameType: SportType=1, Bettype=2, League=3
	CREATE TABLE #tmpBettype (Bettype INT)
 
	-- Get Exclude Bettype
	INSERT INTO #tmpBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 6
		AND Bettype NOT IN (SELECT Bettype
							FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
							WHERE BettypeGroupID = 16)
							
	CREATE TABLE #tmpHouseProduct (ProductID INT)
	INSERT INTO #tmpHouseProduct (ProductID)
	SELECT DISTINCT ProductID 
	FROM DBWH.bodb_Account.dbo.Product_Bettype WITH (NOLOCK)
	WHERE EventType = 255
	
	CREATE TABLE #tmpProduct (ProductID INT)
	INSERT INTO #tmpProduct (ProductID)
	SELECT DISTINCT ProductID 
	FROM DBWH.bodb_Account.dbo.NonSportSetting WITH (NOLOCK)
	WHERE ProductID NOT IN (5, 27, 23, 31, 77) --Virtual Sports, Virtual Sports 2, NG2, Exchange, Virtual Sports 3 
		AND ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct) -- Saba.club, VGaming	
	
    -- Get Bettype
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName, GameType)
	SELECT	s.ProductID, s.Bettype as TypeId, b.typenamee AS TypeName, 2 AS GameType
	FROM	dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN dbo.Bettype b WITH (NOLOCK) ON s.Bettype = b.TypeId 
		LEFT JOIN #tmpBettype t ON s.Bettype = t.Bettype 
	WHERE  (s.CasinoType IN (1,2) 
			OR s.ProductID IN (SELECT ProductID FROM #tmpProduct)
			)  	 
		   AND t.Bettype IS NULL
		   
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName, GameType)
	SELECT	s.ProductID ProductID, s.Bettype as TypeId, b.typenamee AS TypeName, s.SportType AS GameType
	FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
		INNER JOIN dbo.Bettype b WITH (NOLOCK) ON s.Bettype = b.TypeId 
		LEFT JOIN #tmpBettype t ON s.Bettype = t.Bettype 
	WHERE  s.ProductID IN (SELECT ProductID FROM #tmpHouseProduct)
		   AND (IsTest = 0 OR s.IsTest = @isTest)
		   AND t.Bettype IS NULL
		   	
	--- ProductID = 3 - Number Game get LeagueId
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName, IsTest, GameType)
	SELECT  3 as ProductId,
			leagueid as TypeId ,
			leaguename as TypeName,
			IsTest,
			3 AS GameType
	FROM	dbo.league l WITH (NOLOCK)
	WHERE	EXISTS (SELECT TOP 1 1 FROM dbo.SportBettypeMatrix s (NOLOCK) WHERE l.sporttype = s.SportType AND s.ProductID = 3)
	
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName, IsTest, GameType)
	VALUES (3, 168, 'Happy 5 Linked Games', 0, 3)
		 
	--- ProductID = 5, 27, 23, 42 - Virtual Sports, Virtual Sports 2, Virtual Sports 3, NG2, Saba.club get Sporttype
	INSERT INTO #SportBettype (ProductId, TypeId, TypeName, GameType)
	SELECT DISTINCT sb.ProductID, sb.SportType, s.SportName, 1 AS GameType
	FROM dbo.SportBettypeMatrix sb WITH (NOLOCK)
		INNER JOIN dbo.Sports s WITH (NOLOCK) ON sb.SportType = s.SportType 
	WHERE (sb.ProductID IN (5, 27, 23, 77) OR sb.ProductID IN (SELECT ProductID FROM #tmpHouseProduct))
		AND (sb.IsTest = 0 OR sb.IsTest = @isTest)	
			
	SELECT	* 
	FROM	#SportBettype
	ORDER BY ProductId, TypeName
	
	DROP TABLE #SportBettype
	DROP TABLE #tmpBettype
	DROP TABLE #tmpProduct
	DROP TABLE #tmpHouseProduct

END

 
