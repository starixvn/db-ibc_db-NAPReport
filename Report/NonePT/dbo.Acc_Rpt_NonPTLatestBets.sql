
ALTER PROCEDURE [dbo].[Acc_Rpt_NonPTLatestBets]  
 @Username varchar(30) = NULL,
 @Bettypes varchar(50) = '',	
 @Currency int = 0,
 @FromStake int = 0,
 @ToStake int = 0,
 @PageSize int=50,
 @PageIndex int=1,
 @TotalPages int=0 output
 
AS  

/*
	Created by: Henry
	Date: 2010-08-05
	Task: Get Running/Waiting Non PT Bets
	DB: DB06.bodb02 

	
	Revisions:
		- 20110413@Amy: Change function to get odds value and odds type
		- 20110516@Lukas: re-arrange bettype
		
		
*/ 

SET NOCOUNT ON  

Declare @Data TABLE (
	Username nvarchar(50),
	bettype smallint,
	transid bigint, 
	refno bigint, 
	matchcode nvarchar(50),
	race nvarchar(20),
	eventdate smalldatetime,
	homeid int, 
	awayid int, 
	hdp1 smallmoney, 
	hdp2 smallmoney, 
	odds smallmoney,
	OddsType tinyint,
	stake money,
	transdate datetime,
	betteam nvarchar(10),
	liveindicator bit,
	custid int,
	leagueid int, 
	sporttype smallint, 
	ip nvarchar(15), 
	matchid int,
	isNeutral bit,
	CurrencyName nvarchar(50),
	livehomescore smallint, 
	liveawayscore smallint, 
	finalhomescore int, 
	finalawayscore int,
	isShowOTExRate bit, --if true then we will use virtualrate instead of currency for Open Tote
	virtualrate float,
	status nvarchar(50)
)
Declare @custid int
if @Username IS NOT NULL  
BEGIN
	Exec @custid = f_GetCustIDFromUsername @username 
	IF @custid IS NULL
	RETURN
END

IF @Bettypes = '' --ALL
BEGIN
	--Sport Book
		INSERT INTO @Data
		select 
			b.Username,
			b.bettype,
			b.transid,
			b.refno,
			m.matchcode,
			'' as race,
			'' as eventdate,
			m.homeid,
			m.awayid,
			b.hdp1,
			b.hdp2,
			dbo.f_ShowOddsByBettype(b.bettype,b.oddstype) as OddsType, 
			dbo.f_GetOddsByBettype(b.Odds,b.bettype,b.oddstype) as Odds,
			stake,
			b.transdate,
			dbo.f_GetChoice(b.betteam, b.bettype,'E') betteam, 
			b.liveindicator,     
			b.custid,
			m.leagueid,
			m.sporttype,
			b.ip,
			b.matchid,
			isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
			b.CurrencyName,
			b.livehomescore, 
			b.liveawayscore, 
			m.finalhomescore, 
			m.finalawayscore, 
			0,
			0,
			b.status
		from 
			bettrans as b with (nolock) inner join match as m with (nolock) on b.matchid = m.matchid
		where	
			b.bettype < 19001 and
			b.ruben = 0 and
			b.statusID IN (0,1) and
			b.tpositiontaking = 0 and
			(@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency)) and
			(@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid)) 
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
				
				 



				
		
		--Mix Parlay
		INSERT INTO @Data
		select 
			 b.Username,
			 9 bettype,   
			 b.transid,   
			 b.refno,
			 '' matchcode,  
			 '' as race,
			 '' as eventdate,
			 0 as homeid,   
			 0 as awayid,  
			 b.hdp1,
			 b.hdp2,
			 b.odds,   
			 '' OddsType,   
			 b.stake,   
			 b.transdate transdate,   
			 b.betteam,   
			 0 liveindicator,     
			 b.custid, 
			 0 as leagueid,  
			 0 as sporttype, 
			 b.ip,
			 0 matchid,	
			 CONVERT(BIT,0) as IsNeutral,
			 b.CurrencyName,
			 b.livehomescore,
			 b.liveawayscore,
			 0 as finalhomescore, 
			 0 as finalawayscore, 
			 0,
			 0,
			 b.status
		from	
			bettrans as b with (nolock)   
		where	
			matchid = 9
			and bettype = 9  
			and b.ruben = 0
			and b.statusID IN (0,1) 
			and b.tpositiontaking = 0
			and (@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid))
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
				
				 
		 
		
		-- Outright
		INSERT INTO @Data
		select 
			b.Username,
			b.bettype,
			b.transid,   
			b.refno,
			odds.matchcode, 
			odds.groupmatch as race,
			odds.eventdate as eventdate, 
			0 as homeid,
			odds.teamid as awayid,
			b.hdp1,
			b.hdp2,
			b.odds,   
			'' OddsType,  
			b.stake,   
			b.transdate transdate,   
			b.betteam,   
			b.liveindicator,    
			b.custid,
			odds.leagueid,
			l.sporttype,
			b.ip ,
			b.matchid,
			CONVERT(BIT,0) as IsNeutral,
			b.CurrencyName,
			b.livehomescore,
			b.liveawayscore,
			0 as finalhomescore, 
			0 as finalawayscore,
			0,
			0,
			b.status
		from	
			bettrans as b with (nolock)   
			inner join outright as odds with (nolock) on b.matchid=odds.orid   
			inner join league l with (nolock) on odds.leagueid=l.leagueid     
		where 
			b.bettype = 10
			and b.ruben = 0
			and b.statusID IN (0,1)
			and b.tpositiontaking = 0
			and (@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid))
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
		 
		  
			
		-- HR		
		INSERT INTO @Data 
		select 
			b.Username,
			b.bettype,
			b.transid,   
			b.refno,
			odds.matchcode, 
			odds.groupmatch as race,
			odds.eventdate as eventdate,
			0 as homeid,
			odds.teamid as awayid,
			b.hdp1,
			b.hdp2,
			b.odds,   
			'' OddsType,   
			b.stake,   
			b.transdate transdate,   
			b.betteam,   
			b.liveindicator,   
			b.custid, 
			odds.leagueid,
			l.sporttype,
			b.ip ,
			b.matchid,
			CONVERT(BIT,0) as IsNeutral,
			b.CurrencyName,
			b.livehomescore,
			b.liveawayscore,
			0 as finalhomescore, 
			0 as finalawayscore,
			--isnumeric(odds.programID),
			CONVERT(BIT,1) AS isShowOTExRate,
			b.virtualrate,
			b.status
		from	
			bettrans as b with (nolock)   
			inner join outright as odds with (nolock) on b.matchid=odds.orid   
			inner join league l with (nolock) on odds.leagueid=l.leagueid    
		where	
			b.bettype in (31,32,33,41,42,43) 
			and b.ruben = 0
			and b.statusID IN (0,1)
			and b.tpositiontaking = 0
			and (@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid)) 	
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
				 
