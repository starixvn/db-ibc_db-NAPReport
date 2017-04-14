
ALTER PROCEDURE [dbo].[Task_rptBalanceMovementIns]
	@winlostdate	DATETIME 
AS
/*	Created by: Jamie
	Date: 2009-08-21
	Task: Job for Balance Movement 
	DB: DB06.BODB02 	

	Revision: 
		- 20110516@Lukas: re-arrange bettype
*/
BEGIN
	SET NOCOUNT ON
	IF EXISTS (SELECT 1 FROM bodb_Report.dbo.rptCustBalance WITH (NOLOCK) WHERE winlostdate = @winlostdate)
	BEGIN
		DELETE FROM bodb_Report.dbo.rptCustBalance WHERE winlostdate = @winlostdate 
	END

	INSERT INTO bodb_Report.dbo.rptCustBalance(
		winlostdate, 
		CustID, 
		RoleID,
		ComOriginal, 
		PosOriginal, 
		BetOriginal, 
		TraOriginal, 
		BalOriginal,
		ComBase, 
		PosBase, 
		BetBase, 
		TraBase, 
		BalBase
	)
	SELECT	@winlostdate, 
			srecommend, 
			4, 
			ISNULL(ComOriginal,0), 
			ISNULL(PosOriginal,0), 
			ISNULL(BetOriginal,0), 
			ISNULL(TraOriginal,0), 
			ISNULL(ComOriginal,0) + ISNULL(PosOriginal,0)+ ISNULL(BetOriginal,0) + ISNULL(TraOriginal,0),
			ISNULL(ComBase,0), 
			ISNULL(PosBase,0), 
			ISNULL(BetBase,0), 
			ISNULL(TraBase,0), 
			ISNULL(ComBase,0) + ISNULL(PosBase,0) + ISNULL(BetBase,0) + ISNULL(TraBase,0)
	FROM (
			SELECT 	srecommend,		
					--Original 
					SUM (CASE WHEN bettype < 19001 THEN winlost-actual_stake ELSE 0 END) BetOriginal,
					SUM (CASE WHEN bettype < 19001 THEN swinlost + mwinlost + awinlost ELSE 0 END) PosOriginal,
					SUM (CASE WHEN bettype < 19001 THEN scomm ELSE 0 END) ComOriginal,
					SUM (CASE WHEN bettype > 19000 THEN swinlost + scomm + mwinlost + awinlost + winlost-actual_stake ELSE 0 END) TraOriginal,
				
					--Base 	
					SUM ((CASE WHEN bettype < 19001 THEN winlost-actual_stake ELSE 0 END)* actualrate) BetBase,
					SUM ((CASE WHEN bettype < 19001 THEN swinlost + mwinlost + awinlost ELSE 0 END)* actualrate) PosBase,
					SUM ((CASE WHEN bettype < 19001 THEN scomm ELSE 0 END)* actualrate) ComBase,
					SUM ((CASE WHEN bettype > 19000 THEN swinlost + scomm + mwinlost + awinlost + winlost-actual_stake ELSE 0 END)* actualrate) TraBase

			FROM	bettrans WITH (NOLOCK) 
			where	winlostdate = @winlostdate 
					AND ruben = 1 
					AND status NOT IN ('VOID','REJECT','REFUND')
			GROUP BY srecommend
	) t 
END 
GO
GRANT EXECUTE ON [dbo].[Task_rptBalanceMovementIns] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Task_rptBalanceMovementIns] TO [vnteam]



