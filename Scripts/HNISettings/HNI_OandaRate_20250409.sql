/*<info serverAlias="DBCUST-CustDB"></info>*/

/*
	Created by Aries@20250408
	Run at DBCUST@CustDB
	Task: Missing OANDA exchange rates - Manual insert data for [April 9] from [April 5] (#223200)
*/

USE CustDB
GO

DROP TABLE IF EXISTS #tmpExchangeDailyOanda

SELECT *
INTO #tmpExchangeDailyOanda
FROM CustDB.dbo.ExchangeDailyOanda WITH (NOLOCK)
WHERE ExchangeDate = '2025-04-05'

-----------------Insert 2025-04-09-----------------------------
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
SELECT '2025-04-09' AS [ExchangeDate]
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