END
ELSE
BEGIN
	Declare @BettypeTemp TABLE (bettype smallint)
	INSERT INTO @BettypeTemp
	SELECT distinct convert(int,val) FROM dbo.strSplit(@Bettypes,'^')
	
	IF @@ROWCOUNT = 0
	RETURN

	--HR
	IF EXISTS (SELECT TOP 1 1 FROM @BettypeTemp WHERE bettype IN (31,32,33,41,42,43))
	BEGIN
		INSERT INTO @Data 
		select 
			b.Username,
			b.bettype,
			b.transid,   
			b.refno,
			odds.matchcode, 
			odds.groupmatch as race,
			odds.eventdate as eventdate,
			0 as homeid,
			odds.teamid as awayid,
			b.hdp1,
			b.hdp2,
			b.odds,   
			'' OddsType,   
			b.stake,   
			b.transdate transdate,   
			b.betteam,   
			b.liveindicator,    
			b.custid, 
			odds.leagueid,
			l.sporttype,
			b.ip ,
			b.matchid,
			CONVERT(BIT,0) as IsNeutral,
			b.CurrencyName,
			b.livehomescore,
			b.liveawayscore,
			0 as finalhomescore, 
			0 as finalawayscore,  
			--isnumeric(odds.programID),
			CONVERT(BIT,1) AS isShowOTExRate,
			b.virtualrate,
			b.status
		from	
			bettrans as b with (nolock)   
			inner join outright as odds with (nolock) on b.matchid=odds.orid   
			inner join league l with (nolock) on odds.leagueid=l.leagueid    
		where	
			b.bettype IN (SELECT bettype FROM @BettypeTemp WHERE bettype IN (31,32,33,41,42,43))
			and b.ruben = 0
			and b.statusID IN (0,1)
			and b.tpositiontaking = 0
			and (@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid)) 	
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
				 
	END
	--Outright
	IF EXISTS (SELECT 1 FROM @BettypeTemp WHERE bettype = 10)
	BEGIN
		INSERT INTO @Data
		select 
			b.Username,
			b.bettype,
			b.transid,   
			b.refno,
			odds.matchcode, 
			odds.groupmatch as race,
			odds.eventdate as eventdate,
			0 as homeid,
			odds.teamid as awayid,
			b.hdp1,
			b.hdp2,
			b.odds,   
			'' OddsType,  
			b.stake,   
			b.transdate transdate,   
			b.betteam,   
			b.liveindicator,      
			b.custid,
			odds.leagueid,
			l.sporttype,
			b.ip ,
			b.matchid,
			CONVERT(BIT,0) as IsNeutral,
			b.CurrencyName,
			b.livehomescore,
			b.liveawayscore,
			0 as finalhomescore, 
			0 as finalawayscore,  
			0,
			0,
			b.status
		from	
			bettrans as b with (nolock)   
			inner join outright as odds with (nolock) on b.matchid=odds.orid   
			inner join league l with (nolock) on odds.leagueid=l.leagueid     
		where 
			b.bettype = 10
			and b.ruben = 0
			and b.statusID IN (0,1) 
			and b.tpositiontaking = 0 
			and (@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid))
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
		
	END
	--Mix Parlay
	IF EXISTS (SELECT 1 FROM @BettypeTemp WHERE bettype = 9)
	BEGIN
		INSERT INTO @Data
		select 
			 b.Username,
			 9 bettype,   
			 b.transid,   
			 b.refno,
			 '' matchcode,  
			 '' as race,
			 '' as eventdate,
			 0 as homeid,   
			 0 as awayid,  
			 b.hdp1,
			 b.hdp2,
			 b.odds,   
			 '' OddsType,   
			 b.stake,   
			 b.transdate transdate,   
			 b.betteam,   
			 0 liveindicator,    
			 b.custid, 
			 0 as leagueid,  
			 0 as sporttype, 
			 b.ip,
			 0 matchid,	
			 CONVERT(BIT,0) as IsNeutral,
			 b.CurrencyName,
			 b.livehomescore,
			 b.liveawayscore,
			 0 as finalhomescore, 
			 0 as finalawayscore,  
			 0,
			 0,
			 b.status
		from	
			bettrans as b with (nolock)   
		where	 
			matchid = 9
			and bettype = 9  
			and b.ruben = 0 
			and b.statusID IN (0,1) 
			and b.tpositiontaking = 0 
			and (@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid)) 
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
	END
	--SportsBook
	IF EXISTS (SELECT TOP 1 1 FROM @BettypeTemp WHERE bettype NOT IN (9,10,31,32,33,41,42,43)) 
	BEGIN
		INSERT INTO @Data
		select 
			b.Username,
			b.bettype,
			b.transid,
			b.refno,
			m.matchcode,
			'' as race,
			'' as eventdate,
			m.homeid,
			m.awayid,
			b.hdp1,
			b.hdp2,
			dbo.f_ShowOddsByBettype(b.bettype,b.oddstype) as OddsType, 
			dbo.f_GetOddsByBettype(b.Odds,b.bettype,b.oddstype) as Odds,
			stake,
			b.transdate,
			dbo.f_GetChoice(b.betteam, b.bettype,'E') betteam, 
			b.liveindicator,    
			b.custid,
			m.leagueid,
			m.sporttype,
			b.ip,
			b.matchid,
			isnull(m.isNeutral, CONVERT(BIT,0)) as IsNeutral,
			b.CurrencyName,
			b.livehomescore, 
			b.liveawayscore, 
			m.finalhomescore, 
			m.finalawayscore, 
			0,
			0,
			b.status
		from 
			bettrans as b with (nolock) inner join match as m with (nolock) on b.matchid = m.matchid
		where	 
			b.bettype IN (SELECT bettype FROM @BettypeTemp WHERE bettype NOT IN (9,10,31,32,33,41,42,43) AND bettype < 19001 ) and
			b.ruben = 0 and
			b.statusID IN (0,1) and
			b.tpositiontaking = 0 and
			(@Currency = 0 OR  (@Currency <> 0 AND b.currency = @Currency))
			and (@Username IS NULL OR  (@Username IS NOT NULL AND b.custid = @Custid))
			and (@ToStake=0  OR (@ToStake > 0 AND @ToStake>= @FromStake AND stake >= @FromStake and stake <= @ToStake )  )
				 	
	END
 END 

DECLARE @RowCount int, @RowStart int, @RowEnd int  
SELECT @PageIndex = @PageIndex - 1, @RowStart = @PageSize * @PageIndex + 1, @RowEnd = @RowStart + @PageSize - 1 




IF @TotalPages = 0 
	BEGIN
		SELECT 
			@TotalPages = count(c.transid),
			@TotalPages=@TotalPages/@PageSize + case when @TotalPages%@PageSize > 0 then 1 else 0 end
		FROM 
		(
			SELECT * FROM @Data
		) as c
		
	END

	SELECT 
		*
	FROM
	(
		SELECT 
			ROW_NUMBER() over (order by transid desc) as RowNum,
			*
		 FROM @Data
		
	) as c
	WHERE RowNum between @RowStart and @RowEnd


 
  
GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NonPTLatestBets] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonPTLatestBets] TO [vnteam] 