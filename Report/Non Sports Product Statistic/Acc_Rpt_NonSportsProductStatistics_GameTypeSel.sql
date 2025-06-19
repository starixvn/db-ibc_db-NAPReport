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
		20231010@Cherry: Integrate Saba Promotion (#194567) 
		20240116@Cherry: Integrate Virtual Sports 4 (#198623)
*/
 
BEGIN
SET NOCOUNT ON 
	
					  
	--------Get Sport Bettype Matrix------
	 -- Check SP Version	 
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
 
	CREATE TABLE #SportBettype 
		(ProductId INT, 
		TypeId INT, 
		TypeName NVARCHAR(1000), 
		IsTest BIT DEFAULT(0), 
		GameType TINYINT, --GameType: SportType=1, Bettype=2, League=3
		IsPrize BIT DEFAULT(0)
		) 
	CREATE TABLE #tmpBettype (Bettype INT)
	CREATE TABLE #tmpPrizeBettype (Bettype INT)
	CREATE TABLE #tmpVirtualSport (ProductID INT)

	DECLARE @VirtualSportGroupStr VARCHAR(500)
    SELECT  @VirtualSportGroupStr = VValue
	FROM DBWH.bodb_account.dbo.SystemSettings WITH(NOLOCK)
	WHERE VID = 31		

    INSERT INTO #tmpVirtualSport (ProductID)
    SELECT val ProductID
    FROM bodb02.dbo.strSplit(@VirtualSportGroupStr, ',')
	WHERE val <> 49
 
	INSERT INTO #tmpPrizeBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 16

	-- Get Exclude Bettype
	INSERT INTO #tmpBettype (Bettype)
	SELECT Bettype
	FROM DBWH.bodb_Account.dbo.BettypeGroup WITH (NOLOCK)
	WHERE BettypeGroupID = 6
		AND Bettype NOT IN (SELECT Bettype
							FROM #tmpPrizeBettype)

	INSERT INTO #tmpBettype (Bettype) VALUES (3007) -- SA Gaming Tips
							
	CREATE TABLE #tmpHouseProduct (ProductID INT, Bettype INT)
	INSERT INTO #tmpHouseProduct (ProductID, Bettype)
	SELECT DISTINCT ProductID, Bettype 
	FROM DBWH.bodb_Account.dbo.Product_Bettype WITH (NOLOCK)
	WHERE EventType = 255
	
	CREATE TABLE #tmpProductBettype (ProductID INT, Bettype INT)
	INSERT INTO #tmpProductBettype (ProductID, Bettype)
	SELECT DISTINCT ProductID, Bettype
	FROM DBWH.bodb_Account.dbo.NonSportSetting WITH (NOLOCK)
	WHERE ProductID NOT IN (23, 31) --Virtual Sports, Virtual Sports 2, NG2, Exchange, Virtual Sports 3 
		AND ProductID NOT IN (SELECT ProductID FROM #tmpHouseProduct) -- Saba.club, VGaming	
		AND ProductID NOT IN (SELECT ProductID FROM #tmpVirtualSport)
	
    -- Get Bettype
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName, GameType, IsPrize)
	SELECT	DISTINCT s.ProductID, s.Bettype as TypeId, b.typenamee AS TypeName, 2 AS GameType,
		CASE WHEN bt.Bettype IS NOT NULL THEN 1 ELSE 0 END
	FROM	dbo.f_SportBettypeMatrix_Sel(0, 0, 0, 2, '', '', @isTest) s
		INNER JOIN #tmpProductBettype p ON s.ProductID = p.ProductID AND s.BetType = p.Bettype
		INNER JOIN dbo.Bettype b WITH (NOLOCK) ON s.Bettype = b.TypeId 
		LEFT JOIN #tmpBettype t ON s.Bettype = t.Bettype 
		LEFT JOIN #tmpPrizeBettype bt ON s.Bettype = bt.Bettype 
	WHERE t.Bettype IS NULL
		AND b.typenamee NOT LIKE 'Upcoming%' 
		AND b.typenamee NOT LIKE 'Up coming%'
		AND b.typenamee NOT LIKE 'Upcomming%' 
		   
	INSERT INTO #SportBettype (ProductID, TypeId, TypeName, GameType)
	SELECT	DISTINCT s.ProductID ProductID, s.Bettype as TypeId, b.typenamee AS TypeName, s.SportType AS GameType
	FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
		INNER JOIN #tmpHouseProduct p ON s.ProductID = p.ProductID AND s.BetType = p.Bettype
		INNER JOIN dbo.Bettype b WITH (NOLOCK) ON s.Bettype = b.TypeId 
		LEFT JOIN #tmpBettype t ON s.Bettype = t.Bettype 
	WHERE  t.Bettype IS NULL
		   AND (IsTest = 0 OR s.IsTest = @isTest)
		   AND b.typenamee NOT LIKE 'Upcoming%' 
		   AND b.typenamee NOT LIKE 'Up coming%'
		   AND b.typenamee NOT LIKE 'Upcomming%' 
		   	
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
	WHERE (sb.ProductID = 23 OR sb.ProductID IN (SELECT ProductID FROM #tmpHouseProduct)
			OR sb.ProductID IN (SELECT ProductID FROM #tmpVirtualSport))
		AND (sb.IsTest = 0 OR sb.IsTest = @isTest)	
			
	SELECT	* 
	FROM	#SportBettype
	ORDER BY ProductId, TypeName
	
	DROP TABLE #SportBettype
	DROP TABLE #tmpBettype
	DROP TABLE #tmpProductBettype
	DROP TABLE #tmpHouseProduct
	DROP TABLE #tmpVirtualSport

END

 
