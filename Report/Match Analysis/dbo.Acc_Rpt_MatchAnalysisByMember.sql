ALTER PROCEDURE dbo.[Acc_Rpt_MatchAnalysisByMember]
	@eventdate datetime,
	@matchid int,
	@liveindicator smallint = NULL,
	@bettypes VARCHAR(4000) = NULL,
	@statusid tinyint = 112	,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME		
AS

/*	Creator: Dan
	Date: 20120228
	Task: Match Analysis By Member (get top 100 winning member of a match)
	DB: DBACC/bodb02	
		
	History:
		- 20120406@Dan: add @liveindicator and @bettypes parameter for more filters. Support to get data from bettran_bk
		- 20120823@Dan: fix bug when getting from archive DB
		- 20120920@Sophia: support only Sportsbook
		- 20121123@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20120215@Elodie: Change linked server DB06 to DBARC
		- 20150529@Jim: add Metric Gaming and apply sport-bettype matrix
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20160125@Robert: Cricket - Integrate to Accounting Reports [#50274]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)

	Explanation's Param:
		- @matchid: the id of match
		- @statusid: the status of tickets --> WON/LOSE  (112/113)
*/
	SET NOCOUNT ON
	
	IF 	(@statusid NOT IN (112,113))
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
		SELECT TOP 100 * 
		FROM
		(
			SELECT 	username, 
					MAX(currency) currency,
					SUM(CASE WHEN b.bettype = 500 THEN 0 ELSE 1 END) betcount,
					-- MEMBER
					ISNULL(SUM(ABS(stake)* b.actualrate),0) AS MemberTurnover,
					ISNULL(SUM((winlost-actual_stake + playercomm)* b.actualrate),0) AS MemberWinLost,
					-- COMPANY
					ISNULL(SUM((1-tpositiontaking)*ABS(stake)* b.actualrate),0) AS HouseTurnover,	
					ISNULL(SUM(-(winlost-actual_stake  + swinlost + awinlost + mwinlost + scomm) * b.actualrate),0)  AS HouseWinloss, --Company	
					-- SA + MA + AG
					ISNULL(SUM(tpositiontaking*ABS(stake)* b.actualrate),0) AS SMATurnover,
					ISNULL(SUM((swinlost + scomm + awinlost + mwinlost - playercomm)* b.actualrate),0) AS SMAWinLost
					
			FROM	bettrans b WITH (NOLOCK)		
				INNER JOIN @SportBettype s on b.bettype = s.bettype					
			WHERE			
					matchid = @matchid					
					--AND status NOT IN ('VOID', 'REJECT','REFUND') 
					AND b.statusID IN (111,112,113)
					AND (@liveindicator IS NULL or liveindicator = @liveindicator)
					AND (@bettypes IS NULL OR b.bettype IN (SELECT val FROM @tmp))
					AND ruben = 1		
					AND Currency <> 20		
			GROUP BY username			
		) AS t
		WHERE (@statusID = 112 and MemberWinLost > 0)
			or 	(@statusID = 113 and MemberWinLost < 0)	
		ORDER BY CASE WHEN @statusID = 112 THEN 
						- MemberWinLost --  a trick to reverse order (get top winning)
					ELSE
						MemberWinLost --(get top losing)
					END
	END
	ELSE IF (@eventdate>=@BalanceUpDay)
	BEGIN
		SELECT TOP 100 * 
		FROM
		(	
			SELECT 	username, 
					MAX(currency) currency,
					SUM(CASE WHEN b.bettype = 500 THEN 0 ELSE 1 END) betcount,
					-- MEMBER
					ISNULL(SUM(ABS(stake)* b.actualrate),0) AS MemberTurnover,
					ISNULL(SUM((winlost-actual_stake + playercomm)* b.actualrate),0) AS MemberWinLost,
					-- COMPANY
					ISNULL(SUM((1-tpositiontaking)*ABS(stake)* b.actualrate),0) AS HouseTurnover,	
					ISNULL(SUM(-(winlost-actual_stake  + swinlost + awinlost + mwinlost + scomm) * b.actualrate),0)  AS HouseWinloss, --Company	
					-- SA + MA + AG
					ISNULL(SUM(tpositiontaking*ABS(stake)* b.actualrate),0) AS SMATurnover,
					ISNULL(SUM((swinlost + scomm + awinlost + mwinlost - playercomm)* b.actualrate),0) AS SMAWinLost
					
			FROM	bettrans14 b WITH (NOLOCK)	
				INNER JOIN @SportBettype s on b.bettype = s.bettype								
			WHERE			
					matchid = @matchid					
					--AND status NOT IN ('VOID', 'REJECT','REFUND') 
					AND b.statusID IN (111,112,113)
					AND (@liveindicator IS NULL or liveindicator = @liveindicator)
					AND (@bettypes IS NULL OR b.bettype IN (SELECT val FROM @tmp))
					AND ruben = 1		
					AND Currency <> 20		
			GROUP BY username
		) AS t
		WHERE (@statusID = 112 and MemberWinLost > 0)
			or 	(@statusID = 113 and MemberWinLost < 0)			
		ORDER BY CASE WHEN @statusID = 112 THEN 
						- MemberWinLost --  a trick to reverse order (get top winning)
					ELSE
						MemberWinLost --(get top losing)
					END
	END
	ELSE
	BEGIN
		SELECT TOP 100 * 
		FROM
		(
			SELECT 	username, 
					MAX(B.currency) currency,
					SUM(CASE WHEN b.bettype = 500 THEN 0 ELSE 1 END) betcount,
					-- MEMBER
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
			WHERE			
					winlostdate = @eventdate	
					AND matchid = @matchid					
					AND status IN ('DRAW', 'WON','LOSE') 
					--AND b.statusID IN (111,112,113)									
					AND (@liveindicator IS NULL or liveindicator = @liveindicator)
					AND (@bettypes IS NULL OR b.bettype IN (SELECT val FROM @tmp))
					AND ruben = 1		
					AND b.Currency <> 20		
			GROUP BY username			
		) t
		WHERE (@statusID = 112 and MemberWinLost > 0)
			or 	(@statusID = 113 and MemberWinLost < 0)			
		ORDER BY CASE WHEN @statusID = 112 THEN 
						- MemberWinLost --  a trick to reverse order (get top winning)
					ELSE
						MemberWinLost --(get top losing)
					END
	END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MatchAnalysisByMember] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MatchAnalysisByMember] TO [vnteam]