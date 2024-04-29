
/*<info serverAlias="DBRPT-bodb_Report" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_Report
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_BalanceBreakdown_Daily]
@PageIndex  INT = 0
, @PageSize INT = 1048576
AS
/*
    Created	: 20240426@Jaden
	Task	: Balance report of customers, for Finance team to backup (#204276)
              Daily runs
	DB		: DBRPT/bodb_Report
	
	Revision:		
		20240426@Jaden: Initial (#204276)

	Param's Explanation:
*/
BEGIN
    SELECT s.username                                          AS [Super]
         , ISNULL(m.username, '-')                             AS [Master]
         , ISNULL(a.username, '-')                             AS [Agent]
         , CASE WHEN b.custid <> b.recommend
                 AND b.custid <> b.mrecommend
                 AND b.custid <> b.srecommend THEN c.username
               ELSE '-'
           END                                                 AS [Member]
         , ISNULL(e.Currency, e1.Currency)                     AS [Currency]
         , SuperAmt
         , MasterAmt
         , AgentAmt
         , MemberAmt
         , SuperAmtRM
         , MasterAmtRM
         , AgentAmtRM
         , MemberAmtRM
         , SuperAmt + MasterAmt + AgentAmt + MemberAmt         AS Total
         , SuperAmtRM + MasterAmtRM + AgentAmtRM + MemberAmtRM AS TotalRM
    FROM dbo.AutomailBalanceBreakdown_Daily b WITH (NOLOCK)
    LEFT JOIN bodb02.dbo.vw_Customer        s WITH (NOLOCK) ON b.srecommend = s.custid
    LEFT JOIN bodb02.dbo.vw_Customer        m WITH (NOLOCK) ON b.mrecommend = m.custid
    LEFT JOIN bodb02.dbo.vw_Customer        a WITH (NOLOCK) ON b.recommend = a.custid
    LEFT JOIN bodb02.dbo.vw_Customer        c WITH (NOLOCK) ON b.custid = c.custid
    LEFT JOIN bodb02.dbo.Exchange           e WITH (NOLOCK) ON s.currency = e.exchangeid
    LEFT JOIN bodb02.dbo.Exchange           e1 WITH (NOLOCK) ON c.currency = e1.exchangeid
    ORDER BY b.[srecommend]
           , b.[mrecommend]
           , b.[recommend]
           , b.[custid] 
    OFFSET @PageIndex * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE)
END