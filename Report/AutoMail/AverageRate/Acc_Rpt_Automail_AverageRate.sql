/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_AverageRate]
	@FromDate    SMALLDATETIME,
	@ToDate      SMALLDATETIME
AS
/*
    Created	: 20201207@Cherry
	Task	: Average Rate (#146621)
	DB		: DBACC/bodb02
	
	Revision:		
		20201207@Cherry: Initial (convert from script adhoc #146621 to SP)

	Param's Explanation:
*/ 
BEGIN
	SELECT Currency, Rate as 'AvgRate'
	FROM (
			SELECT USD=AVG(USD)
				,EUR=AVG(EUR)
				,CNY=AVG(CNY)
				,IDR=AVG(IDR)
				,AUD=AVG(AUD)
				,CHF=AVG(CHF)
				,GBP=AVG(GBP)
				,SGD=AVG(SGD)
				,THB=AVG(THB)
				,VND=AVG(VND)
				,KRW=AVG(KRW)
				,JPY=AVG(JPY)
				,HKD=AVG(HKD)
				,TWD=AVG(TWD)
				,PHP=AVG(PHP)			
			FROM dbo.ExchangeDailyOanda WITH(NOLOCK)
			WHERE ExchangeDate BETWEEN @FromDate AND @ToDate 
				AND exchangeid = 2
		) p  
	UNPIVOT  
	   (Rate FOR Currency IN   
		  (USD, EUR, CNY, IDR, AUD, CHF, GBP, SGD, THB, VND, KRW, JPY, HKD, TWD, PHP)  
	)AS unpvt 
END  