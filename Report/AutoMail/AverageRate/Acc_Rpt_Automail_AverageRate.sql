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
		20210104@Cherry: Change request (#146621)

	Param's Explanation:
*/ 
BEGIN
	SELECT DISTINCT o.code AS Currency
	  ,LTRIM(STR(1/avg(EUR) * MultipliedBy, 19, 8)) AS 'AvgRate'
	FROM dbo.ExchangeDailyOanda o WITH(NOLOCK)
	  INNER JOIN dbo.exchange e WITH(NOLOCK) ON o.exchangeid = e.exchangeid
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate 
	  AND o.ExchangeId <> 20
	GROUP BY o.code, MultipliedBy
	ORDER BY o.code
END  