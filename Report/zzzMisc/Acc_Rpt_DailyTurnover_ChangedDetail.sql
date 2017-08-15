USE [bodb02]
GO
ALTER PROCEDURE [dbo].[Acc_Rpt_DailyTurnover_ChangedDetail]
	@fromdate datetime
AS
/*
Created: Minzy@20120405
Task : Get agency, ibc turnover, bet count changed detail

DB: DB06.bodb02
Original: 

Revisions:
	- 20120511@Minzy: Fix when get data from bettrans14, must get team name from match14
	- Daniel@20120605: exclude 3rd party bettypes when checking void bet case
	- 20121213@Dan: Change linked server from DB052-->DBLOG
	- 20150126@Jamie: Missing 3rd party's tickets - HotFix [#29477]
	- 20150728@Jim: apply Bettrade (Feature #38815)
	- 20160325@Jim: Exclude Bettrade [hotfix #54691]
	- 20160607@Jim:Add More Actions of Settlement to Daily Turnover Report (#57781)
	- 20160819@Robert: Add Bet Trade Winloss bettype=904 (#62630)
	- 20170815@Tom: Add some bettype missing (#81287)
Param's Explanation:

*/
BEGIN
	
	SET NOCOUNT ON
	 DECLARE @fromdate_ DATETIME  
	 SET @fromdate_=@fromdate  
 
	DECLARE @datelog DATETIME
	SET @datelog = dateadd(d,1,@fromdate) 
	-- Temp table to save changed stake,bet count detail
	CREATE TABLE #temp(	logdate DATETIME,
					actionid INT,
					DetailID BIGINT,-- matchid or transid(void ticket)
					UserID INT,
					Total_Virtual MONEY,
					Total_Actual MONEY,
					Super_Virtual MONEY,
					Super_Actual MONEY,
					Master_Virtual MONEY,
					Master_Actual MONEY,
					Agent_Virtual MONEY,
					Agent_Actual MONEY,
					IBC_Virtual MONEY,
					IBC_Actual MONEY
			)

	DECLARE	@tmpBettypes TABLE(
		Bettype		INT
	)
	DECLARE @BettypeAction AS TABLE (
	ActionID INT
	,BettypeID INT
	)
	INSERT INTO @BettypeAction ( ActionID,BettypeID)
	SELECT ActionID
		  ,	CONVERT(INT,strbettye) AS BettypeID
	FROM dbo.[v_ActionIDBettype]
	WHERE CONVERT(INT,strbettye) <> 0
	
	CREATE TABLE #tmpUserLog  (logdate DATETIME
							   ,matchId INT
							   ,actionId INT
							   ,UserID INT
							   )
							   
	INSERT INTO #tmpUserLog (LogDate,MatchID,ActionID,UserID)						   
			SELECT LogDate,MatchID,ActionID,UserID
			FROM DBLOG.bodb_customerlog.dbo.userlog_settle   WITH (nolock)
			WHERE logdate between @datelog AND getdate()
				AND ActionID IN (SELECT DISTINCT ActionID FROM @BettypeAction)
	UNION 
		   SELECT LogDate,MatchID,ActionID,UserID
			FROM DBLOG.bodb_customerlog.dbo.UserLog_Settle3rd   WITH (nolock)
			WHERE logdate between @datelog AND getdate()
				AND ActionID IN (SELECT DISTINCT ActionID FROM @BettypeAction)
				
	INSERT INTO @tmpBettypes(Bettype)
	SELECT	Bettype 
	FROM	SportBettypeMatrix WITH (NOLOCK)
	WHERE	ProductID = 1
			AND EventType = 1 
			AND bettype NOT IN (901,902,903, 904)
	-- Consider to include bettrans_BK into query or not.
	IF @fromdate_<= (select max(distinct eventdate) from match14 (nolock))
	BEGIN
		INSERT INTO #temp(logdate,DetailID,actionid,UserID,Total_Actual,Total_Virtual,Super_Actual,Super_Virtual,Master_Actual,Master_Virtual,Agent_Actual,Agent_Virtual,IBC_Actual,IBC_Virtual)--TicketCNT,NormalCNT,RejectCNT)
		SELECT l.logdate,l.matchid,l.actionid,l.UserID,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Total_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Total_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *spositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Super_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *spositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Super_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *mpositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Master_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *mpositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Master_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *apositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Agent_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *apositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Agent_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * (1-tpositiontaking) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) IBC_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * (1-tpositiontaking) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) IBC_Virtual
		FROM #tmpUserLog l  
			INNER JOIN bodb02.dbo.bettrans14 b WITH (nolock) ON (l.matchid = b.matchid AND b.currency <> 20 )
			INNER JOIN @BettypeAction bet ON l.actionID = bet.actionID AND b.bettype= bet.BettypeID
			LEFT JOIN bodb02.dbo.zzzbettrans z WITH (nolock) ON  (b.transid=z.transid)
		WHERE	b.winlostdate = @fromdate_
				AND (bet.actionID = 126 AND ( b.custid IN (50057, 879241, 103873, 78761, 851668, 878902)  OR  b.recommend IN (1688156))
					  OR bet.actionID <> 126	
						)
				AND (bet.actionID = 135 AND (b.custid IN (2331, 1077687, 115770, 15523642) )
					 OR bet.actionID <> 135	
					)		
		GROUP BY l.logdate,l.matchid,l.actionid,l.UserID
		ORDER BY l.logdate,l.matchid,l.actionid,l.UserID

		-- Void ticket
		INSERT INTO #temp(logdate,actionid,DetailID,UserID,Total_Actual,Total_Virtual,Super_Actual,Super_Virtual,Master_Actual,Master_Virtual,Agent_Actual,Agent_Virtual,IBC_Actual,IBC_Virtual)--TicketCNT,NormalCNT,RejectCNT)
		SELECT z.transdate,-1,z.transid,b.creator,
			abs(b.stake) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Total_Actual,
			abs(b.stake) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Total_Virtual,
			abs(b.stake) *spositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Super_Actual,
			abs(b.stake) *spositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Super_Virtual,
			abs(b.stake) *mpositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Master_Actual,
			abs(b.stake) *mpositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Master_Virtual,
			abs(b.stake) *apositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Agent_Actual,
			abs(b.stake) *apositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Agent_Virtual,
			abs(b.stake) * (1-tpositiontaking) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end IBC_Actual,
			abs(b.stake) * (1-tpositiontaking) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end IBC_Virtual
		FROM	 bodb02.dbo.zzzbettrans z WITH (nolock)
				INNER JOIN bodb02.dbo.bettrans14 b  WITH (nolock)
				ON  b.transid=z.transid
		WHERE	z.transdate between @datelog AND getdate()
			AND z.status <> 'running'
			AND b.winlostdate = @fromdate_
			AND	b.currency <> 20
			and b.matchid > 29 -- exclude transfer, mix parlay, system parlay
			--and (b.bettype < 9 OR b.bettype between 11 and 30 OR b.bettype between 121 and 999)	
			and b.bettype IN (SELECT bettype FROM @tmpBettypes)
	END

	ELSE
	BEGIN

		INSERT INTO #temp(logdate,DetailID,actionid,UserID,Total_Actual,Total_Virtual,Super_Actual,Super_Virtual,Master_Actual,Master_Virtual,Agent_Actual,Agent_Virtual,IBC_Actual,IBC_Virtual)--TicketCNT,NormalCNT,RejectCNT)
		SELECT l.logdate,l.matchid,l.actionid,l.UserID,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Total_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Total_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *spositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Super_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *spositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Super_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *mpositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Master_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *mpositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Master_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *apositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Agent_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) *apositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) Agent_Virtual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * (1-tpositiontaking) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) IBC_Actual,
				sum(abs(case when b.statusID IN (101,102) and z.transdate < l.logdate then 0 else b.stake end) * (1-tpositiontaking) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end) IBC_Virtual
		FROM #tmpUserLog l WITH (nolock)
			INNER JOIN bodb02.dbo.bettrans b WITH (nolock) ON (l.matchid = b.matchid AND b.currency <> 20)
			INNER JOIN @BettypeAction bet ON l.actionID = bet.actionID AND b.bettype= bet.BettypeID
			LEFT JOIN bodb02.dbo.zzzbettrans z WITH (nolock) ON  (b.transid=z.transid)
		WHERE	 b.winlostdate = @fromdate_
				 AND (bet.actionID = 126 AND ( b.custid IN (50057, 879241, 103873, 78761, 851668, 878902)  OR  b.recommend IN (1688156))
					  OR bet.actionID <> 126	
						)
				AND (bet.actionID = 135 AND (b.custid IN (2331, 1077687, 115770, 15523642) )
					 OR bet.actionID <> 135	
					)	
		GROUP BY l.logdate,l.matchid,l.actionid,l.UserID
		ORDER BY l.logdate,l.matchid,l.actionid,l.UserID

		-- Void ticket
		INSERT INTO #temp(logdate,actionid,DetailID,UserID,Total_Actual,Total_Virtual,Super_Actual,Super_Virtual,Master_Actual,Master_Virtual,Agent_Actual,Agent_Virtual,IBC_Actual,IBC_Virtual)--TicketCNT,NormalCNT,RejectCNT)
		SELECT z.transdate,-1,z.transid,b.creator,
			abs(b.stake) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Total_Actual,
			abs(b.stake) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Total_Virtual,
			abs(b.stake) *spositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Super_Actual,
			abs(b.stake) *spositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Super_Virtual,
			abs(b.stake) *mpositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Master_Actual,
			abs(b.stake) *mpositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Master_Virtual,
			abs(b.stake) *apositiontaking * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Agent_Actual,
			abs(b.stake) *apositiontaking * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end Agent_Virtual,
			abs(b.stake) * (1-tpositiontaking) * actualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end IBC_Actual,
			abs(b.stake) * (1-tpositiontaking) * virtualrate * case when b.betteam in ('a','h') then case when abs(b.odds) > 1 then abs(b.odds) else 1 end else 1 end IBC_Virtual
		FROM	 bodb02.dbo.zzzbettrans z WITH (nolock)
				INNER JOIN bodb02.dbo.bettrans b  WITH (nolock)
				ON  b.transid=z.transid
		WHERE	z.transdate between @datelog AND getdate()
			AND z.status <> 'running'
			AND b.winlostdate = @fromdate_
			AND	b.currency <> 20
			and b.matchid > 29 -- exclude transfer, mix parlay, system parlay
			--and (b.bettype < 9 OR b.bettype between 11 and 30 OR b.bettype between 121 and 999)		
			and b.bettype IN (SELECT bettype FROM @tmpBettypes)
	END
	
	UPDATE #temp
	SET	Total_Actual = Total_Actual * -1,
		Total_Virtual = Total_Virtual * -1,
		Super_Actual = Super_Actual * -1,
		Super_Virtual = Super_Virtual  * -1,
		Master_Actual = Master_Actual * -1,
		Master_Virtual = Master_Virtual * -1,
		Agent_Actual = Agent_Actual * -1,
		Agent_Virtual = Agent_Virtual * -1,
		IBC_Actual = IBC_Actual * -1,
		IBC_Virtual =IBC_Virtual  * -1
	WHERE actionid  IN (-1,-2,103,109,110,111,112,126,135,149,150,153,154,166,167,190,191)
	
	SELECT DISTINCT
			c.CustID	
			,c.UserName
	INTO #tmpCust	
	FROM  #temp  t
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON t.UserID = c.CustID
	INSERT INTO #tmpCust(CustID,UserName)
	SELECT 0,''
	
		-- Retrun result
	IF @fromdate_<= (select max(distinct eventdate) from match14 (nolock))
	BEGIN
		SELECT CONVERT(VARCHAR(20), logdate, 120)  [DateTime],
				CASE #temp.actionid WHEN -1 THEN 'Void Settled Bet'  ELSE l.ActionNameEN  END [Action],
				CASE #temp.actionid WHEN -1 THEN convert( nvarchar(50),DetailID) WHEN -2 THEN convert( nvarchar(50),DetailID)  
												ELSE teamname.homename + '-vs-' + teamname.awayname + ' $ ' + convert( nvarchar(50),teamname.matchcode) END [Detail] ,
				  ISNULL(c.username,'')  [Username],
				Total_Actual,Total_Virtual,Super_Actual,Super_Virtual,Master_Actual,Master_Virtual,Agent_Actual,Agent_Virtual,IBC_Actual,IBC_Virtual--TicketCNT,NormalCNT,RejectCNT
		FROM #temp 
			LEFT JOIN DBLOG.bodb_CustomerLog.dbo.LogAction l ON #temp.actionid = l.actionid
			LEFT JOIN ( SELECT m.matchid,m.matchcode,ht.teamname homename,at.teamname awayname
						FROM bodb02.dbo.[match14] m INNER JOIN bodb02.dbo.team ht ON m.homeid = ht.teamid
										INNER JOIN bodb02.dbo.team at ON m.awayid = at.teamid) as teamname
				ON #temp.actionid <> -1 AND #temp.DetailID = teamname.matchid
			INNER JOIN #tmpCust c ON c.custID = #temp.UserID
		ORDER BY logdate DESC	
	END
	ELSE
	BEGIN
		SELECT CONVERT(VARCHAR(20), logdate, 120)  [DateTime],
				CASE #temp.actionid WHEN -1 THEN 'Void Settled Bet'  ELSE l.ActionNameEN  END [Action],
				CASE #temp.actionid WHEN -1 THEN convert( nvarchar(50),DetailID) WHEN -2 THEN convert( nvarchar(50),DetailID)  
												ELSE teamname.homename + '-vs-' + teamname.awayname + ' $ ' + convert( nvarchar(50),teamname.matchcode) END [Detail] ,
				 ISNULL(c.username,'')   [Username],
				Total_Actual,Total_Virtual,Super_Actual,Super_Virtual,Master_Actual,Master_Virtual,Agent_Actual,Agent_Virtual,IBC_Actual,IBC_Virtual--TicketCNT,NormalCNT,RejectCNT
		FROM #temp 
			LEFT JOIN DBLOG.bodb_CustomerLog.dbo.LogAction l ON #temp.actionid = l.actionid
			LEFT JOIN ( SELECT m.matchid,m.matchcode,ht.teamname homename,at.teamname awayname
						FROM bodb02.dbo.[match] m INNER JOIN bodb02.dbo.team ht ON m.homeid = ht.teamid
										INNER JOIN bodb02.dbo.team at ON m.awayid = at.teamid) as teamname
				ON #temp.actionid <> -1 AND #temp.DetailID = teamname.matchid
			INNER JOIN  #tmpCust c ON c.custID = #temp.UserID
		ORDER BY logdate DESC	
	END


	DROP TABLE #temp
	DROP TABLE #tmpUserLog
	DROP TABLE #tmpCust
END
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyTurnover_ChangedDetail] TO [bodbAdminNet] AS [dbo]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyTurnover_ChangedDetail] TO [Dot_Admin] AS [dbo]
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_DailyTurnover_ChangedDetail] TO [vnteam] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_DailyTurnover_ChangedDetail] TO [vnteam] AS [dbo]