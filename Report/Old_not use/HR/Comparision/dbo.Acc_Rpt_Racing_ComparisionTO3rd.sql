ALTER PROCEDURE [dbo].[Acc_Rpt_Racing_ComparisionTO3rd]
@winlostdate	DATETIME,
@reportType		INT=1
AS
/*	Created by: Jamie
	Date: 2010-06-08
	Task: 3rd Turnover and Dividend Comparision
	DB: DBACC/BODB_ACC

	Revisions:
		- 20111130@Jamie: Filtering by merchant_id 
		- 20130224@Lukas: - 20130224@Lukas: move sp to new database bodb_ACC
	Param Explanation:
		@reportType:1-UK Horse Racing ; 3-UK Greyhound
						

*/
BEGIN
	SET NOCOUNT ON

	DECLARE	@merchant_id INT
	
	IF @reportType = 1 SELECT @merchant_id = 501001
	ELSE IF  @reportType = 3 SELECT @merchant_id = 501002
		 ELSE SELECT @merchant_id =0  	

	SELECT	currency currencyName, SUM(cost) TO3rd, SUM(payout) DividendWon3rd 
	FROM	dbo.Acc_HorseTransaction3rd WITH (NOLOCK)
	WHERE	winlostdate = @winlostdate
			AND merchant_id = @merchant_id  
			AND status = 'SUCCESS' 
			AND has_refund = 'N' 
			AND cancelled ='N'
	GROUP BY currency 
END

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_Racing_ComparisionTO3rd] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Racing_ComparisionTO3rd] TO [vnteam] 