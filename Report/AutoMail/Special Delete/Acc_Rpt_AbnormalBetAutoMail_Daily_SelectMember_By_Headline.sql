/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_SelectMember_By_Headline 
	@GroupId    INT = 583
AS
/*
	Creator: Robert
	Date: 2020-03-12
	DB: DBACC.bodb02
	Task: [Special Delete] - Implement Daily Auto Mail for Abnormal Bets
	Revisions:				
		- 20200312@Robert: NAP Report - Daily Abnormal Bet Report for Headline - [130183]

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   DECLARE @TmpMember TABLE(
		   CustId      INT
		 , MemberId    INT
		 , Super       VARCHAR(50)
		 , Master      VARCHAR(50)
		 , Agent       VARCHAR(50));

	   WITH Cust_CTE(Custid
				, SuperId
				, MasterId
				, AgentId
				, MemberId)
		   AS (SELECT c.custid
				  , s.custid AS SuperId
				  , m.custid AS MasterId
				  , a.custid AS AgentId
				  , mem.custid AS MemberId
			  FROM dbo.CustAccount AS c
				 LEFT JOIN dbo.Customer AS s WITH(NOLOCK) ON s.srecommend = c.custid
													AND s.roleid = 4
				 LEFT JOIN dbo.Customer AS m WITH(NOLOCK) ON m.mrecommend = c.custid
													AND m.roleid = 3
				 LEFT JOIN dbo.Customer AS a WITH(NOLOCK) ON a.recommend = c.custid
													AND a.roleid = 2
				 LEFT JOIN dbo.Customer AS mem WITH(NOLOCK) ON mem.custid = c.custid
													  AND mem.roleid = 1
			  WHERE groupID = CASE
							  WHEN @GroupId = 0
							  THEN groupID
							  ELSE @GroupId
						   END
				   AND c.custid > 0)

		   INSERT INTO @TmpMember(CustId
						    , MemberId
						    , Super
						    , Master
						    , Agent)
				(
				    SELECT cte.Custid
					    , c.custid AS MemberId
					    , s.username AS Super
					    , m.username AS Master
					    , a.username AS Agent
				    FROM Cust_CTE AS cte
					   INNER JOIN dbo.Customer AS c ON c.srecommend = cte.SuperId
												AND c.roleid = 1
					   INNER JOIN dbo.Customer AS s ON s.custid = c.srecommend
												AND s.roleid = 4
					   INNER JOIN dbo.Customer AS m ON m.custid = c.mrecommend
												AND m.roleid = 3
					   INNER JOIN dbo.Customer AS a ON a.custid = c.recommend
												AND a.roleid = 2
				    UNION ALL
				    SELECT cte.Custid
					    , c.custid AS MemberId
					    , s.username AS Super
					    , m.username AS Master
					    , a.username AS Agent
				    FROM Cust_CTE AS cte
					   INNER JOIN dbo.Customer AS c ON c.mrecommend = cte.MasterId
												AND c.roleid = 1
					   INNER JOIN dbo.Customer AS s ON s.custid = c.srecommend
												AND s.roleid = 4
					   INNER JOIN dbo.Customer AS m ON m.custid = c.mrecommend
												AND m.roleid = 3
					   INNER JOIN dbo.Customer AS a ON a.custid = c.recommend
												AND a.roleid = 2
				    UNION ALL
				    SELECT cte.Custid
					    , c.custid AS MemberId
					    , s.username AS Super
					    , m.username AS Master
					    , a.username AS Agent
				    FROM Cust_CTE AS cte
					   INNER JOIN dbo.Customer AS c ON c.recommend = cte.AgentId
												AND c.roleid = 1
					   INNER JOIN dbo.Customer AS s ON s.custid = c.srecommend
												AND s.roleid = 4
					   INNER JOIN dbo.Customer AS m ON m.custid = c.mrecommend
												AND m.roleid = 3
					   INNER JOIN dbo.Customer AS a ON a.custid = c.recommend
												AND a.roleid = 2
				    UNION ALL
				    SELECT cte.Custid
					    , c.custid AS MemberId
					    , s.username AS Super
					    , m.username AS Master
					    , a.username AS Agent
				    FROM Cust_CTE AS cte
					   INNER JOIN dbo.Customer AS c ON c.custid = cte.MemberId
					   INNER JOIN dbo.Customer AS s ON s.custid = c.srecommend
												AND s.roleid = 4
					   INNER JOIN dbo.Customer AS m ON m.custid = c.mrecommend
												AND m.roleid = 3
					   INNER JOIN dbo.Customer AS a ON a.custid = c.recommend
												AND a.roleid = 2
				);

	   SELECT CustId
		   , MemberId
		   , Super
		   , Master
		   , Agent
	   FROM @TmpMember;
    END;