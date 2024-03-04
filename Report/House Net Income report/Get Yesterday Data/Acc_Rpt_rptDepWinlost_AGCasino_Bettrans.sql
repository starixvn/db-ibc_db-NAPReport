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
		- 20240403@Danny: AGC product integrate JP, Contribution, Promotion  (#200523)

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
								drawBetCount	INT,
								JpContribution	MONEY,
								StakeContribution MONEY,
								bettype			INT)

	BEGIN	
		TRUNCATE TABLE #TicketData

		;WITH cte_bettrans_AGCasino AS
		(
			SELECT Winlostdate
					, CASE
						WHEN b.PlayType IN (9000, 9001, 9002, 9003, 9004, 9005) THEN 1801
						WHEN b.GameCode IN ('GC0161811101Y', 'RED_POCKET', 'COMP_ENROLL', 'COMP_PRIZE', 'COMP_REFUND', 'EVENT_PRIZE') THEN 1803
						ELSE 1800
					END AS bettype
					, b.Currency
					, SUM(ABS(Stake)) AS Stake
					, SUM(ABS(Actual_stake)) AS Actual_stake
					, SUM(ABS(JpContribution)) AS JpContribution
					, SUM(CASE WHEN b.JpContribution > 0 THEN ABS(Stake) ELSE 0 END) AS StakeContribution
					, ISNULL(SUM(CASE WHEN b.StatusID = 111 THEN b.Stake ELSE 0 END),0) AS DrawTO
					, ISNULL(SUM(b.Winlost - b.Actual_Stake),0) AS Winlost
					, ISNULL(COUNT(1),0) AS Betcount
					, ISNULL(SUM(CASE WHEN b.StatusID = 111 THEN 1 ELSE 0 END),0) AS DrawBetCount
					,CustID
					,isVIPGame
			FROM bodb_PlaytechCS.dbo.bettrans_AGCasino b WITH (NOLOCK)
			WHERE  Winlostdate = @winlostdate
				AND StatusID IN (112, 113, 111)
			GROUP BY Winlostdate
					, b.Currency
					, CASE
							WHEN b.PlayType IN (9000, 9001, 9002, 9003, 9004, 9005) THEN 1801
							WHEN b.GameCode IN ('GC0161811101Y', 'RED_POCKET', 'COMP_ENROLL', 'COMP_PRIZE', 'COMP_REFUND', 'EVENT_PRIZE') THEN 1803
							ELSE 1800
						END
					,CustID
					,isVIPGame
		)INSERT INTO #TicketData (custid, sporttype, currency, isVipGame, turnover, drawTO, winlost, playercomm, betCount, drawBetCount, JpContribution, StakeContribution, bettype)
		SELECT  b.CustID,
				250 AS SportType, 
				b.Currency, 
				b.isVIPGame, 
				SUM(b.Stake) Turnover,
				SUM(b.drawTO) drawTO,
				SUM(b.winlost) winlost,
				0 AS playercomm,
				SUM(b.betCount) betCount,
				SUM(b.DrawBetCount) DrawBetCount,
				SUM(b.JpContribution) JpContribution,
				SUM(b.StakeContribution) StakeContribution,
				b.bettype
		FROM cte_bettrans_AGCasino a
		CROSS APPLY (
			SELECT CustID, isVIPGame,  Winlostdate,bettype,Currency,Stake,Actual_stake,Winlost,0 AS JpContribution,0 AS StakeContribution, DrawTO, Betcount  ,DrawBetCount
			UNION ALL
			SELECT CustID, isVIPGame,  Winlostdate,1802,Currency,0,0,0,JpContribution ,StakeContribution, DrawTO, Betcount,DrawBetCount
			WHERE JpContribution > 0
			) b
		GROUP BY b.Winlostdate, b.Currency, b.bettype, b.CustID, b.isVIPGame

		SELECT	@winlostdate Winlostdate, 
				custid Custid, 
				10 AS ProductId,
				currency CurrencyId,
				SUM(Winlost) Winlost,
				SUM(Turnover) Turnover,
				SUM(BetCount) BetCount,
				SUM(PlayerComm) PlayerComm,
				bettype,
				SUM(JpContribution) JpContribution
		FROM #TicketData	
		WHERE Currency <> 20
		GROUP BY  Custid, Currency, bettype

	END

	DROP TABLE #TicketData
END 
GO
