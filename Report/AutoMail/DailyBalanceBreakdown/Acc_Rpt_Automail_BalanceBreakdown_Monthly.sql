
/*<info serverAlias="DBRPT-bodb_Report" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_Report
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_BalanceBreakdown_Monthly]
@PageIndex INT           = 0
, @PageSize  INT           = 1048576
AS
/*
    Created	: 20240426@Jaden
	Task	: Balance report of customers, for Finance team to backup (#204276)
              Monthly runs (at 4th), query Monthly table (which is populated via Acc_Rpt_Automail_BalanceBreakdown_Job)
	DB		: DBRPT/bodb_Report
	
	Revision:		
		20240426@Jaden: Initial (#204276)

	Param's Explanation:
*/
BEGIN
    SELECT [Super]
         , [Master]
         , [Agent]
         , [Member]
         , [Currency]
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
    FROM dbo.AutomailBalanceBreakdown_Monthly b WITH (NOLOCK)
    ORDER BY [RowNumber] 
    OFFSET @PageIndex * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE)
END