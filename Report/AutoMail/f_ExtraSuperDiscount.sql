/*<info serverAlias="DBAGE-bodb02" selecters="" isFunction="1" isNested="1"></info>*/
ALTER FUNCTION [dbo].[f_ExtraSuperDiscount]()
RETURNS TABLE
AS

/*
	Created: 20200505@Percy
	DB: DBAGE-bodb02
	Task: Core function config Super Extra Commission

	Revisions:
		- 20200505@Percy: Initialize SP [RedmineID: #133413]
		- 20200723@Percy: Get super from IBCIndo site [RedmineID: #138169]
*/

RETURN
	SELECT
		c.CustId
		,c.UserName
		,c.Currency
		,CONVERT(SMALLINT, ProductId)		AS ProductId
		,CONVERT(SMALLINT, SportType)		AS SportType
		,CONVERT(SMALLINT, 0)				AS BetType
		,CONVERT(DATETIME, '2020-04-01')	AS FromDate
		,CONVERT(DATETIME, '9999-12-31')	AS ToDate
		,CONVERT(FLOAT, 0.008)				AS Discount
		,CONVERT(FLOAT, 0.002)				AS ExtraDiscount
	FROM dbo.Customer c WITH (NOLOCK)
		CROSS JOIN (
			SELECT 12 AS ProductId, 255 AS SportType
			UNION ALL
			SELECT 21, 211
			UNION ALL
			SELECT 39, 244
		) p
	WHERE c.roleid = 4 AND c.site = 'IBCIndo'
GO