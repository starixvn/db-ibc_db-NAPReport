/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.Acc_Rpt_AbnormalBetAutoMail_Daily_SelectMember_By_Headline 
	@GroupName    VARCHAR(50) = 'INDOWIN'
AS
    BEGIN
/*
	Creator: Robert
	Date: 2020-03-12
	DB: DBACC.bodb02
	Task: [Special Delete] - Implement Daily Auto Mail for Abnormal Bets
	Revisions:				
		- 20200312@Robert: NAP Report - Daily Abnormal Bet Report for Headline - [130183]

	Param's Explanation:	 
*/

	   SET NOCOUNT ON;

	   WITH Cust_CTE(Custid
				, SuperId)
		   AS (SELECT c.custid
				  , s.custid AS SuperId
			  FROM dbo.Acc_CustGroup AS c
				 LEFT JOIN dbo.Customer AS s WITH(NOLOCK) ON s.srecommend = c.custid
			  WHERE c.GroupName = @GroupName)
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
			  INNER JOIN dbo.Customer AS a ON a.custid = c.recommend;
    END;