ALTER PROCEDURE [dbo].[Task_rptBalanceMovementSum]
	@winlostdate	DATETIME
AS
/*	Created by: Jamie
	Date: 2009-08-22
	Task: Sum Historical Balance
	DB: DB06.bodb_Report 

	Param's Explanation:
		@winlostdate = today - 7 [old day/ Day 0]  
*/
BEGIN
	SET NOCOUNT ON
	IF EXISTS (SELECT 1 FROM dbo.rptCustBalance WITH (NOLOCK) WHERE winlostdate = @winlostdate -1)
	BEGIN
		INSERT INTO dbo.rptCustBalance (
			winlostdate, custID, roleID, [Status],
			PosOriginal, ComOriginal, BetOriginal, TraOriginal, BalOriginal,
			PosBase, ComBase, BetBase, TraBase, BalBase
		)
		SELECT	@winlostdate, custid, 4, 1, 
				0, 0, 0, 0, SUM(BalOriginal),
				0, 0, 0, 0, SUM(BalBase)
		FROM	dbo.rptCustBalance WITH (NOLOCK)
		WHERE	winlostdate BETWEEN @winlostdate - 1 AND @winlostdate
		GROUP BY custid
		HAVING	SUM(BalOriginal) <>0 OR SUM(BalBase) <>0 
		
		IF @@ERROR = 0 
		BEGIN 
			DELETE FROM dbo.rptCustBalance WHERE winlostdate < @winlostdate OR (winlostdate = @winlostdate AND status = 0)
		END 
	END 
END 
GO
GRANT EXECUTE ON [dbo].[Task_rptBalanceMovementSum] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Task_rptBalanceMovementSum] TO [vnteam]
