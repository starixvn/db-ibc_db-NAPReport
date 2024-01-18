ALTER PROCEDURE [dbo].[Acc_HedgeSel]
	@transid bigint
AS

/*
Created: 
Task : Sel hedge record in Betting graph report
DB: DBTRANS.bodb02
Original:

Revisions:
		- 20101007@Henry: Change column transid from INT to BIGINT
		- 20101102@Jamie: SET NOCOUNT 
		- 20111202@Sophia: Add new bettype 124, 125 for 1x2 HDP
		- 20131108@Elodie: Splitting bodb02 into CustDB (call custinfo by link database)
Param's Explanation:

*/
SET NOCOUNT ON 
SELECT
	b.transid,
	c.username,
	m.showtime,  
	m.HomeId,
	m.AwayId,
	b.bettype,
	b.betteam,	
	hdp1,hdp2,CASE
	when b.bettype IN (1,7,124,125) and betteam = 'h' then hdp2-hdp1
	when b.bettype IN (1,7,124,125) and betteam = 'a' then hdp1-hdp2
	when b.bettype IN (3,8) then hdp1
	end hdp, odds, stake, Remark,
	b.LiveIndicator, b.LiveHomescore, b.LiveAwayScore,
	cr.username creator,
	--phuong.nguyen
	isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral
FROM
	dbo.BetHedgeRecord b with (nolock)
	INNER JOIN CustDB.dbo.custinfo c with (nolock) ON b.custid = c.custid AND c.roleid = 1
	INNER JOIN CustDB.dbo.custinfo cr with (nolock) ON b.creator = cr.custid AND cr.roleid > 4
	INNER JOIN dbo.match m with (nolock) ON b.matchid = m.matchid
WHERE
	b.transid=@transid
ORDER BY m.eventdate, c.username, b.bettype, m.matchcode

GO
GRANT EXECUTE ON [dbo].[Acc_HedgeSel] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_HedgeSel] TO [vnteam] AS [dbo]