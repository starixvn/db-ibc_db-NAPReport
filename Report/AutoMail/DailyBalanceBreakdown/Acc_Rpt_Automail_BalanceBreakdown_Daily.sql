
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
    FROM dbo.AutomailBalanceBreakdown_Daily b WITH (NOLOCK)
    ORDER BY [RowNumber] 
    OFFSET @PageIndex * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE)
END