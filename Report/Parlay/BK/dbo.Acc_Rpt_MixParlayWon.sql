USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_Rpt_MixParlayWon]    Script Date: 02/22/2011 23:59:54 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_MixParlayWon]
	@WinlostDate	DATETIME,
	@Bettype		INT = 9,
    @IsSoccer		BIT	= 1,    
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME,
    @ErrCode		INT = 0 OUTPUT ,
    @ErrMsg			VARCHAR(200)  = '' OUTPUT
AS  

/*
Created: Steven@20110215
Task : List of users won Mix Parlay of others sport

DB: DB053.bodb02
Original:

Revisions:
	20110216@Lukas: Add @MoveBetsDay, @BalanceUpDay, @IsSoccer param
	20110223@Daniel: Add sorting by transid
	20110805@Johnson:- Add new bettype combination mix parlay
					 - Get more columns actual_stake, modds to display stake,odds for combination mix parlay 
	
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
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winloss,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winloss_RM,
			COUNT(1) selection, b.odds, b.modds
		FROM bettrans b WITH (nolock)
			INNER join bettransm bm WITH (nolock) ON b.refno = bm.refno
			INNER JOIN match m WITH(NOLOCK) ON bm.matchid = m.matchid
		WHERE b.bettype = @bettype 
			AND b.matchid = @_matchid
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
		GROUP BY
			b.transid, b.username, b.currencyname, b.actualrate,
			b.stake, b.winlost, b.actual_stake, b.odds, b.modds , b.refno, b.tpositiontaking
		HAVING MIN(m.sporttype) = 1
		ORDER BY b.transid
	END
	ELSE
	BEGIN
		SELECT b.transid, b.username, b.currencyname AS Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winloss,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winloss_RM,
			COUNT(1) selection, b.odds , b.modds
		FROM bettrans14 b WITH (nolock)
			INNER join bettransm14 bm WITH (nolock) ON b.refno = bm.refno
			INNER JOIN match14 m WITH(NOLOCK) ON bm.matchid = m.matchid
		WHERE b.bettype = @bettype 
			AND b.matchid = @_matchid 
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
		GROUP BY
			b.transid, b.username, b.currencyname, b.actualrate,
			b.stake, b.winlost, b.actual_stake, b.odds, b.modds , b.refno, b.tpositiontaking
		HAVING MIN(m.sporttype) = 1
		ORDER BY b.transid
	END
END
ELSE
BEGIN
	IF @WinlostDate > @MoveBetsDay
	BEGIN
		SELECT b.transid, b.username, b.currencyname Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winloss,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winloss_RM,
			COUNT(1) selection, b.odds, b.modds
		FROM bettrans b WITH (nolock)
			INNER join bettransm bm WITH (nolock) ON b.refno = bm.refno
			INNER JOIN match m WITH(NOLOCK) ON bm.matchid = m.matchid
		WHERE b.bettype = @bettype
			AND b.matchid = @_matchid
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
		GROUP BY
			b.transid, b.username, b.currencyname, b.actualrate,
			b.stake, b.winlost, b.actual_stake, b.odds , b.modds, b.refno, b.tpositiontaking
		HAVING MIN(m.sporttype) <> 1
		ORDER BY b.transid
	END
	ELSE
	BEGIN
		SELECT b.transid, b.username, b.currencyname Currency, b.actualrate AS exchange,
			b.stake, b.actual_stake, b.winlost-b.actual_stake AS Winloss,
			b.stake*b.actualrate AS stake_RM, b.actual_stake*b.actualrate AS actual_stake_RM, (b.winlost-b.actual_stake)*b.actualrate AS Winloss_RM,
			COUNT(1) selection, b.odds , b.modds
		FROM bettrans14 b WITH (nolock)
			INNER join bettransm14 bm WITH (nolock) ON b.refno = bm.refno
			INNER JOIN match14 m WITH(NOLOCK) ON bm.matchid = m.matchid
		WHERE b.bettype = @bettype 
			AND b.matchid = @_matchid 
			AND b.statusID = 112 -- WON
			AND b.Currency <> 20
			AND b.winlostdate = @WinlostDate
		GROUP BY
			b.transid, b.username, b.currencyname, b.actualrate,
			b.stake, b.winlost, b.actual_stake, b.odds , b.modds, b.refno, b.tpositiontaking
		HAVING MIN(m.sporttype) <> 1
		ORDER BY b.transid
	END
END



GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_MixParlayWon] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_MixParlayWon] TO [vnteam] 