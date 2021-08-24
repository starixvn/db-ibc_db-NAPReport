/*<info serverAlias="DBEXT-bodb02" isFunction="0" executers="bodbAdminNet" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[Acc_Rpt_rptDepWinlost_AGCasino_Bettrans]
	@winlostdate DATETIME
AS
/*   
	Created: 20210413@Danny
	Task: Summary AG Casino data and insert into rptDepWinlost_AGCasino
	DB: DBEXT-bodb02

	Revisions:
		- 20210413@Danny: Initialize SP [RedmineID: #151993]

	EXEC Acc_Rpt_rptDepWinlost_AGCasino_Bettrans '2021-05-21'
		
*/  
SET NOCOUNT ON
BEGIN 

	CREATE TABLE #TicketData (	custid			INT,
								sporttype		SMALLINT,
								currency		INT,
								isVipGame		INT,
								turnover		MONEY,
								drawTO			MONEY,
								winlost			MONEY,
								playercomm		MONEY,
								betCount		INT,
								drawBetCount	INT)

	BEGIN	
		TRUNCATE TABLE #TicketData
			
		INSERT INTO #TicketData (custid, sporttype, currency, isVipGame, turnover, drawTO, winlost, playercomm, betCount, drawBetCount)
		SELECT b.CustID, 
			250 AS SportType,
			b.currency,
			isVIPGame,
			ISNULL(SUM(b.Stake),0) AS Turnover,
			ISNULL(SUM(CASE WHEN b.StatusID = 111 THEN b.Stake ELSE 0 END),0) AS DrawTO,
			ISNULL(SUM(b.Winlost - b.Actual_Stake),0) AS Winlost,
			0 AS PlayerComm,
			ISNULL(COUNT(*),0) AS Betcount,
			ISNULL(SUM(CASE WHEN b.StatusID = 111 THEN 1 ELSE 0 END),0) AS DrawBetCount
		FROM bodb_PlaytechCS.dbo.bettrans_AGCasino b WITH (NOLOCK)
		WHERE Winlostdate = @winlostdate
			AND StatusId IN (111, 112, 113)
		GROUP BY b.CustID, b.currency, isVIPGame

		SELECT	@winlostdate Winlostdate, 
				custid Custid, 
				10 AS ProductId,
				currency CurrencyId,
				SUM(Winlost) Winlost,
				SUM(Turnover) Turnover,
				SUM(BetCount) BetCount,
				SUM(PlayerComm) PlayerComm
		FROM #TicketData	
		WHERE Currency <> 20
		GROUP BY  Custid, Currency
		
	END

	DROP TABLE #TicketData
END 
