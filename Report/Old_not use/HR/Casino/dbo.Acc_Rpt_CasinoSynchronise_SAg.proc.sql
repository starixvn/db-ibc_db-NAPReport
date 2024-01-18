ALTER PROCEDURE [dbo].[Acc_Rpt_CasinoSynchronise_SAg]
	@Custid int = 0,
	@Keyword nvarchar(50) = ''	
AS
--Original: SP Casino Synchronised List
--UPDATED : 03/19/2009@Tuan 
--Task:	Get downline list of Super synchronised.

SET NOCOUNT ON

SELECT 
	custid, username
FROM 
	custinfo AS c WITH (nolock)
WHERE	c.roleid = 3
		AND CASE	WHEN @Custid <> 0 AND c.srecommend = @Custid THEN 1
					WHEN @Custid = 0 THEN 1 ELSE 0 END = 1
	and c.username like '%' + @Keyword + '%'
	and c.SyncCasino=1
order by username


GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CasinoSynchronise_SAg] TO [bodbAdminNet]