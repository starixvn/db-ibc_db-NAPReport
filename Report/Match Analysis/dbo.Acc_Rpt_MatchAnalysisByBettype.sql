ALTER PROCEDURE dbo.[Acc_Rpt_MatchAnalysisByBettype]
	@eventdate datetime,	
	@matchid int,
	@liveindicator smallint = NULL,
	@bettypes VARCHAR(4000) = NULL,
	@statusid tinyint = 0,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME			
AS

/*	Creator: Dan
	Date: 20120228
	Task: Match Analysis By Bet type
	DB: DBACC/bodb02	
		
	History:
		- 20120405@Dan: add @liveindicator and @bettypes parameter for more filters. Support to get data from bettran_bk
		- 20120920@Sophia: support only Sportsbook
		- 20121123@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20120215@Elodie: Change linked server DB06 to DBARC
		- 20150529@Jim: add Metric Gaming and apply sport-bettype matrix
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20150922@Jim: offer MO ( #41935)		
		- 20160125@Robert: Cricket - Integrate to Accounting Reports [#50274]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	Explanation's Param:
		- @matchid: the id of match
		- @statusid: the status of tickets --> ALL/DRAW/WON/LOSE  (0/111/112/113)
*/
	SET NOCOUNT ON
	
	IF 	(@statusid NOT IN (0,111,112,113))
		RETURN
	
	DECLARE @tmp TABLE (val INT)
	INSERT INTO @tmp(val) 
	VALUES(500) -- Charged Commission

	IF (@bettypes IS NOT NULL)
		INSERT INTO @tmp(val) SELECT CONVERT(INT,val) FROM dbo.strSplit(@bettypes,',')
	
	DECLARE @SportBettype TABLE(ProductID INT,Bettype INT,EventType INT,SubProduct VARCHAR(200),OrderKey TINYINT)
	INSERT INTO @SportBettype (ProductID  , Bettype  ,EventType  ,SubProduct)
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode=5
	
	DELETE @SportBettype
	WHERE bettype IN (901,902,903,903,9,29,10)
		OR ProductID <> 1
	
	UPDATE @SportBettype
	SET OrderKey = CASE Bettype WHEN 1   THEN 1
								WHEN 301 THEN 2
								WHEN 3	 THEN 4
								WHEN 302 THEN 5
								WHEN 7   THEN 7
								WHEN 303 THEN 8
								WHEN 8   THEN 10
								WHEN 304 THEN 11
								ELSE 12
								END	
								
	IF (@eventdate>@MoveBetsDay)
	BEGIN	
		SELECT 	
				b.bettype,
				SUM(CASE WHEN b.bettype = 500 THEN 0 ELSE 1 END) betcount,
				--MEMBER
				ISNULL(SUM(ABS(stake)* b.actualrate),0) AS MemberTurnover,
				ISNULL(SUM((winlost-actual_stake + playercomm)* b.actualrate),0) AS MemberWinLost,
				-- COMPANY
				ISNULL(SUM((1-tpositiontaking)*ABS(stake)* b.actualrate),0) AS HouseTurnover,	
				ISNULL(SUM(-(winlost-actual_stake  + swinlost + awinlost + mwinlost + scomm) * b.actualrate),0)  AS HouseWinloss, --Company	
				-- SA + MA + AG
				ISNULL(SUM(tpositiontaking*ABS(stake)* b.actualrate),0) AS SMATurnover,
				ISNULL(SUM((swinlost + scomm + awinlost + mwinlost - playercomm)* b.actualrate),0) AS SMAWinLost
				
		FROM	bettrans b WITH (NOLOCK)	
				INNER JOIN @SportBettype bet ON b.bettype = bet.bettype
		WHERE			
				matchid = @matchid								
				AND statusID = CASE WHEN @statusID = 0 THEN statusID		
									ELSE @statusID 	END
				--AND status NOT IN ('VOID', 'REJECT','REFUND') 			
				AND b.statusID IN (111,112,113)
				AND (@liveindicator IS NULL or liveindicator = @liveindicator)
				AND (@bettypes IS NULL OR bet.bettype IN (SELECT val FROM @tmp))
				AND ruben = 1
				AND Currency <> 20		
		GROUP BY b.bettype,bet.OrderKey
		ORDER BY b.bettype,bet.OrderKey
	END
	ELSE IF (@eventdate>=@BalanceUpDay)
	BEGIN
		SELECT 	
				b.bettype,
				SUM(CASE WHEN b.bettype = 500 THEN 0 ELSE 1 END) betcount,
				--MEMBER
				ISNULL(SUM(ABS(stake)* b.actualrate),0) AS MemberTurnover,
				ISNULL(SUM((winlost-actual_stake + playercomm)* b.actualrate),0) AS MemberWinLost,
				-- COMPANY
				ISNULL(SUM((1-tpositiontaking)*ABS(stake)* b.actualrate),0) AS HouseTurnover,	
				ISNULL(SUM(-(winlost-actual_stake  + swinlost + awinlost + mwinlost + scomm) * b.actualrate),0)  AS HouseWinloss, --Company	
				-- SA + MA + AG
				ISNULL(SUM(tpositiontaking*ABS(stake)* b.actualrate),0) AS SMATurnover,
				ISNULL(SUM((swinlost + scomm + awinlost + mwinlost - playercomm)* b.actualrate),0) AS SMAWinLost
				
		FROM	bettrans14 b WITH (NOLOCK)		
				INNER JOIN @SportBettype bet ON b.bettype = bet.bettype
		WHERE			
				matchid = @matchid				
				AND statusID = CASE WHEN @statusID = 0 THEN statusID		
									ELSE @statusID 	END
				--AND status NOT IN ('VOID', 'REJECT','REFUND') 
				AND b.statusID IN (111,112,113)
				AND (@liveindicator IS NULL or liveindicator = @liveindicator)
				AND (@bettypes IS NULL OR bet.bettype IN (SELECT val FROM @tmp))
				AND ruben = 1
				AND Currency <> 20		
		GROUP BY b.bettype,bet.OrderKey		
		ORDER BY b.bettype,bet.OrderKey
	END
	ELSE
	BEGIN
		SELECT 	
				b.bettype,
				SUM(CASE WHEN b.bettype = 500 THEN 0 ELSE 1 END) betcount,
				--MEMBER
				ISNULL(SUM(ABS(stake)* b.actualrate),0) AS MemberTurnover,
				ISNULL(SUM((winlost-actual_stake + playercomm)* b.actualrate),0) AS MemberWinLost,
				
				-- COMPANY
				ISNULL(SUM((1-tpositiontaking)*ABS(stake)* b.actualrate),0) AS HouseTurnover,	
				ISNULL(SUM(-(winlost-actual_stake  + swinlost + awinlost + mwinlost + scomm) * b.actualrate),0)  AS HouseWinloss, --Company	
				-- SA + MA + AG
				ISNULL(SUM(tpositiontaking*ABS(stake)* b.actualrate),0) AS SMATurnover,
				ISNULL(SUM((swinlost + scomm + awinlost + mwinlost - playercomm)* b.actualrate),0) AS SMAWinLost
				
		FROM	DBARC.bodb_archive.dbo.bettrans_bk b WITH (NOLOCK)		
				INNER JOIN @SportBettype bet ON b.bettype = bet.bettype
		WHERE			
				winlostdate = @eventdate
				AND matchid = @matchid				
				--AND statusID = CASE WHEN @statusID = 0 THEN statusID	ELSE @statusID 	END
				AND status = CASE WHEN @statusID = 0 THEN status		
								WHEN @statusID = 111 THEN 'DRAW'
								WHEN @statusID = 112 THEN 'WON'
								WHEN @statusID = 113 THEN 'LOSE'
								END
				AND status IN ('DRAW', 'WON','LOSE') 
				--AND b.statusID IN (111,112,113)
				AND (@liveindicator IS NULL or liveindicator = @liveindicator)
				AND (@bettypes IS NULL OR bet.bettype IN (SELECT val FROM @tmp))
				AND ruben = 1
				AND Currency <> 20		
		GROUP BY b.bettype,bet.OrderKey	
		ORDER BY b.bettype,bet.OrderKey	
	END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MatchAnalysisByBettype] TO [bodbAdminNet]

GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MatchAnalysisByBettype] TO [vnteam]