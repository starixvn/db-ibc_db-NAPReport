/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Agent_Yesterday]
	@masterid INT = 0
AS
/*
Created:
Task: Get Agent yesterday balance
DB: DB06.bodb02
Original:
Revisions:
	- 20090619@Kiwi: Remove Exchange
	- 20100111@Jamie: Get currencyName from cache
	- 20110516@Lukas: re-arrange bettype
	- 20131119@Lukas: remove running/void/reject/refund tickets
	- 20190919@Bobby: Enhance SMA Balance report [redmine: #119990]
	- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
	- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
*/
BEGIN
	SET NOCOUNT ON 

	DECLARE @MoveBetsDay DATE
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentDate	SMALLDATETIME
		, @yesterday		SMALLDATETIME
		, @_masterid		INT

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
		,@yesterday			= @currentDate -1
		,@_masterid			= ISNULL(@masterid,0)
	
	CREATE TABLE #AgentInfo (
		custid				INT PRIMARY KEY
		, username			NVARCHAR(50)
		, currency			INT
	)

	INSERT INTO #AgentInfo (custid, username, currency)
	SELECT c.custid, c.username,c.currency
	FROM dbo.custinfo c (nolock)
	WHERE c.mrecommend = @_masterid
		AND c.roleid = 2

	;
	WITH CTE_AgentBalance AS 
	(
		SELECT	b.recommend AS custid
			,SUM(bet.Balance) AS Balance
			,SUM(bet.Balance * b.actualrate) AS BaseBalance
		FROM #AgentInfo ai
		INNER JOIN dbo.bettrans b WITH (nolock)
		ON b.recommend = ai.custid
		CROSS APPLY (
			SELECT 
				--skip volatile rows during move bet process (see Balance_Direct_Master report)
				CASE WHEN (b.winlostdate > @MoveBetsDay AND bettype = 19999) OR (b.winlostdate <= @MoveBetsDay and bettype < 19999)
					THEN 0 ELSE 1 END
				*
				CASE 
					WHEN (b.bettype >= 20000 OR b.winlostdate <= @yesterday) THEN
						(CASE WHEN b.custid = b.recommend THEN winlost-actual_stake ELSE awinlost+comm-playercomm END) -- agent level
						+ (CASE WHEN b.custid <> b.recommend then winlost-actual_stake+playercomm else 0 end) -- member level
					ELSE 0
				END 
				AS Balance
		) AS bet
		WHERE b.winlostdate <= @currentDate
			AND b.ruben = 1
			AND b.statusID NOT IN (101,102,103)
			AND b.bettype NOT IN (21008, 21009)
		GROUP BY b.recommend
	)
	SELECT c.custid, c.username,c.currency
		,ISNULL(Balance,0) Balance
		,ISNULL(BaseBalance,0) BaseBalance  
	FROM #AgentInfo c
	LEFT JOIN CTE_AgentBalance AS bal 
	ON c.custid = bal.custid
	ORDER BY c.username
END
GO