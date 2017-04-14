 ALTER PROCEDURE dbo.[Acc_Rpt_MatchAnalysisBySuper_Ag]
	@custid int,
	@eventdate datetime,	
	@matchid int,
	@liveindicator smallint = NULL,
	@bettypes VARCHAR(4000) = NULL,
	@statusid tinyint = 0,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME		
AS

/*	Creator: Sophia
	Date: 20120827
	Task: Match Analysis By Agnet drill down to Member
	DB: DBACC/bodb02	
		
	Revisions:
		- 20120920@Sophia: support only Sportsbook
		- 20121123@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20120215@Elodie: Change linked server DB06 to DBARC
		- 20150529@Jim: add Metric Gaming and apply sport-bettype matrix
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20160125@Robert: Cricket - Integrate to Accounting Reports [#50274]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)

	Explanation's Param:
		- @CustID : Agent ID
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

	
	DECLARE @SportBettype TABLE(ProductID INT,Bettype INT,EventType INT,SubProduct VARCHAR(200))
	INSERT INTO @SportBettype
	EXEC dbo.Acc_SportBettypeMatrix_Sel @mode=5
	
	DELETE @SportBettype
	WHERE bettype IN (901,902,903,904,9,29,10)
		OR ProductID <> 1

	IF (@eventdate>@MoveBetsDay)
	BEGIN	
		SELECT 	
				c.username,b.Currency, b.custid,
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
			INNER JOIN customer c WITH (NOLOCK)	ON c.custid = b.custid
			INNER JOIN @SportBettype s on b.bettype = s.bettype			
		WHERE	b.recommend = @custID		
				AND b.matchid = @matchid				
				AND b.statusID = CASE WHEN @statusID = 0 THEN statusID		
									ELSE @statusID 	END
				
				AND b.statusID IN (111,112,113)
				AND (@liveindicator IS NULL or liveindicator = @liveindicator)
				AND (@bettypes IS NULL OR b.bettype IN (SELECT val FROM @tmp))
				AND b.ruben = 1
				AND b.Currency <> 20		
		GROUP BY b.custid, c.username, b.Currency
		ORDER BY c.username
	END
	ELSE IF (@eventdate>=@BalanceUpDay)
	BEGIN
		SELECT 	
				c.username, b.Currency, b.custid,
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
			INNER JOIN customer c WITH (NOLOCK) ON c.custid = b.custid
			INNER JOIN @SportBettype s on b.bettype = s.bettype			
		WHERE	b.recommend = @custID			
				AND matchid = @matchid
				AND statusID = CASE WHEN @statusID = 0 THEN statusID		
									ELSE @statusID 	END
				
				AND b.statusID IN (111,112,113)
				AND (@liveindicator IS NULL or liveindicator = @liveindicator)
				AND (@bettypes IS NULL OR b.bettype IN (SELECT val FROM @tmp))
				AND ruben = 1
				AND b.Currency <> 20		
		GROUP BY b.custid, c.username, b.Currency
		ORDER BY c.username
	END
	ELSE
	BEGIN
		SELECT 	
				c.username, b.Currency, b.custid,
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
			INNER JOIN customer c WITH (NOLOCK) ON c.custid = b.custid
			INNER JOIN @SportBettype s on b.bettype = s.bettype			
		WHERE	b.recommend = @custID		
				AND winlostdate = @eventdate	
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
				AND (@bettypes IS NULL OR b.bettype IN (SELECT val FROM @tmp))
				AND ruben = 1
				AND b.Currency <> 20		
		GROUP BY b.custid, c.username, b.Currency
		ORDER BY c.username	
	END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MatchAnalysisBySuper_Ag] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MatchAnalysisBySuper_Ag] TO [vnteam]