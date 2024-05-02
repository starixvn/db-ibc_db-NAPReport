/*<info serverAlias="DBACC-bodb_Report"></info>*/
use bodb_Report

ALTER DATABASE bodb_report ADD FILEGROUP AutomailBalanceBreakdown_Daily;

ALTER DATABASE bodb_report 
ADD FILE 
(
    NAME = AutomailBalanceBreakdown_Daily,
    FILENAME = '/mnt/DiskG/bodb_Report/AutomailBalanceBreakdown_Daily.ndf',
    SIZE = 1GB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 64MB
)
TO FILEGROUP AutomailBalanceBreakdown_Daily;

ALTER DATABASE bodb_report ADD FILEGROUP AutomailBalanceBreakdown_Monthly;

ALTER DATABASE bodb_report 
ADD FILE 
(
    NAME = AutomailBalanceBreakdown_Monthly,
    FILENAME = '/mnt/DiskG/bodb_Report/AutomailBalanceBreakdown_Monthly.ndf',
    SIZE = 1GB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 64MB
)
TO FILEGROUP AutomailBalanceBreakdown_Monthly;

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
        PRIMARY KEY CLUSTERED ([srecommend] ASC, [mrecommend] ASC, [recommend] ASC, [custid] ASC)
) ON [PK_AutomailBalanceBreakdown_Daily]

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
        PRIMARY KEY CLUSTERED ([srecommend] ASC, [mrecommend] ASC, [recommend] ASC, [custid] ASC)
) ON [PK_AutomailBalanceBreakdown_Monthly]