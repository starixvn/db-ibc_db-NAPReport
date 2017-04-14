USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_ParlayWon]
	@WinlostDate	DATETIME,
	@Bettype		INT = 9,
    @IsSoccer		BIT	= 0,    
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME
AS  

/*
Created: 20120821@Sophia
Task : List of users won Parlay of others sport
	   Note: CompanyWinlost no need to get commission

DB: DBAGE.bodb02
Original: Acc_Rpt_MixParlayWon

Revisions:
		- 20160826@Percy: Enhance System/Mix Parlay [RedmineID: #63022]
Param's Explanation:
	• @WinlostDate:
		- Date of Win lost
	• @IsSoccer
		- 1: Get WON mix parlay tickets of soccer
		- 0: Get WON mix parlay tickets of other sports
	• @Bettype = 9 Mix Parlay
			   = 29 Combination mix parlay
*/

SET NOCOUNT ON

DECLARE @_matchid INT

IF @bettype = 9
	SELECT @_matchid = 9
ELSE IF @bettype = 29 
	SELECT @_matchid = 29

IF @IsSoccer = 1
BEGIN
	IF @WinlostDate > @MoveBetsDay
	BEGIN
		SELECT b.transid, b.username, b.currencyname Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winlost,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winlost_RM,
			b.stake*(1-b.tpositiontaking)*b.actualrate AS CompanyStake_RM, b.actual_stake*(1-b.tpositiontaking)*b.actualrate AS CompanyActual_stake_RM, (b.winlost-b.actual_stake)*(1-b.tpositiontaking)*b.actualrate AS CompanyWinlost_RM,
			CASE WHEN RAND() + 1 > 0 AND b.bettype = 9 THEN CONVERT(INT, RIGHT(b.betcheck, LEN(b.betcheck) - 1)) ELSE CONVERT(INT, b.hdp2) END selection, b.odds, b.modds
		FROM bettrans b WITH (nolock)
		WHERE
			b.bettype IN (9, 29)
			AND b.matchid IN (9, 29)
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
			AND b.liveawayscore IN (1, 3)
			AND (@bettype = CASE WHEN b.bettype = 29 AND b.betteam <> N'1' THEN 29 ELSE 9 END)
		ORDER BY b.transid
	END
	ELSE
	BEGIN
		SELECT b.transid, b.username, b.currencyname AS Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winlost,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winlost_RM,
			b.stake*(1-b.tpositiontaking)*b.actualrate AS CompanyStake_RM, b.actual_stake*(1-b.tpositiontaking)*b.actualrate AS CompanyActual_stake_RM, (b.winlost-b.actual_stake)*(1-b.tpositiontaking)*b.actualrate AS CompanyWinlost_RM,
			CASE WHEN RAND() + 1 > 0 AND b.bettype = 9 THEN CONVERT(INT, RIGHT(b.betcheck, LEN(b.betcheck) - 1)) ELSE CONVERT(INT, b.hdp2) END selection, b.odds , b.modds
		FROM bettrans14 b WITH (nolock)
		WHERE
			b.bettype IN (9, 29)
			AND b.matchid IN (9, 29)
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
			AND b.liveawayscore IN (1, 3)
			AND (@bettype = CASE WHEN b.bettype = 29 AND b.betteam <> N'1' THEN 29 ELSE 9 END)
		ORDER BY b.transid
	END
END
ELSE
BEGIN
	IF @WinlostDate > @MoveBetsDay
	BEGIN
		SELECT b.transid, b.username, b.currencyname Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winlost,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winlost_RM,
			b.stake*(1-b.tpositiontaking)*b.actualrate AS CompanyStake_RM, b.actual_stake*(1-b.tpositiontaking)*b.actualrate AS CompanyActual_stake_RM, (b.winlost-b.actual_stake)*(1-b.tpositiontaking)*b.actualrate AS CompanyWinlost_RM,
			CASE WHEN RAND() + 1 > 0 AND b.bettype = 9 THEN CONVERT(INT, RIGHT(b.betcheck, LEN(b.betcheck) - 1)) ELSE CONVERT(INT, b.hdp2) END selection, b.odds, b.modds
		FROM bettrans b WITH (nolock)
		WHERE
			b.bettype IN (9, 29)
			AND b.matchid IN (9, 29)
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
			AND b.liveawayscore = 2
			AND (@bettype = CASE WHEN b.bettype = 29 AND b.betteam <> N'1' THEN 29 ELSE 9 END)
		ORDER BY b.transid
	END
	ELSE
	BEGIN
		SELECT b.transid, b.username, b.currencyname Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winlost,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winlost_RM,
			b.stake*(1-b.tpositiontaking)*b.actualrate AS CompanyStake_RM, b.actual_stake*(1-b.tpositiontaking)*b.actualrate AS CompanyActual_stake_RM, (b.winlost-b.actual_stake)*(1-b.tpositiontaking)*b.actualrate AS CompanyWinlost_RM,
			CASE WHEN RAND() + 1 > 0 AND b.bettype = 9 THEN CONVERT(INT, RIGHT(b.betcheck, LEN(b.betcheck) - 1)) ELSE CONVERT(INT, b.hdp2) END selection, b.odds , b.modds
		FROM bettrans14 b WITH (nolock)
		WHERE
			b.bettype IN (9, 29)
			AND b.matchid IN (9, 29)
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
			AND b.liveawayscore = 2
			AND (@bettype = CASE WHEN b.bettype = 29 AND b.betteam <> N'1' THEN 29 ELSE 9 END)
		ORDER BY b.transid
	END
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_ParlayWon] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_ParlayWon] TO [vnteam]