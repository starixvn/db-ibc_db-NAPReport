ALTER PROCEDURE [dbo].[Acc_Rpt_Racing_Transaction3rdIns]
	@merchant_id INT = NULL,
	@merchant_name VARCHAR(50) = NULL,
	@cre_timestamp DATETIME = NULL,
	@merchant_reference BIGINT = NULL,
	@bet_type VARCHAR(10) = NULL,
	@meeting_name VARCHAR(50) = NULL,
	@currency VARCHAR(10) = NULL,
	@provider VARCHAR(10) = NULL,
	@transaction_id BIGINT = NULL,
	@pool_oid INT = NULL,
	@leg_races VARCHAR(10)= NULL,
	@formatted_selections VARCHAR(10) = NULL,
	@bet_options VARCHAR(5) = NULL,
	@tsn VARCHAR(50) = NULL,
	@stake MONEY = NULL,
	@cost MONEY = NULL,
	@payout MONEY = NULL,
	@other_currency VARCHAR(10) = NULL,
	@other_cost MONEY = NULL,
	@otherpayout MONEY = NULL,
	@cancelamount MONEY = NULL,
	@reconciled VARCHAR(5) = NULL,
	@cancelled VARCHAR(5) = NULL,
	@has_refund VARCHAR(5) = NULL,
	@has_payout VARCHAR(5) = NULL,
	@client_cashed VARCHAR(5) = NULL,
	@status VARCHAR(10) = NULL,
	@rate FLOAT = NULL
AS

/*
    Created by: @Jamie
    Date: 20111130
    Task: Insert transactions's I-neda
    DB: DBACC/BODB_ACC
	Original: Acc_Rpt_HorseTransaction3rdIns
   
    Revisions:
       - 20130224@Lukas: move SP to new database bodb_ACC
 */
SET NOCOUNT ON
DECLARE @winlostdate DATETIME
SELECT @winlostdate = CONVERT(VARCHAR(10), @cre_timestamp, 120)

INSERT INTO dbo.Acc_HorseTransaction3rd
           (merchant_id
           ,merchant_name
           ,cre_timestamp
           ,winlostdate
           ,merchant_reference
           ,bet_type
           ,meeting_name
           ,currency
           ,provider
           ,transaction_id
           ,pool_oid
           ,leg_races
           ,formatted_selections
           ,bet_options
           ,tsn
           ,stake
           ,cost
           ,payout
           ,other_currency
           ,other_cost
           ,otherpayout
           ,cancelamount
           ,reconciled
           ,cancelled
           ,has_refund
           ,has_payout
           ,client_cashed
           ,status
           ,rate)
     VALUES
            (@merchant_id
           ,@merchant_name
           ,@cre_timestamp
           ,@winlostdate
           ,@merchant_reference
           ,@bet_type
           ,@meeting_name
           ,@currency
           ,@provider
           ,@transaction_id
           ,@pool_oid
           ,@leg_races
           ,@formatted_selections
           ,@bet_options
           ,@tsn
           ,@stake
           ,@cost
           ,@payout
           ,@other_currency
           ,@other_cost
           ,@otherpayout
           ,@cancelamount
           ,@reconciled
           ,@cancelled
           ,@has_refund
           ,@has_payout
           ,@client_cashed
           ,@status
           ,@rate)




GO

GRANT EXECUTE ON [dbo].[Acc_Rpt_Racing_Transaction3rdIns] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_Racing_Transaction3rdIns] TO [vnteam]
 