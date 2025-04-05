/*<info serverAlias="DBCUST-CustDB"></info>*/
USE CustDB
GO

DROP TABLE IF EXISTS #tmpExchangeDailyOanda

SELECT *
INTO #tmpExchangeDailyOanda
FROM CustDB.dbo.ExchangeDailyOanda WITH (NOLOCK)
WHERE ExchangeDate = '2025-04-05'

------------------2025-04-06--------------------
UPDATE e
SET Code=e1.Code,
	MYR=e1.MYR,
	USD=e1.USD,
	EUR=e1.EUR,
	CNY=e1.CNY,
	ActualRate=e1.ActualRate,
	IDR=e1.IDR,
	AUD=e1.AUD,
	CHF=e1.CHF,
	GBP=e1.GBP,
	SGD=e1.SGD,
	THB=e1.THB,
	VND=e1.VND,
	KRW=e1.KRW,
	JPY=e1.JPY,
	HKD=e1.HKD,
	TWD=e1.TWD,
	PHP=e1.PHP,
	BDT=e1.BDT,
	INR=e1.INR,
	TRY=e1.TRY,
	NPR=e1.NPR,
	MXN=e1.MXN,
	NGN=e1.NGN,
	RepUpdateTime= dbo.f_GetDateTime2(),
	BRL=e1.BRL,
	PKR=e1.PKR
FROM CustDB.dbo.ExchangeDailyOanda AS e
	INNER JOIN #tmpExchangeDailyOanda AS e1 ON e.ExchangeDate = '2025-04-06' AND e.[ExchangeId] = e1.[ExchangeId] AND e.[Code] = e1.[Code]

INSERT INTO CustDB.dbo.ExchangeDailyOanda (
	[ExchangeDate]
	,[ExchangeId]
	,[Code]
	,[MYR]
	,[USD]
	,[EUR]
	,[CNY]
	,[ActualRate]
	,[IDR]
	,[AUD]
	,[CHF]
	,[GBP]
	,[SGD]
	,[THB]
	,[VND]
	,[KRW]
	,[JPY]
	,[HKD]
	,[TWD]
	,[PHP]
	,[BDT]
	,[INR]
	,[TRY]
	,[NPR]
	,[MXN]
	,[NGN]
	,[RepUpdateTime]
	,[BRL]
	,[PKR]
)
SELECT '2025-04-06' AS [ExchangeDate]
  ,e1.[ExchangeId]
  ,e1.[Code]
  ,e1.[MYR]
  ,e1.[USD]
  ,e1.[EUR]
  ,e1.[CNY]
  ,e1.[ActualRate]
  ,e1.[IDR]
  ,e1.[AUD]
  ,e1.[CHF]
  ,e1.[GBP]
  ,e1.[SGD]
  ,e1.[THB]
  ,e1.[VND]
  ,e1.[KRW]
  ,e1.[JPY]
  ,e1.[HKD]
  ,e1.[TWD]
  ,e1.[PHP]
  ,e1.[BDT]
  ,e1.[INR]
  ,e1.[TRY]
  ,e1.[NPR]
  ,e1.[MXN]
  ,e1.[NGN]
  ,dbo.f_GetDateTime2() AS [RepUpdateTime]
  ,e1.[BRL]
  ,e1.[PKR]
FROM #tmpExchangeDailyOanda AS e1
	LEFT JOIN CustDB.dbo.ExchangeDailyOanda AS e ON e.ExchangeDate = '2025-04-06' AND e.[ExchangeId] = e1.[ExchangeId] AND e.[Code] = e1.[Code]
WHERE e.[ExchangeId] IS NULL
	
