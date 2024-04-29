
/*<info serverAlias="DBACC-bodb_Report" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/

USE bodb_Report
GO

ALTER PROCEDURE [dbo].[Acc_Rpt_Automail_BalanceBreakdown_Daily]
@PageIndex INT           = 0
, @PageSize  INT           = 1048576
AS
/*
    Created	: 20240426@Jaden
	Task	: Balance report of customers, for Finance team to backup (#204276)
              Daily runs
	DB		: DBACC/bodb02
	
	Revision:		
		20240426@Jaden: Initial (#204276)

	Param's Explanation:
*/
BEGIN
    SELECT srecommend
         , mrecommend
         , recommend
         , custid
         , SuperAmt
         , MasterAmt
         , AgentAmt
         , MemberAmt
         , SuperAmtRM
         , MasterAmtRM
         , AgentAmtRM
         , MemberAmtRM
    FROM dbo.AutomailBalanceBreakdown_Daily (NOLOCK)
    ORDER BY [srecommend]
           , [mrecommend]
           , [recommend]
           , [custid] 
    OFFSET @PageIndex * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE)
END