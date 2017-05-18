USE [bk]
GO

ALTER PROCEDURE [dbo].[Task_Bets_TransForecast]
	@transid BIGINT
AS

/*
	Created: 
	Task:	 
	DB: DBBET/BK
	Revisions:
		- 20120904@Viet: add new sportsbook and number game bettype		   
		- 20130121@Johnson: move sp from DB052.BODB02 to DBBET/BK
		- 20160415@Percy: expand range Sportbook [Redmine: #53217]
		- 20170424@Percy: apply Cash Out [RedmineID: #73419]

	Param's Explanation:
*/

INSERT INTO dbo.bets 
(
	transid,
	hdp1,
	hdp2,
	odds,
	stake,
	status,
	livehomescore,
	liveawayscore,
	liveindicator,
	betteam,
	tpositiontaking,
	matchid,
	oddsid,
	ruben,
	bettype,
	currency,
	custid,
	winlostdate
) 
SELECT
	transid,
	hdp1,
	hdp2,
	odds,
	CASE
		WHEN betdaqid <> 0 OR ExtraInfo IS NULL THEN stake
		WHEN ExtraInfo LIKE '%p25%' THEN ISNULL(CAST(('<xml>' + ExtraInfo + '</xml>') AS XML).value('data(/xml/p25/@s)[1]','MONEY'), 0)
		ELSE stake END AS stake,
	status,
	livehomescore,
	liveawayscore,
	liveindicator,
	betteam,
	tpositiontaking,
	matchid,
	oddsid,
	ruben,
	bettype,
	currency,
	custid,
	winlostdate
FROM bodb02.dbo.bettrans WITH (NOLOCK)
WHERE transid > @transid
	AND
	(
		bettype < 50
		OR bettype between 81 and 999
		OR bettype between 1201 and 1299
		OR bettype BETWEEN 1301 AND 1399
	)

GO
GRANT VIEW DEFINITION ON [dbo].[Task_Bets_TransForecast] TO [vnteam] AS [dbo]
GO