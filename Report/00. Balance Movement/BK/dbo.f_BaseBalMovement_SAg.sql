ALTER FUNCTION [dbo].[f_BaseBalMovement_SAg]
(
	@winlostdate	DATETIME
)
RETURNS @CustBalance TABLE
(
	custid	INT PRIMARY KEY,
	Bet		MONEY,
	Pos		MONEY,
	Com		MONEY,
	Tra		MONEY,
	Bal		MONEY
)
AS
/*
	Created by: Jamie
	Date: 2009-08-21
	Task: Super Base Balance Movement 
	DB: DB06.BODB02 
	
	Revision:
		- 20101224@Johnson: Apply new arrange of bettype
*/
BEGIN
	INSERT INTO @CustBalance (	
		custid,	
		Bet,
		Pos,
		Com,
		Tra,
		Bal
	)
	SELECT	srecommend,
			BetBase,
			PosBase,
			ComBase,
			TraBase,
			BetBase + PosBase + ComBase + TraBase AS BalBase 
	FROM
	(
		SELECT 	srecommend,		
				ISNULL(SUM (CASE WHEN bettype < 19001 THEN (winlost-actual_stake)*actualrate ELSE 0 END),0) BetBase,
				ISNULL(SUM (CASE WHEN bettype < 19001 THEN (swinlost + mwinlost + awinlost)*actualrate ELSE 0 END),0) PosBase,
				ISNULL(SUM (CASE WHEN bettype < 19001 THEN	scomm*actualrate ELSE 0 END),0) ComBase,
				ISNULL(SUM (CASE WHEN bettype > 19000 THEN (winlost-actual_stake + swinlost + scomm + mwinlost + awinlost)*actualrate ELSE 0 END),0) TraBase
		FROM	bettrans WITH (NOLOCK) 
		where	winlostdate = @winlostdate 
				AND ruben = 1 
				AND status NOT IN ('VOID','REJECT','REFUND')
		GROUP BY srecommend
	) t
	RETURN
END
GO
GRANT VIEW DEFINITION ON [dbo].[f_BaseBalMovement_SAg] TO [vnteam]

