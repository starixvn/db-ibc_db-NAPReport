/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE bodb02 
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_MonthlyAbnormalBets]
	@FromDate		DATETIME
	,@ToDate		DATETIME
AS
/*
	Created: 20191101@Harry
	Task: #123087 - SAS - Monthly Abnormal bets report
	DB: DB061.BODB02

	Revisions:
		- 20191231@Harry: add reasons: Robot Betting and Irrigation Bet
*/
BEGIN
	SELECT @todate = DATEADD(DD, 1, @todate)

	CREATE TABLE #tmp_voidabticket (
		TransId BIGINT
		,Monthly VARCHAR(100)
		,IssueTypeID INT
		,SubIssueTypeID INT
		,CustID INT
		,SubIssueTypeName VARCHAR(100)
		,Match INT
		,Sport VARCHAR(100)
		,Live VARCHAR(100)
		,Division VARCHAR(100)
		,currency INT
		)

	INSERT #tmp_voidabticket (
		TransId
		,Monthly
		,IssueTypeID
		,SubIssueTypeID
		,CustID
		,SubIssueTypeName
		,Match
		,Sport
		,Live
		,Division
		,currency
		)
	SELECT tv.TransId
		,CONVERT(VARCHAR(10), Year(CreatedDate)) + '-' + CONVERT(VARCHAR(10), RIGHT('0' + RTRIM(MONTH(CreatedDate)), 2)) AS Monthly
		,tv.IssueTypeID
		,tv.SubIssueTypeID
		,tv.CustID
		,tvs.SubIssueTypeName
		,bt.matchid 'match'
		,CASE 
			WHEN m.sporttype = 1
				THEN 'soccer'
			WHEN m.sporttype <> 1
				THEN 'OS'
		END 'Sport'
		,CASE 
			WHEN bt.liveindicator = 0
				THEN 'Non-Live'
			WHEN bt.liveindicator = 1
				THEN 'Live'
			ELSE 'Live & Non-Live'
		END [Live]
		,CASE 
			WHEN si.isDeposit = 0
				AND si.site NOT IN (
					'cn88'
					,'789y'
					)
				THEN 'Nova88'
			WHEN si.isDeposit = 1
				THEN 'Licensee'
			WHEN si.site IN ('cn88')
				THEN 'CN88'
			WHEN si.site IN ('789y')
				THEN '789Y'
		END [Division]
		,s.currency
	FROM [dbo].[TicketVoiding_VoidedTransaction] tv WITH (NOLOCK)
		INNER JOIN dbo.TicketVoiding_SubIssueType tvs WITH (NOLOCK) ON tv.SubIssueTypeID = tvs.SubIssueTypeId
		INNER JOIN dbo.zzzbettrans bt WITH (NOLOCK) ON bt.transid = tv.TransId 
		CROSS APPLY (
			SELECT matchid
				,sporttype
				,leagueID
			FROM dbarc.bodb_archive.dbo.match_bk m WITH (NOLOCK)
			WHERE matchid = bt.matchid
		
			UNION ALL
		
			SELECT matchid
				,sporttype
				,leagueID
			FROM dbo.match14 m WITH (NOLOCK)
			WHERE matchid = bt.matchid
		
			UNION ALL
		
			SELECT matchid
				,sporttype
				,leagueID
			FROM dbo.match m WITH (NOLOCK)
			WHERE matchid = bt.matchid
			) m
		INNER JOIN dbo.League l WITH (NOLOCK) ON l.leagueid = m.leagueid AND l.isTest = 0
		INNER JOIN dbo.vw_Customer s WITH (NOLOCK) ON s.custid = tv.CustID
		INNER JOIN dbo.vw_Customer s1 WITH (NOLOCK) ON s.recommend = s1.CustID
		INNER JOIN dbo.site si WITH (NOLOCK) ON si.site = s1.site
	WHERE tv.IssueTypeID = 11
		AND s.currency <> 20
		AND tv.CreatedDate >= @fromdate
		AND tv.CreatedDate < @todate;

	SELECT Monthly
		,[Division]
		,Sport
		,Live
		,match
		,SubIssueTypeName
		,COUNT(1) total
	INTO #final
	FROM #tmp_voidabticket
	GROUP BY GROUPING SETS((Monthly), 
				(Monthly,match), 
				(Monthly,Sport,match), 
				(Monthly,[Division],Sport,Live), 
				(Monthly,Division,match,SubIssueTypeName));



	WITH match
	AS (
		SELECT *
		FROM (
			SELECT Monthly
				,sport
				,match
			FROM #final
			WHERE Division IS NULL
				AND sport IS NOT NULL
				AND live IS NULL
				AND match IS NOT NULL
				AND SubIssueTypeName IS NULL
			
			UNION
			
			SELECT Monthly
				,'TOTAL'
				,match
			FROM #final
			WHERE Division IS NULL
				AND sport IS NOT NULL
				AND live IS NULL
				AND match IS NOT NULL
				AND SubIssueTypeName IS NULL
			) scr
		PIVOT(count(match) FOR sport IN (
					[total]
					,[Soccer]
					,[OS]
					)) p
		)
		,reason
	AS (
		SELECT *
		FROM (
			SELECT DISTINCT Monthly
				,Division + '-' + SubIssueTypeName [reason]
				,match
			FROM #final
			WHERE Division IS NOT NULL
				AND sport IS NULL
				AND live IS NULL
				AND match IS NOT NULL
				AND SubIssueTypeName IS NOT NULL
			) scr
		PIVOT(count(match) FOR reason IN (
					[Nova88-Group Betting]
					,[Nova88-Fixed Game]
					,[Nova88-Abnormal]
					,[Nova88-Arbitrage]
					,[Nova88-Hedging]
					,[Nova88-AB Bet]
					,[Nova88-Irrigation Bet]
					,[Nova88-Robot Betting]
					,[Licensee-Group Betting]
					,[Licensee-Fixed Game]
					,[Licensee-Abnormal]
					,[Licensee-Arbitrage]
					,[Licensee-Hedging]
					,[Licensee-AB Bet]
					,[Licensee-Irrigation Bet]
					,[Licensee-Robot Betting]
					,[789y-Group Betting]
					,[789y-Fixed Game]
					,[789y-Abnormal]
					,[789y-Arbitrage]
					,[789y-Hedging]
					,[789y-AB Bet]
					,[789y-Irrigation Bet]
					,[789y-Robot Betting]
					,[cn88-Group Betting]
					,[cn88-Fixed Game]
					,[cn88-Abnormal]
					,[cn88-Arbitrage]
					,[cn88-Hedging]
					,[cn88-AB Bet]
					,[cn88-Irrigation Bet]
					,[cn88-Robot Betting]
					)) p
		)
		,tickettype
	AS (
		SELECT *
		FROM (
			SELECT Monthly
				,Division + '-' + sport + '-' + Live [event]
				,total
			FROM #final
			WHERE Division IS NOT NULL
				AND sport IS NOT NULL
				AND live IS NOT NULL
				AND match IS NULL
				AND SubIssueTypeName IS NULL
			
			UNION
			
			SELECT Monthly
				,Division + '-' + 'TOTAL'
				,total
			FROM #final
			WHERE Division IS NOT NULL
				AND sport IS NOT NULL
				AND live IS NOT NULL
				AND match IS NULL
				AND SubIssueTypeName IS NULL
			) scr
		pivot(sum(total) FOR event IN (
					[Nova88-soccer-live]
					,[Nova88-Soccer-Non-live]
					,[Nova88-OS-Live]
					,[Nova88-OS-non-live]
					,[Nova88-TOTAL]
					,[789y-soccer-live]
					,[789y-Soccer-Non-live]
					,[789y-OS-Live]
					,[789y-OS-non-live]
					,[789y-TOTAL]
					,[Licensee-soccer-live]
					,[Licensee-Soccer-Non-live]
					,[Licensee-OS-Live]
					,[Licensee-OS-non-live]
					,[Licensee-TOTAL]
					,[CN88-soccer-live]
					,[CN88-Soccer-Non-live]
					,[CN88-OS-Live]
					,[CN88-OS-non-live]
					,[CN88-TOTAL]
					)) p
		)
		,tickettotal
	AS (
		SELECT *
		FROM (
			SELECT Monthly
				,total
			FROM #final
			WHERE Division IS NULL
				AND sport IS NULL
				AND live IS NULL
				AND match IS NULL
				AND SubIssueTypeName IS NULL
			) scr
		)
	SELECT m.[monthly]
		,[Soccer]
		,[OS]
		,m.[total] [Toal Matches Voided]
		,ISNULL([Nova88-soccer-live], 0) [Nova88-soccer-live]
		,ISNULL([Nova88-Soccer-Non-live], 0) [Nova88-Soccer-Non-live]
		,ISNULL([Nova88-OS-Live], 0) [Nova88-OS-Live]
		,ISNULL([Nova88-OS-non-live], 0) [Nova88-OS-non-live]
		,ISNULL([Nova88-TOTAL], 0) [Nova88-TOTAL]
		,ISNULL([Nova88-Group Betting], 0) [Nova88-Group Betting]
		,ISNULL([Nova88-Fixed Game], 0) [Nova88-Fixed Game]
		,ISNULL([Nova88-Abnormal], 0) [Nova88-Abnormal]
		,ISNULL([Nova88-Arbitrage], 0) [Nova88-Arbitrage]
		,ISNULL([Nova88-Hedging], 0) [Nova88-Hedging]
		,ISNULL([Nova88-AB Bet], 0) [Nova88-AB Bet]
		,ISNULL([Nova88-Irrigation Bet], 0) [Nova88-Irrigation Bet]
		,ISNULL([Nova88-Robot Betting], 0) [Nova88-Robot Betting]

		,ISNULL([789y-soccer-live], 0) [789y-soccer-live]
		,ISNULL([789y-Soccer-Non-live], 0) [789y-Soccer-Non-live]
		,ISNULL([789y-OS-Live], 0) [789y-OS-Live]
		,ISNULL([789y-OS-non-live], 0) [789y-OS-non-live]
		,ISNULL([789y-TOTAL], 0) [789y-TOTAL]
		,ISNULL([789y-Group Betting], 0) [789y-Group Betting]
		,ISNULL([789y-Fixed Game], 0) [789y-Fixed Game]
		,ISNULL([789y-Abnormal], 0) [789y-Abnormal]
		,ISNULL([789y-Arbitrage], 0) [789y-Arbitrage]
		,ISNULL([789y-Hedging], 0) [789y-Hedging]
		,ISNULL([789y-AB Bet], 0) [789y-AB Bet]
		,ISNULL([789y-Irrigation Bet], 0) [789y-Irrigation Bet]
		,ISNULL([789y-Robot Betting], 0) [789y-Robot Betting]

		,ISNULL([Licensee-soccer-live], 0) [Licensee-soccer-live]
		,ISNULL([Licensee-Soccer-Non-live], 0) [Licensee-Soccer-Non-live]
		,ISNULL([Licensee-OS-Live], 0) [Licensee-OS-Live]
		,ISNULL([Licensee-OS-non-live], 0) [Licensee-OS-non-live]
		,ISNULL([Licensee-TOTAL], 0) [Licensee-TOTAL]
		,ISNULL([Licensee-Group Betting], 0) [Licensee-Group Betting]
		,ISNULL([Licensee-Fixed Game], 0) [Licensee-Fixed Game]
		,ISNULL([Licensee-Abnormal], 0) [Licensee-Abnormal]
		,ISNULL([Licensee-Arbitrage], 0) [Licensee-Arbitrage]
		,ISNULL([Licensee-Hedging], 0) [Licensee-Hedging]
		,ISNULL([Licensee-AB Bet], 0) [Licensee-AB Bet]
		,ISNULL([Licensee-Irrigation Bet], 0) [Licensee-Irrigation Bet]
		,ISNULL([Licensee-Robot Betting], 0) [Licensee-Robot Betting]

		,ISNULL([CN88-soccer-live], 0) [CN88-soccer-live]
		,ISNULL([CN88-Soccer-Non-live], 0) [CN88-Soccer-Non-live]
		,ISNULL([CN88-OS-Live], 0) [CN88-OS-Live]
		,ISNULL([CN88-OS-non-live], 0) [CN88-OS-non-live]
		,ISNULL([CN88-TOTAL], 0) [CN88-TOTAL]
		,ISNULL([cn88-Group Betting], 0) [cn88-Group Betting]
		,ISNULL([cn88-Fixed Game], 0) [cn88-Fixed Game]
		,ISNULL([cn88-Abnormal], 0) [cn88-Abnormal]
		,ISNULL([cn88-Arbitrage], 0) [cn88-Arbitrage]
		,ISNULL([cn88-Hedging], 0) [cn88-Hedging]
		,ISNULL([cn88-AB Bet], 0) [cn88-AB Bet]
		,ISNULL([CN88-Irrigation Bet], 0) [CN88-Irrigation Bet]
		,ISNULL([CN88-Robot Betting], 0) [CN88-Robot Betting]

	FROM match m
		INNER JOIN tickettype t ON t.Monthly = m.Monthly
		INNER JOIN reason r ON m.monthly = r.Monthly
		INNER JOIN tickettotal t1 ON t1.Monthly = m.Monthly
	ORDER BY m.[monthly]

	DROP TABLE #tmp_voidabticket

	DROP TABLE #final
END