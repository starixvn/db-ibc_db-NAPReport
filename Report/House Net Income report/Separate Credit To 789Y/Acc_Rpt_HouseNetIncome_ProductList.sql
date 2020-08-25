/*<info serverAlias="DBWH-bodb_dwrs" executers="dwrs" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_dwrs
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_HouseNetIncome_ProductList]
AS  
/*  	
	Created:	20200214@Kean  
    Task :		DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
    DB:			DBWH/bodb_dwrs  
   
    Revisions:  
		- 20200214@Kean - DHWL Letstalk - Margin report - Separate Credit into 789 and other MBC [#128572]
		- 20200317@Kean - Letstalk - Integrate Virtual Games product [#126465]
		- 20200324@Kean - Email/Letstalk Reports - Integrate SA Gaming product [#128059]
		- 20200410@Kean - Email/Letstalk Reports - Integrate BBIN product [#131364]
		- 20200409@Kean: House Net Income - Integrate Table Games product (#129447)
		- 20200423@Kean - Email/Letstalk Reports - Integrate IBCBet Live Casino product (#130690)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO ION Live Casino (#132331)
		- 20200518@Ned.Le - Email/Letstalk Reports - Integrate SBO RNG War (#132019)
		- 20200521@Ned.Le - Re-Integrate Fishing World product for letstalk (#134533)
		- 20200720@Kean - DHWL Email/Letstalk - Separate Saba Sports from real Sports (#137822)
		- 20200722@Ned.Le - Email/Letstalk Reports - Integrate Jackpot Games (#137280)
		- 20200813@Kean - DHWL Email/Letstalk - Change Product Name and Margin Report Format. (#139537)
  
*/
BEGIN
SET NOCOUNT ON;	
    -- Spooksbooks
	SELECT 'Real Soc' Product, 'Soccer' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'Saba Soc' Product, 'SabaSoccer' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'Real Bas' Product, 'Basketball' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'Saba Bas' Product, 'SabaBasketball' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'Tennis' Product, 'Tennis' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'E-Sports' Product, 'E-Sports' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'Saba Cric' Product, 'SabaCricket' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'OtherSp' Product, 'OS' ProductPrefix, 'Spooksbooks' [Group]
	UNION ALL
	SELECT 'Parlay' Product, 'Parlay' ProductPrefix, 'Spooksbooks' [Group]

	-- Live Casino
	UNION ALL
	SELECT 'AllBet' Product, 'AB' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'SexyG' Product, 'SXG' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'GoldD' Product, 'GD' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'SA Game' Product, 'SAG' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'ION LC' Product, 'ION' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'IBC LC' Product, 'IBCLC' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'BBIN LC' Product, 'BBIN' ProductPrefix, 'Live Casino' [Group]
	UNION ALL
	SELECT 'AG LC' Product, 'AGC' ProductPrefix, 'Live Casino' [Group]

	-- RNG Casino
	UNION ALL
	SELECT 'SabaC' Product, 'SBC' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT '1RNG' Product, 'CS' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT '1RNG-JP' Product, 'JP' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'CardC' Product, 'CC' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'PragP' Product, 'PP' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'PragP-JP' Product, 'PP-JP' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'TableG' Product, 'TG' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'VirtualG' Product, 'VG' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'MacauG' Product, 'VB' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'SpadeG' Product, 'SG' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'RNGWar' Product, 'RNGW' ProductPrefix, 'RNG Casino' [Group]
	UNION ALL
	SELECT 'FishW' Product, 'FW' ProductPrefix, 'RNG Casino' [Group]

	-- Lottery/Keno
	UNION ALL
	SELECT 'MKeno' Product, 'KN' ProductPrefix, 'Lottery/Keno' [Group]
	UNION ALL
	SELECT 'NumG' Product, 'NG' ProductPrefix, 'Lottery/Keno' [Group]
	UNION ALL
	SELECT 'Happy5' Product, 'H5' ProductPrefix, 'Lottery/Keno' [Group]
	UNION ALL
	SELECT 'MLotte' Product, 'LT' ProductPrefix, 'Lottery/Keno' [Group]
	UNION ALL
	SELECT 'NG2' Product,'NG2' ProductPrefix, 'Lottery/Keno' [Group]
	--UNION ALL
	--SELECT 'Indo 4D' Product, 'I4D' ProductPrefix, 'Lottery/Keno' [Group]

	-- Others
	UNION ALL
	SELECT 'VirtSpo2' Product, 'VS2' ProductPrefix, 'Others' [Group]
	UNION ALL
	SELECT 'VirtSpo' Product, 'VS' ProductPrefix, 'Others' [Group]
	UNION ALL
	SELECT 'ColosBe' Product, 'CB' ProductPrefix, 'Others' [Group]
	UNION ALL
	SELECT 'CashO' Product, 'CO' ProductPrefix, 'Others' [Group]
	UNION ALL
	SELECT 'Exchange' Product, 'EX' ProductPrefix, 'Others' [Group]
	UNION ALL
	SELECT 'SabaPro' Product, 'NPH' ProductPrefix, 'Others' [Group]
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_ProductList] TO [dwrs]
