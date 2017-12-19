USE [bodb02]
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_DailyWLDirect_MixParlay]
	@winlostdate	datetime,
	@bettype		int,
	@site			tinyint = 0
AS


/*	Creator: Phuong Dao
	Date: 2009-03-03
	Task: Winloss Summary History
	DB: DBACC/bodb02

	Revisions:
		- 20090731@Jamie: 
			+ Break out Mix-Parlay into Soccer and Others 
			+ Not to view data in range of date, but only one date at once 
		- 20100330@Jamie: Add one more row for Parlay - Multiple Sports
		-- 20100525@Henry: Change to use StatusID instead of Status in WHERE statement
		- 20100611@Henry: Change mix-parlay match from 0 to 9
		- 16Dec2010@Viet: Correct Turnover's value, will revert back when old data's gone
		- 20110801@Johnson:  add new bettype mix-parlay combination
		- 20110824@Johnson: remove check winlostdate with '16 Dec 2010' for sumary turnover, get from stake instead actual_stake
		- 20110824@Elly: - Correct Turnover of sports book since Sep 01, 2011
		- 20120210@Henry: Fix system parlay turnover bug
		- 20130805@Johnson: filter by site
		- 20130819@Johnson: separate sports by liveawayscore field to correct multi-sports and other sports formula	
		- 20160830@Robert: Enhance System/Mix Parlay [RedmineID: #63022]
	- Parameter's Explanation:
		- @bettype - 9 : mix-parlay
					- 29: combination mix-parlay	
		- @site: 
			0: all sites
			1: credit sites
			2: deposit sites
*/
SET NOCOUNT ON 
	
IF @site = 0
BEGIN	
	SELECT 
			@bettype bettype, status, liveawayscore sporttype,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
			sum((1-tpositiontaking)*ABS(stake)*virtualrate) Turnover
	FROM	bettrans WITH (NOLOCK)
	WHERE
			bettrans.ruben=1 AND			
			matchid IN (9,29) AND 
			bettype IN (9,29) AND
			bettrans.winlostdate = @winlostdate AND
			bettrans.statusID NOT IN (101,102,103) AND			
			(@bettype = CASE WHEN bettype = 29 AND betteam <> N'1' THEN 29 ELSE 9 END) 
	GROUP BY status, liveawayscore 	
END
ELSE
BEGIN
	CREATE TABLE #DepAgent (custid int primary key)
	
	INSERT INTO #DepAgent (custid)
	SELECT c.custid
	FROM custinfo c WITH(NOLOCK)
		LEFT JOIN (select custid from f_DepSuper_1('All')) dep ON c.srecommend = dep.custid
	WHERE roleid = 2
		AND 1= CASE WHEN @site = 1 AND dep.custid IS NULL THEN 1
					WHEN @site = 2 AND dep.custid IS NOT NULL THEN 1 ELSE 0 END
		AND c.custid NOT IN (52466,5707545)--8RM, BARM
	
	INSERT INTO #DepAgent (custid)
	SELECT 52466 WHERE @site = 1--8RM
	UNION
	SELECT 5707545 WHERE @site =2 --BARM	
	
	SELECT 
			@bettype bettype, status, liveawayscore sporttype,
			sum((winlost-actual_stake)*virtualrate) WinLost,
			sum((awinlost+mwinlost+swinlost)*virtualrate) Position,
			sum(scomm*virtualrate) Commission,	
			sum((winlost-actual_stake+awinlost+mwinlost+swinlost+scomm)*virtualrate) LineTotal,
			sum((1-tpositiontaking)*ABS(case when bettype=29 and betid>0 then  actual_stake else stake end)*virtualrate) Turnover
	FROM	bettrans WITH (NOLOCK)
		INNER JOIN #DepAgent dep ON bettrans.recommend = dep.custid
	WHERE
			bettrans.ruben=1 AND			
			matchid IN (9,29) AND 
			bettype  IN (9,29) AND 
			bettrans.winlostdate = @winlostdate AND			
			bettrans.statusID NOT IN (101,102,103) AND
			(@bettype = CASE WHEN bettype = 29 AND betteam <> N'1' THEN 29 ELSE 9 END) 			 
	GROUP BY status, liveawayscore
	
	DROP TABLE #DepAgent
END

	-------------------

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyWLDirect_MixParlay] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyWLDirect_MixParlay] TO [vnteam]