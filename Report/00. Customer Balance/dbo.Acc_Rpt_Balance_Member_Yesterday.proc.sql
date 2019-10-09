/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Member_Yesterday]
	@agentid	INT
AS
/*
Created: 
Task : Get member yesterday balance
DB: DB06.bodb02
Original: 
Revisions:	
	- 20090619@Kiwi: Enhence Performance
	- 20100112@Jamie: Get currencyName from Cache 
	- 20101229@Lukas: Re-arrange bettype
	- 20131118@Lukas: add filter to exclude running tickets
	- 20190923@Bobby: Enhance SMA Balance report [redmine: #119990] 
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @currentDate		SMALLDATETIME
			, @yesterday		SMALLDATETIME
			, @_agentid			INT

		SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
			,@yesterday			= @currentDate -1
			,@_agentid			= ISNULL(@agentid, 0)

	SELECT
		c.custid, 
		c.username, 
		c.currency,
		IsNull(b.balance, 0) Balance,
		IsNull(baseBalance,0) AS BaseBalance
	FROM
		dbo.custinfo c (nolock)
		LEFT OUTER JOIN (
			SELECT
				custid,
				SUM(bet.winlost) AS balance,
				SUM(bet.winlost * b.actualrate) AS baseBalance
			FROM dbo.bettrans b with (nolock)
			CROSS APPLY (
				SELECT CASE 
							WHEN b.bettype >= 20000 OR b.winlostdate <= @yesterday THEN (winlost - actual_stake + playercomm) 
							ELSE 0
						END
					AS winlost
			) AS bet
			WHERE b.recommend = @_agentid 
				AND b.winlostdate <= @currentDate
				AND b.ruben = 1 
				AND b.statusID NOT IN (101,102,103)
			GROUP BY b.custid
		) AS b ON c.custid = b.custid
	WHERE
		c.roleid = 1 AND c.recommend = @_agentid 
	ORDER BY c.username
END
GO