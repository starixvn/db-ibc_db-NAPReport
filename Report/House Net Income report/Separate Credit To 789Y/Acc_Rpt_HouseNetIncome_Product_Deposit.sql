/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_Product_Deposit]
	@FromDate DATE,
	@ToDate	DATE
AS  
/*  	
	Created:	20200214@Kean  
    Task :		DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
    DB:			DB: DBEXT/bodb02 
   
    Revisions:  
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200224@Kean - Add SG product - #123734
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200422@Kean: House Net Income - Integrate Sexy Gaming product (#132792)
		- 20200422@Kean: House Net Income - Integrate Saba.Club product (#132791)
		- 20200521@Ned.Le: Re-Integrate Fishing World product for letstalk (#134533)
	
	
	EXEC [Acc_Rpt_HouseNetIncome_Product_Deposit] '20180601', '20180619'
  
*/
BEGIN
    SET NOCOUNT ON;
    -- Declare datetime variables

    DECLARE @FDate DATE, @TDate DATE;

    SELECT @FDate = @FromDate
	    , @TDate = @ToDate;

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_AGC_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_CB 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_CC_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_CO_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_EX_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_LT_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_PP_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC DBWH.bodb_dwrs.dbo.Acc_Rpt_HouseNetIncome_SP_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_VS2_Deposit 
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_AB_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_CS_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_GD_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_GD_PayToSupplier
		@FromDate = @FDate
		, @ToDate = @TDate
		, @DepositType = 1

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_KN_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_MacauGames_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_NG_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_HP5_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SB_PayToSupplier
	@FromDate  = @FromDate
	,@ToDate	= @ToDate
	,@DepositType = 1

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_VS_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SG_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_VG_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SA_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_I4D_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_TG_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SXG_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate

EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_SBC_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate
	
EXEC bodb02.dbo.Acc_Rpt_HouseNetIncome_FW_Deposit
	@FromDate  = @FromDate
	,@ToDate	= @ToDate
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_Product_Deposit] TO [bodbAdminNet]