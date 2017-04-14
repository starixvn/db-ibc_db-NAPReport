
ALTER PROCEDURE [dbo].[Acc_CheckDuplicateTickets]	
	@date datetime,
	@ShowTime bit = 0
with recompile
AS
/*
Created: 
Task : 
DB: DBACC/bodb02
Original: 

Revisions:
	- 20131227@Kathy: Add more Betdaq's customer: BDUS016, BDUS01 [Redmine:#9765]
	- 20140227@Dan: ignore refno when checking, it causes the report did not detect mix parlay case.
	
Param's Explanation:

*/

-- DB06.bodb02
SET NOCOUNT ON

IF @@servername = 'DWDBG1S'
begin
	select * from vtest
end
else
begin
	declare @_date datetime
	select @_date = @date

	IF @ShowTime = 0
	BEGIN
		;WITH B as (
			select custid, odds, stake, balance, status,bettype,winlostdate, username,
					min(transid) refno1, max(transid) refno2, 
					min(transdate) bettime1,max(transdate) bettime2, 
					datediff(ms,min(transdate),max(transdate)) timediff
			from bettrans with(nolock)
			where matchid > 0
				and bettype < 19000
				and custid not in (50057,879241,103873, 851668, 878902) --betdaq
				AND custid NOT IN (1077687) -- Betfair
				and recommend not in (11196380) -- foobet
				and DATEADD(dd, DATEDIFF(dd, 0, transdate), 0) = @_date
				and winlostdate >= @_date
				and custid > 0
				and recommend <> 5707545 -- exclude members under BARM
				and currency <> 20
			group by custid, odds, stake, balance, status, bettype,winlostdate, username, matchid, betteam --refno
			having count(*) > 1 and datediff(ms,min(transdate),max(transdate))<1000
		)
		SELECT username, custid, typenamee,winlostdate, balance, stake, odds, status,
			refno1, refno2, bettime1, bettime2, timediff
		FROM B b
			INNER JOIN bettype bt with(nolock) on b.bettype = bt.typeid	
		ORDER BY refno1 desc
	END
	ELSE
	BEGIN

		;WITH B as (
			select custid, odds, stake, balance, status,bettype,winlostdate, username,
					min(transid) refno1, max(transid) refno2, 
					min(transdate) bettime1,max(transdate) bettime2, 
					datediff(ms,min(transdate),max(transdate)) timediff
			from bettrans with(nolock)
			where matchid > 0
				and bettype < 19000
				and custid not in (50057,879241,103873, 851668, 878902) --betdaq
				AND custid NOT IN (1077687) -- Betfair
				and recommend not in (11196380) -- foobet
				and DATEADD(dd, DATEDIFF(dd, 0, transdate), 0) = @_date
				and winlostdate >= @_date
				and custid > 0
				and recommend <> 5707545 -- exclude members under BARM
				and currency <> 20
			group by custid, odds, stake, balance, status, bettype,winlostdate, username, matchid, betteam --refno
			having count(*) > 1 and datediff(ms,min(transdate),max(transdate))<1000
		)
		SELECT username, custid, typenamee,winlostdate, balance, stake, odds, status,
			refno1, refno2, bettime1, bettime2, timediff, 
			CAST( 0 as int) ProcessTime1, CAST( 0 as int) ProcessTime2, 
			CAST('' as nvarchar(100)) Called1, CAST('' as nvarchar(100)) Called2,
			CAST('' as nvarchar(500)) Doing1,
			CAST('' as nvarchar(500)) Doing2
		INTO #Result
		FROM B b
			INNER JOIN bettype bt with(nolock) on b.bettype = bt.typeid	
		ORDER BY refno1 desc
		
		UPDATE #Result
		SET Doing1 = ul.doing
		FROM dbo.UserLog ul with (nolock)
		WHERE #Result.custid = ul.userid
			AND ul.doing LIKE '%' + CAST(refno1 as varchar(50)) + '%'
			
		UPDATE #Result
		SET Doing2 = ul.doing
		FROM dbo.UserLog ul with (nolock)
		WHERE #Result.custid = ul.userid
			AND ul.doing LIKE '%' + CAST(refno2 as varchar(50)) + '%'

		Declare @a1 int, @b1 int, @c1 int, @d1 int
		Declare @a2 int, @b2 int, @c2 int, @d2 int


		UPDATE #Result
		SET @a1 = CHARINDEX('ms)', Doing1),
			@b1 = CHARINDEX('(', Doing1, @a1 - 10),
			ProcessTime1 = CASE WHEN @a1 + @b1 > 0 THEN SUBSTRING(Doing1, @b1+1, @a1-@b1-2) ELSE ProcessTime1 END,
			@c1 = CHARINDEX('(Call', Doing1),
			@d1 = CHARINDEX(')', Doing1, @c1),
			Called1 = CASE WHEN @c1 + @d1 > 0 THEN SUBSTRING(Doing1, @c1+1, @d1-@c1-1) ELSE Called1 END,

			@a2 = CHARINDEX('ms)', Doing2),
			@b2 = CHARINDEX('(', Doing2, @a2 - 10),
			ProcessTime2 = CASE WHEN @a2 + @b2 > 0 THEN SUBSTRING(Doing2, @b2+1, @a2-@b2-2) ELSE ProcessTime2 END,
			@c2 = CHARINDEX('(Call', Doing2),
			@d2 = CHARINDEX(')', Doing2, @c2),
			Called2 = CASE WHEN @c2 + @d2 > 0 THEN SUBSTRING(Doing2, @c2+1, @d2-@c2-1) ELSE Called2 END

		SELECT username, custid, typenamee,winlostdate, balance, stake, odds, status,
			refno1, refno2, bettime1, bettime2, timediff, 
			ProcessTime1, ProcessTime2, Called1, Called2,
			(select betfrom from bettrans with (nolock) where transid = r.refno1) betfrom1,
			(select betfrom from bettrans with (nolock) where transid = r.refno2) betfrom2,
			(select bettype from bettrans with (nolock) where transid = r.refno1) bettype
		FROM #Result r
	END
end


GO
GRANT EXECUTE ON [dbo].[Acc_CheckDuplicateTickets] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_CheckDuplicateTickets] TO [vnteam]