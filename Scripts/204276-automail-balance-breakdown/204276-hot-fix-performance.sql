/*<info serverAlias="DBACC-bodb_Report"></info>*/
use bodb_Report

DROP TABLE AutomailBalanceBreakdown_Daily;

--from begin of bettrans/transfer to date
CREATE TABLE AutomailBalanceBreakdown_Daily
(
    [Super] VARCHAR(30)
,   [Master] VARCHAR(30)
,   [Agent] VARCHAR(30)
,   [Member] VARCHAR(30)
,   SuperAmt MONEY
,   MasterAmt MONEY
,   AgentAmt MONEY
,   MemberAmt MONEY
,   SuperAmtRM MONEY
,   MasterAmtRM MONEY
,   AgentAmtRM MONEY
,   MemberAmtRM MONEY
,   [RowNumber] INT
        CONSTRAINT [PK_AutomailBalanceBreakdown_Daily]
        PRIMARY KEY CLUSTERED ([RowNumber] ASC)
) ON [AutomailBalanceBreakdown_Daily]

DROP TABLE AutomailBalanceBreakdown_Monthly;

--from begin of bettrans/transfer to end of last month
CREATE TABLE AutomailBalanceBreakdown_Monthly
(
    [Super] VARCHAR(30)
,   [Master] VARCHAR(30)
,   [Agent] VARCHAR(30)
,   [Member] VARCHAR(30)
,   SuperAmt MONEY
,   MasterAmt MONEY
,   AgentAmt MONEY
,   MemberAmt MONEY
,   SuperAmtRM MONEY
,   MasterAmtRM MONEY
,   AgentAmtRM MONEY
,   MemberAmtRM MONEY
,   [RowNumber] INT
        CONSTRAINT [PK_AutomailBalanceBreakdown_Monthly]
        PRIMARY KEY CLUSTERED ([RowNumber] ASC)
) ON [AutomailBalanceBreakdown_Monthly]