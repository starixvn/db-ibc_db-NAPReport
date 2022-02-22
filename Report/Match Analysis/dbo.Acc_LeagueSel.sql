/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
use bodb02
GO
ALTER PROCEDURE [dbo].[Acc_LeagueSel]
	@eventdate datetime,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME	
AS

/*
	Created: Dan
	Date: 2012/04/04
	Task: Get list of leagues for report Special match analysis
	DB: DBACC/BODB02

	Revisions:
		- 20120914@Sophia: Revise condition of sporttype: support sportbook, number games, live casino
		- 20120920@Sophia: Only support sportbook
		- 20120215@Elodie: Change linked server DB06 to DBARC
		- 20131204@Kathy: Add HR Fixed Odds (154) [Redmine:#6505]
		- 20211216@Jaden: Add IsDeleted column check (#164376)
	Parameters Explanations:			
*/
SET NOCOUNT ON
IF (@eventdate>@MoveBetsDay)
BEGIN
	-- get from match
	SELECT DISTINCT m.sporttype, m.leagueid
	FROM dbo.match m WITH (NOLOCK) 
	INNER JOIN dbo.league l WITH (NOLOCK) 
			ON l.leagueid = m.leagueid	
	WHERE eventdate = @eventdate
		and (m.sporttype <=99 OR m.sporttype = 154)  --support sportbook
		and m.matchcode not like '%hedge%'	--exclude hedge match
		and m.eventstatus = 'completed'
		and m.betstatus <> 'Refund'
		and l.isTest = 0
		and m.isDeleted = 0
	ORDER BY m.sporttype, m.leagueid	
END
ELSE IF (@eventdate>=@BalanceUpDay)
BEGIN
	-- get from match14	
	SELECT DISTINCT m.sporttype, m.leagueid
	FROM dbo.match14 m WITH (NOLOCK)
	INNER JOIN dbo.league l WITH (NOLOCK) 
			ON l.leagueid = m.leagueid 
	WHERE eventdate = @eventdate
		and (m.sporttype <=99 OR m.sporttype = 154)  --support sportbook
		and m.matchcode not like '%hedge%'	--exclude hedge match
		and m.eventstatus = 'completed'
		and m.betstatus <> 'Refund'
		and l.isTest = 0
	ORDER BY m.sporttype, m.leagueid
END
ELSE 
BEGIN
	-- get from match_bk
	SELECT DISTINCT m.sporttype, m.leagueid
	FROM DBARC.BODB_Archive.dbo.match_bk m WITH (NOLOCK) 
	INNER JOIN dbo.league l WITH (NOLOCK) 
			ON l.leagueid = m.leagueid
	WHERE eventdate = @eventdate
		and (m.sporttype <=99 OR m.sporttype = 154)  --support sportbook
		and m.matchcode not like '%hedge%'	--exclude hedge match
		and m.eventstatus = 'completed'
		and m.betstatus <> 'Refund'
		and l.isTest = 0
	ORDER BY m.sporttype, m.leagueid
END


GO
GRANT EXECUTE ON [dbo].[Acc_LeagueSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_LeagueSel] TO [vnteam]