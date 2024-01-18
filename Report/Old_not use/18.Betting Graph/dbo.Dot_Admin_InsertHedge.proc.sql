

ALTER PROCEDURE [dbo].[Dot_Admin_InsertHedge]
	@matchid int,
	@oddsid int,
	@bettype smallint,
	@odds smallmoney,
	@hdp1 smallmoney,
	@hdp2 smallmoney,
	@betteam nvarchar(1),
	@stake money,
	@liveindicator bit,
	@livehomescore smallint,
	@liveawayscore smallint,
	@custid int,
	@creator int,
	@Remark nvarchar(200)
AS
/*  
Creator : 
Created : 
Task : 
Revision:
	- 20110516@Lukas: re-arrange bettype
*/ 

	SELECT @matchid = matchid FROM odds WHERE oddsid = @oddsid

	INSERT INTO dbo.BetHedgeRecord
	(matchid, oddsid, bettype, odds, hdp1, hdp2, betteam,
	stake, liveindicator, livehomescore, liveawayscore, 
	custid, creator, Remark)
	VALUES
	(@matchid, @oddsid, @bettype, @odds, @hdp1, @hdp2, @betteam,
	@stake, @liveindicator, @livehomescore, @liveawayscore,
	@custid, @creator, @Remark)

	Declare @LogData nvarchar(300)
	SELECT @LogData = 'Hedge Record ID:m-o:' + CAST(@matchid as nvarchar(20)) + '-' + CAST(@oddsid as nvarchar(20))
		+ ' bt:' + CAST(@bettype as nvarchar(10))
		+ ' odds:' + CAST(CAST(@odds as float) as nvarchar(20)) + '(' + @betteam + ')'
		+ ' hdp:' + CAST(@hdp1 as nvarchar(10)) + '-' + CAST(@hdp2 as nvarchar(10))
		+ ' stake:' + CAST(CAST(@stake as float) as nvarchar(20))
		+ ' live-h-a:' + CAST(@liveindicator as nvarchar(10)) + '-' + CAST(@livehomescore as nvarchar(10)) + '-' + CAST(@liveawayscore as nvarchar(10))
	EXEC dbo.LogFile @creator, @LogData

GO
GRANT EXECUTE ON [dbo].[Dot_Admin_InsertHedge] TO [Dot_Admin]
GO
GRANT EXECUTE ON [dbo].[Dot_Admin_InsertHedge] TO [Dot_Member]
