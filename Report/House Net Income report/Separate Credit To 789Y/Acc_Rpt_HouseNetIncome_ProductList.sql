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
  
*/
BEGIN
SET NOCOUNT ON;	

	SELECT 'Soccer' Product, 'Soccer' ProductPrefix
	UNION ALL
	SELECT 'Basketball' Product, 'Basketball' ProductPrefix
	UNION ALL
	SELECT 'Tennis' Product, 'Tennis' ProductPrefix
	UNION ALL
	SELECT 'E-Sports' Product, 'E-Sports' ProductPrefix
	UNION ALL
	SELECT 'OS' Product, 'OS' ProductPrefix
	UNION ALL
	SELECT 'Parlay' Product, 'Parlay' ProductPrefix
	UNION ALL
	SELECT 'VS' Product, 'VS' ProductPrefix
	UNION ALL
	SELECT 'NG' Product, 'NG' ProductPrefix
	UNION ALL
	SELECT '1RNG' Product, 'CS' ProductPrefix
	UNION ALL
	SELECT '1RNG-JP' Product, 'JP' ProductPrefix
	UNION ALL
	SELECT 'RNGKeno' Product, 'KN' ProductPrefix
	UNION ALL
	SELECT 'AG' Product, 'AGC' ProductPrefix
	UNION ALL
	SELECT 'NG2' Product,'NG2' ProductPrefix
	UNION ALL
	SELECT 'CB' Product, 'CB' ProductPrefix
	UNION ALL
	SELECT 'MacauG' Product, 'VB' ProductPrefix
	UNION ALL
	SELECT 'GD' Product, 'GD' ProductPrefix
	UNION ALL
	SELECT 'AB' Product, 'AB' ProductPrefix
	UNION ALL
	SELECT 'CO' Product, 'CO' ProductPrefix
	UNION ALL
	SELECT 'VS2' Product, 'VS2' ProductPrefix
	UNION ALL
	SELECT 'LT' Product, 'LT' ProductPrefix
	UNION ALL
	SELECT 'EX' Product, 'EX' ProductPrefix
	UNION ALL
	SELECT 'PP' Product, 'PP' ProductPrefix
	UNION ALL
	SELECT 'H5' Product, 'H5' ProductPrefix
	UNION ALL
	SELECT 'CC' Product, 'CC' ProductPrefix
	UNION ALL
	SELECT 'SP' Product, 'NPH' ProductPrefix
	UNION ALL
	SELECT 'SG' Product, 'SG' ProductPrefix
	UNION ALL
	SELECT 'VG' Product, 'VG' ProductPrefix
	UNION ALL
	SELECT 'SAG' Product, 'SAG' ProductPrefix
	--UNION ALL
	--SELECT 'I4D' Product, 'I4D' ProductPrefix
	UNION ALL
	SELECT 'SBC' Product, 'SBC' ProductPrefix
	UNION ALL
	SELECT 'SXG' Product, 'SXG' ProductPrefix
	UNION ALL
	SELECT 'BBIN' Product, 'BBIN' ProductPrefix
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HouseNetIncome_ProductList] TO [dwrs]
