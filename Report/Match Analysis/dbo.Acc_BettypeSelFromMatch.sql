USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_BettypeSelFromMatch]
	@eventdate		datetime,
	@matchid		int,	
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME	
AS

/*
	Created: Dan
	Date: 2012/04/05
	Task: Get list of bettype for a match from bettrans for SpecialMatch report
	DB: DBACC/BODB02

	Revisions:
		- 20120920@Sophia: Support only Sportsbook
		- 20121123@Elodie: Add 34 new bettypes of Tennis (1301 -> 1334)
		- 20120215@Elodie: Change linked server DB06 to DBARC
		- 20150529@Jim: add Metric Gaming and apply sport-bettype matrix
		- 20150728@Jim: apply Bettrade (Feature #38815)
		- 20160125@Robert: Cricket - Integrate to Accounting Reports [#50274]
		- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	Parameters Explanations:			
*/
DECLARE @isTest BIT
SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

CREATE TABLE #SportBettype (Bettype INT PRIMARY KEY)

INSERT INTO #SportBettype (Bettype)
SELECT bettype FROM dbo.f_SportBettypeMatrix_Sel(1,0,0,2,'','',@isTest)

DELETE #SportBettype
WHERE bettype IN (901,902,903,904,9,29,10,500)

DECLARE
	@EVDate		DATETIME,
	@MID		INT,	
	@MBDay		SMALLDATETIME,
	@BUDay		SMALLDATETIME	
SELECT @EVDate = @eventdate, @MID = @matchid, @MBDay = @MoveBetsDay, @BUDay = @BalanceUpDay

IF (@EVDate>@MBDay)
BEGIN
	-- get from bettrans
	SELECT DISTINCT b.bettype
	FROM dbo.bettrans b WITH (NOLOCK) 
	INNER JOIN #SportBettype s on b.bettype = s.bettype
 	WHERE 	
			matchid = @MID						
			--AND status NOT IN ('VOID', 'REJECT','REFUND') 	
			AND b.statusID IN (111,112,113)
			AND ruben = 1
			AND Currency <> 20		
END
ELSE IF (@EVDate>=@BUDay)
BEGIN
	-- get from bettrans14	
	SELECT DISTINCT b.bettype
	FROM dbo.bettrans14 b WITH (NOLOCK) 
	INNER JOIN #SportBettype s on b.bettype = s.bettype
 	WHERE 	
			matchid = @MID			
			--AND status NOT IN ('VOID', 'REJECT','REFUND') 	
			AND b.statusID IN (111,112,113)
			AND ruben = 1
			AND Currency <> 20		
	
END
ELSE 
BEGIN
	-- get from bettrans_BK
	DECLARE @SQL NVARCHAR(MAX)
	SELECT  @SQL = 'SELECT bettype FROM OPENQUERY(DBARC, ''SELECT DISTINCT b.bettype FROM bodb_archive.dbo.bettrans_bk b WITH(NOLOCK)
											WHERE winlostdate = ''''' + CONVERT(VARCHAR(10), @EVDate, 120) +
											''''' AND matchid = ' + CONVERT(VARCHAR(20), @MID) +
											' AND status IN (' + '''''DRAW''''' + ',' + '''''WON''''' + ',' + '''''LOSE'''')
											AND ruben = 1 AND Currency <> 20'')'
	CREATE TABLE #bettype (bettype INT)
	INSERT INTO #bettype (bettype)
	EXEC (@SQL)

	SELECT b.bettype
	FROM
		#bettype b WITH (NOLOCK) 
		INNER JOIN #SportBettype s on b.bettype = s.bettype

	DROP TABLE #bettype
END

DROP TABLE #SportBettype