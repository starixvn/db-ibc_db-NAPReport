ALTER PROCEDURE [dbo].[Acc_Rpt_NonePTMemSummary]
    @Username VARCHAR(50) = '',
    @PageNum INT = 1,
	@PageSize INT = 1000,
    @TotalPages INT OUTPUT,
    @ErrCode INT OUTPUT,
    @ErrMsg VARCHAR(200) OUTPUT
AS  

/*
Created: Khoa@20100517
Task : List of members whom Super/ Master/ Agent doesn't take Position Taking.

DB: DB06.bodb02
Original:

Revisions:
	- 20100523@viet: enhance the performance, reduce load for database.
	- 20100605@khoa: enhance the performance, reduce load for database.
	- 20100608@Jamie: Enhance queries and use the statusID instead of status and exclude 'Refund'

Param's Explanation:
• @Username:
            - Username's Super/Master/Agent/Member
            - If don't input username it means will be listed out all members
*/

SET NOCOUNT ON

CREATE TABLE #Data(custid int primary key, username varchar(30), recommend int, mrecommend int, srecommend int, BetCount INT, RunningTOTotal MONEY, TOTotal MONEY)

DECLARE @CustId INT, @RoleId INT
DECLARE @TotalRows INT
SELECT @CustId = 0, @RoleId = 0

DECLARE @Tmp_Exclude AS TABLE (custid INT)
INSERT INTO @Tmp_Exclude
select s.custid
from custinfo s with(nolock)
where (s.username like '3rdSuper%' or  
        s.username like '12BETACCSuper%' or
        s.username like 'MS88ACCSuper%' or
        s.username like 'AB88ACCSuper%' or
        s.username like 'ALogACCSuper%' or
        s.currency=20)
		AND roleid = 4 

IF @Username <> ''
BEGIN	
	SELECT @CustId = custid, @RoleId = RoleId
	FROM custinfo (nolock) 
	WHERE Username = @UserName
		AND srecommend not in (select custid from @Tmp_Exclude)

	IF @CustID = 0 or @RoleID > 4
    BEGIN
        SELECT @ErrCode = 100, @ErrMsg = 'Invalid Username'
        RETURN
    END	

	INSERT INTO #Data(custid, username, recommend, mrecommend, srecommend, BetCount, RunningTOTotal, TOTotal)
	SELECT DISTINCT ci.custid, ci.username, recommend, mrecommend, srecommend, BetCount, TotalTORunning, TotalTOAll
    FROM custsetting cs (nolock)
        INNER join
			(	select custid, username, recommend, mrecommend, srecommend 
				FROM custinfo (nolock)
				WHERE
					CASE
						WHEN @RoleId = 4 THEN srecommend
						WHEN @RoleId = 3 THEN mrecommend
						WHEN @RoleId = 2 THEN recommend					
						ELSE CustId
					END = @CustId
				AND RoleId=1
			) ci on cs.custid = ci.custid
		left JOIN (
				SELECT b.custid, COUNT(1) AS BetCount, SUM(stake) AS TotalTOAll,
					SUM(CASE WHEN ruben=0 THEN stake ELSE 0 END) AS TotalTORunning
				FROM (
						select custid, stake, ruben, matchid, bettype, tpositiontaking, statusid, winlostdate from bettrans with(nolock)
						union all
						select custid, stake, ruben, matchid, bettype, tpositiontaking, statusid, winlostdate from bettrans14 with(nolock)
					) b			
				WHERE matchid>200 				
					and bettype < 31
					and tpositiontaking=0 
					and statusid not in (102,101,103)
					and winlostdate = winlostdate			
				GROUP BY b.custid 				
			) b on ci.custid = b.custid 
    WHERE cs.bettype in (1,3,7,8) and cs.sporttype = 1
        and ((cs.apositiontaking + cs.mpositiontaking + cs.spositiontaking) = 0
			OR (cs.alivepositiontaking + cs.mlivepositiontaking + cs.slivepositiontaking) = 0)
	order by BetCount desc, TotalTOAll desc
END
ELSE
BEGIN
	INSERT INTO #Data(custid, username, recommend, mrecommend, srecommend, BetCount, RunningTOTotal, TOTotal)
    SELECT DISTINCT ci.custid, ci.username, ci.recommend, ci.mrecommend, ci.srecommend, BetCount, TotalTORunning, TotalTOAll
    FROM custsetting cs (nolock)
		INNER JOIN CustInfo ci with(nolock) on cs.custid = ci.custid        
		left JOIN (
				SELECT b.custid, COUNT(1) AS BetCount, SUM(stake) AS TotalTOAll,
					SUM(CASE WHEN ruben=0 THEN stake ELSE 0 END) AS TotalTORunning
				FROM (
						select custid, stake, ruben, matchid, bettype, tpositiontaking, statusid, winlostdate from bettrans with(nolock)
						union all
						select custid, stake, ruben, matchid, bettype, tpositiontaking, statusid, winlostdate from bettrans14 with(nolock)
					) b			
				WHERE matchid>200 				
					and bettype < 31
					and tpositiontaking=0 
					and statusid not in (101,102,103) 	
					and winlostdate = winlostdate			
				GROUP BY b.custid 				
			) b on ci.custid = b.custid 
    WHERE cs.bettype in (1,3,7,8) 
		and cs.sporttype=1
        and ((cs.apositiontaking + cs.mpositiontaking + cs.spositiontaking) = 0
                OR (cs.alivepositiontaking + cs.mlivepositiontaking + cs.slivepositiontaking) = 0)	
		and ci.RoleID =1
		and ci.custid not in (
								select c.custid 
								from @Tmp_Exclude s
									Inner join custinfo c with(nolock) on s.custid = c.srecommend
								where c.roleid = 1
							)
	order by BetCount desc, TotalTOAll desc
END

SELECT @TotalRows = COUNT(1) FROM #data WITH (NOLOCK)
SELECT @TotalPages = @TotalRows/@Pagesize
IF @TotalRows%@Pagesize>0
    SELECT @TotalPages = @TotalPages+1

IF @PageNum<=0 or @PageNum>@TotalPages
    SELECT @PageNum = 1

SELECT s.currency, s.username Super, m.username Master, a.username Agent, d.Username Member, d.BetCount, d.RunningTOTotal, d.TOTotal
FROM (
	SELECT ROW_NUMBER() OVER(ORDER BY BetCount DESC, RunningTOTotal DESC,  TOTotal DESC) AS RowNum, * FROM #data WITH (NOLOCK)
) d
	INNER JOIN Custinfo a on d.recommend = a.custid
	INNER JOIN CustInfo m on d.mrecommend = m.custid
	INNER JOIN CustInfo s on d.srecommend = s.custid
WHERE RowNum BETWEEN (@PageNum - 1) * @PageSize + 1
	AND @PageNum * @PageSize
ORDER BY BetCount DESC, TOTotal DESC

SELECT @TotalPages TotalPages
DROP TABLE #Data


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_NonePTMemSummary] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_NonePTMemSummary] TO [vnteam]