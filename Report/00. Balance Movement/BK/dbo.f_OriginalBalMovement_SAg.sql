ALTER FUNCTION [dbo].[f_OriginalBalMovement_SAg]
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
	Date: 2009-08-19
	Task: Super Original Balance Movement 
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
			BetOriginal,
			PosOriginal,
			ComOriginal,
			TraOriginal,
			BetOriginal + PosOriginal + ComOriginal + TraOriginal AS BalOriginal 
	FROM
	(
		SELECT 	srecommend,		
				ISNULL(SUM (CASE WHEN bettype < 19001 THEN winlost-actual_stake ELSE 0 END),0) BetOriginal,
				ISNULL(SUM (CASE WHEN bettype < 19001 THEN swinlost + mwinlost + awinlost ELSE 0 END),0) PosOriginal,
				ISNULL(SUM (CASE WHEN bettype < 19001 THEN	scomm ELSE 0 END),0) ComOriginal,
				ISNULL(SUM (CASE WHEN bettype > 19000 THEN winlost-actual_stake + swinlost + scomm + mwinlost + awinlost ELSE 0 END),0) TraOriginal
		FROM	bettrans WITH (NOLOCK) 
		where	winlostdate = @winlostdate 
				AND ruben = 1 
				AND status NOT IN ('VOID','REJECT','REFUND')
		GROUP BY srecommend
	) t
	RETURN
END
GO
GRANT VIEW DEFINITION ON [dbo].[f_OriginalBalMovement_SAg] TO [vnteam]
GO


