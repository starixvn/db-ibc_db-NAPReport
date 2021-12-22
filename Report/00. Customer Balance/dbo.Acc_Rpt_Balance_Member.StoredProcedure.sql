/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Balance_Member]
	@agentid	INT
AS
/*
Created:
Task : Get member balance
DB: DBACC.bodb02
Original:
Revisions:
	- 20090619@Kiwi: Enhence Performance
	- 20100112@Jamie: Get currencyName from Cache
	- 20131118@Lukas: add filter to exclude running tickets
	- 20190923@Bobby: Enhance SMA Balance report [redmine: #119990]
	- 20201027@Ned.Le: NAP Report - BBin - Remove BBIN Transfer off Balance reports (#144071)
	- 20210507@Jaden.Tang: Adjust code to prevent reading dupplicated in bettrans & bettrans14 during move bet process (#154649)
	- 20211111@Cherry: Split transfer table (#164378)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MoveBetsDay DATE
	SELECT @MoveBetsDay = MoveBetsDay
	FROM OPENQUERY(DBACC,'exec bodb02.dbo.Age_SelBalanceUpDay')

	DECLARE @currentDate		SMALLDATETIME
			, @_agentid			INT
			, @srecommend		INT

	SELECT @currentDate		= CAST(CURRENT_TIMESTAMP AS DATE)
		,@_agentid			= ISNULL(@agentid, 0)
		
	SELECT @srecommend = srecommend
	FROM dbo.custinfo  (nolock)
	WHERE custid = @_agentid
		AND roleid = 2

	CREATE TABLE #Data 
	(
		Custid INT,
		Balance MONEY,
		BaseBalance MONEY
	)
	
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--skip volatile rows during move bet process, see Balance_Direct_Master report
					case when b.winlostdate <= @MoveBetsDay then NULL
						 else b.custid
					end custid,
					SUM(b.winlost - b.actual_stake + b.playercomm) AS Balance,
					SUM((b.winlost - b.actual_stake + b.playercomm)* b.actualrate) AS BaseBalance
	FROM	dbo.bettrans b with (nolock)
	WHERE	b.recommend = @_agentid
		AND b.winlostdate <= @currentDate
		AND b.bettype < 19999
		AND b.ruben = 1
		AND b.statusID NOT IN (101,102,103)
	GROUP BY case when b.winlostdate <= @MoveBetsDay then NULL
				else b.custid
			end
			
	INSERT INTO #Data (Custid, Balance, BaseBalance)
	SELECT	--skip volatile rows during move bet process, see Balance_Direct_Master report
					case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
						 else b.custid
					end custid,
					SUM(b.winlost - b.actual_stake + b.playercomm) AS Balance,
					SUM((b.winlost - b.actual_stake + b.playercomm)* b.actualrate) AS BaseBalance
	FROM	dbo.[Transfer] b with (nolock)
	WHERE	b.recommend = @_agentid
		AND b.srecommend = @srecommend
		AND b.winlostdate <= @currentDate		
		AND b.statusID NOT IN (101,102,103)
		AND b.bettype NOT IN (21008, 21009)
	GROUP BY case when b.winlostdate > @MoveBetsDay and bettype = 19999 then NULL
				else b.custid
			end
			
	SELECT
			c.custid, 
			c.username, 
			c.currency,
			IsNull(SUM(b.Balance), 0) Balance,
			IsNull(SUM(b.BaseBalance),0) AS BaseBalance
	FROM
		dbo.custinfo c (nolock)
		LEFT JOIN #Data b ON c.custid = b.custid
	WHERE
		c.roleid = 1 AND c.recommend = @_agentid
	GROUP BY c.custid, 
			c.username, 
			c.currency
	ORDER BY c.username

	DROP TABLE #Data
	
END
GO