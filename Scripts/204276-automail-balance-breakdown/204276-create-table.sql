/*<info serverAlias="DBACC-bodb_Report"></info>*/
use bodb_Report

--from begin of bettrans/transfer to date
CREATE TABLE AutomailBalanceBreakdown_Daily
(
    srecommend INT
,   mrecommend INT
,   recommend INT
,   custid INT
,   SuperAmt MONEY
,   MasterAmt MONEY
,   AgentAmt MONEY
,   MemberAmt MONEY
,   SuperAmtRM MONEY
,   MasterAmtRM MONEY
,   AgentAmtRM MONEY
,   MemberAmtRM MONEY
        CONSTRAINT [PK_AutomailBalanceBreakdown_Daily]
        PRIMARY KEY CLUSTERED ([custid] ASC, [recommend] ASC, [mrecommend] ASC, [srecommend] ASC)
) ON [DATA]

--from begin of bettrans/transfer to end of last month
CREATE TABLE AutomailBalanceBreakdown_Monthly
(
    srecommend INT
,   mrecommend INT
,   recommend INT
,   custid INT
,   SuperAmt MONEY
,   MasterAmt MONEY
,   AgentAmt MONEY
,   MemberAmt MONEY
,   SuperAmtRM MONEY
,   MasterAmtRM MONEY
,   AgentAmtRM MONEY
,   MemberAmtRM MONEY
        CONSTRAINT [PK_AutomailBalanceBreakdown_Monthly]
        PRIMARY KEY CLUSTERED ([custid] ASC, [recommend] ASC, [mrecommend] ASC, [srecommend] ASC)
) ON [DATA]