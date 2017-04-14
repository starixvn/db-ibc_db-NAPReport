ALTER PROCEDURE [dbo].[Acc_Rpt_OriginalBalMovement_SAg]
AS
/*
	Created by: Jamie
	Date: 2009-08-21
	Task: Super Original Balance Movement 
	DB: DB06.BODB02 

*/
BEGIN
	SET NOCOUNT ON
	DECLARE	@today	DATETIME 
	SELECT	@today = CONVERT(VARCHAR(10),CURRENT_TIMESTAMP,120)

	DECLARE	@tmpCust TABLE (
		custID			INT PRIMARY KEY,
		username		VARCHAR(25),
		currencyName	VARCHAR(50)
	)

	INSERT INTO @tmpCust( custID, username, currencyName)
	SELECT	c.custid, c.username, e.currency 
	FROM (
			SELECT	DISTINCT custid	FROM bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
			UNION 
			SELECT	srecommend FROM bettrans WITH (NOLOCK) 
			WHERE	winlostdate = @today AND ruben = 1 AND status NOT IN ('VOID','REJECT','REFUND')
		 ) t
			INNER JOIN custinfo c WITH (NOLOCK) ON t.custid = c.custid 
			INNER JOIN exchange e WITH (NOLOCK) ON c.currency = e.exchangeid 

	SELECT	s.username,
			s.currencyName,
			ISNULL(d0.Bal,0) D0Bal, 
			--Day 1 
			ISNULL(d1.pos,0) D1Pos, 
			ISNULL(d1.com,0) D1Com,
			ISNULL(d1.bet,0) D1Bet,
			ISNULL(d1.tra,0) D1Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0)  D1Bal,
			--Day 2 
			ISNULL(d2.pos,0) D2Pos, 
			ISNULL(d2.com,0) D2Com,
			ISNULL(d2.bet,0) D2Bet,
			ISNULL(d2.tra,0) D2Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0) + ISNULL(d2.bal,0) D2Bal,
			--Day 3 
			ISNULL(d3.pos,0) D3Pos, 
			ISNULL(d3.com,0) D3Com,
			ISNULL(d3.bet,0) D3Bet,
			ISNULL(d3.tra,0) D3Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0) + ISNULL(d2.bal,0) + ISNULL(d3.bal,0) D3Bal,
			--Day 4 
			ISNULL(d4.pos,0) D4Pos, 
			ISNULL(d4.com,0) D4Com,
			ISNULL(d4.bet,0) D4Bet,
			ISNULL(d4.tra,0) D4Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0) + ISNULL(d2.bal,0) + ISNULL(d3.bal,0) + ISNULL(d4.bal,0) D4Bal,
			--Day 5 
			ISNULL(d5.pos,0) D5Pos, 
			ISNULL(d5.com,0) D5Com,
			ISNULL(d5.bet,0) D5Bet,
			ISNULL(d5.tra,0) D5Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0) + ISNULL(d2.bal,0) + ISNULL(d3.bal,0) + ISNULL(d4.bal,0) + ISNULL(d5.bal,0) D5Bal,
			--Day 6 
			ISNULL(d6.pos,0) D6Pos,
			ISNULL(d6.com,0) D6Com,
			ISNULL(d6.bet,0) D6Bet,
			ISNULL(d6.tra,0) D6Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0) + ISNULL(d2.bal,0) + ISNULL(d3.bal,0) + ISNULL(d4.bal,0) + ISNULL(d5.bal,0) + ISNULL(d6.bal,0) D6Bal,
			--Day 7 
			ISNULL(d7.pos,0) D7Pos,
			ISNULL(d7.com,0) D7Com,
			ISNULL(d7.bet,0) D7Bet,
			ISNULL(d7.tra,0) D7Tra,
			ISNULL(d0.Bal,0) + ISNULL(d1.bal,0) + ISNULL(d2.bal,0) + ISNULL(d3.bal,0) + ISNULL(d4.bal,0) + ISNULL(d5.bal,0) + ISNULL(d6.bal,0) + ISNULL(d7.bal,0) D7Bal
			
	FROM	@tmpCust s 
			LEFT JOIN (
				SELECT	custid,
						BalOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 7
			
			) d0 ON d0.custid = s.custid 
			LEFT JOIN (
				SELECT	custid,
						posOriginal Pos,
						comOriginal Com,
						betOriginal Bet,
						traOriginal Tra,
						balOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 6
			
			) d1 ON d1.custid = s.custid 
			LEFT JOIN (
				SELECT	custid,
						posOriginal Pos,
						comOriginal Com,
						betOriginal Bet,
						traOriginal Tra,
						balOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 5
			
			) d2 ON d2.custid = s.custid 
			LEFT JOIN (
				SELECT	custid,
						posOriginal Pos,
						comOriginal Com,
						betOriginal Bet,
						traOriginal Tra,
						balOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 4
			
			) d3 ON d3.custid = s.custid 
			LEFT JOIN (
				SELECT	custid,
						posOriginal Pos,
						comOriginal Com,
						betOriginal Bet,
						traOriginal Tra,
						balOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 3
			
			) d4 ON d4.custid = s.custid 
			LEFT JOIN (
				SELECT	custid,
						posOriginal Pos,
						comOriginal Com,
						betOriginal Bet,
						traOriginal Tra,
						balOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 2
			
			) d5 ON d5.custid = s.custid 
			LEFT JOIN (
				SELECT	custid,
						posOriginal Pos,
						comOriginal Com,
						betOriginal Bet,
						traOriginal Tra,
						balOriginal Bal 
				FROM	bodb_Report.dbo.rptCustBalance WITH (NOLOCK)
				WHERE	winlostdate = @today - 1
			
			) d6 ON d6.custid = s.custid 
			LEFT JOIN dbo.f_OriginalBalMovement_SAg(@today) d7 ON d7.custid = s.custid 
	ORDER BY s.username
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_OriginalBalMovement_SAg] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_OriginalBalMovement_SAg] TO [vnteam]