-----------------Insert 2025-04-06-----------------------------
INSERT INTO CustDB.dbo.ExchangeDailyOanda (
	[ExchangeDate]
	,[ExchangeId]
	,[Code]
	,[MYR]
	,[USD]
	,[EUR]
	,[CNY]
	,[ActualRate]
	,[IDR]
	,[AUD]
	,[CHF]
	,[GBP]
	,[SGD]
	,[THB]
	,[VND]
	,[KRW]
	,[JPY]
	,[HKD]
	,[TWD]
	,[PHP]
	,[BDT]
	,[INR]
	,[TRY]
	,[NPR]
	,[MXN]
	,[NGN]
	,[RepUpdateTime]
	,[BRL]
	,[PKR]
)
SELECT '2025-04-06' AS [ExchangeDate]
  ,[ExchangeId]
  ,[Code]
  ,[MYR]
  ,[USD]
  ,[EUR]
  ,[CNY]
  ,[ActualRate]
  ,[IDR]
  ,[AUD]
  ,[CHF]
  ,[GBP]
  ,[SGD]
  ,[THB]
  ,[VND]
  ,[KRW]
  ,[JPY]
  ,[HKD]
  ,[TWD]
  ,[PHP]
  ,[BDT]
  ,[INR]
  ,[TRY]
  ,[NPR]
  ,[MXN]
  ,[NGN]
  ,dbo.f_GetDateTime2() AS [RepUpdateTime]
  ,[BRL]
  ,[PKR]
FROM #tmpExchangeDailyOanda

-----------------Insert 2025-04-07-----------------------------
INSERT INTO CustDB.dbo.ExchangeDailyOanda (
	[ExchangeDate]
	,[ExchangeId]
	,[Code]
	,[MYR]
	,[USD]
	,[EUR]
	,[CNY]
	,[ActualRate]
	,[IDR]
	,[AUD]
	,[CHF]
	,[GBP]
	,[SGD]
	,[THB]
	,[VND]
	,[KRW]
	,[JPY]
	,[HKD]
	,[TWD]
	,[PHP]
	,[BDT]
	,[INR]
	,[TRY]
	,[NPR]
	,[MXN]
	,[NGN]
	,[RepUpdateTime]
	,[BRL]
	,[PKR]
)
SELECT '2025-04-07' AS [ExchangeDate]
  ,[ExchangeId]
  ,[Code]
  ,[MYR]
  ,[USD]
  ,[EUR]
  ,[CNY]
  ,[ActualRate]
  ,[IDR]
  ,[AUD]
  ,[CHF]
  ,[GBP]
  ,[SGD]
  ,[THB]
  ,[VND]
  ,[KRW]
  ,[JPY]
  ,[HKD]
  ,[TWD]
  ,[PHP]
  ,[BDT]
  ,[INR]
  ,[TRY]
  ,[NPR]
  ,[MXN]
  ,[NGN]
  ,dbo.f_GetDateTime2() AS [RepUpdateTime]
  ,[BRL]
  ,[PKR]
FROM #tmpExchangeDailyOanda
  
-----------------Insert 2025-04-08-----------------------------
INSERT INTO CustDB.dbo.ExchangeDailyOanda (
	[ExchangeDate]
	,[ExchangeId]
	,[Code]
	,[MYR]
	,[USD]
	,[EUR]
	,[CNY]
	,[ActualRate]
	,[IDR]
	,[AUD]
	,[CHF]
	,[GBP]
	,[SGD]
	,[THB]
	,[VND]
	,[KRW]
	,[JPY]
	,[HKD]
	,[TWD]
	,[PHP]
	,[BDT]
	,[INR]
	,[TRY]
	,[NPR]
	,[MXN]
	,[NGN]
	,[RepUpdateTime]
	,[BRL]
	,[PKR]
)
SELECT '2025-04-08' AS [ExchangeDate]
  ,[ExchangeId]
  ,[Code]
  ,[MYR]
  ,[USD]
  ,[EUR]
  ,[CNY]
  ,[ActualRate]
  ,[IDR]
  ,[AUD]
  ,[CHF]
  ,[GBP]
  ,[SGD]
  ,[THB]
  ,[VND]
  ,[KRW]
  ,[JPY]
  ,[HKD]
  ,[TWD]
  ,[PHP]
  ,[BDT]
  ,[INR]
  ,[TRY]
  ,[NPR]
  ,[MXN]
  ,[NGN]
  ,dbo.f_GetDateTime2() AS [RepUpdateTime]
  ,[BRL]
  ,[PKR]
FROM #tmpExchangeDailyOanda