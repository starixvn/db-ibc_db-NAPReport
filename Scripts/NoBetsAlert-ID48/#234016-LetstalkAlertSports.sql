
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250804@Robert
	Task:	Letstalk - No Bet Alerts (ID 48) - Enhancement - Auto Release Product on First Bet Detection for No Bet Alerts #234016

	Database:	DBMMS.bodb_MMS
	
	Revisions:
		- Letstalk - No Bet Alerts (ID 48) - Enhancement - Auto Release Product on First Bet Detection for No Bet Alerts #234016
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

CREATE TABLE [dbo].[LetstalkAlertSports]
(
             [Id]           [tinyint] IDENTITY(1,1), 
             [ProductId]   [tinyint] NOT NULL, 
             [SportType]         [tinyint] NOT NULL, 
             [TimeSetting] [VARCHAR](50) NOT NULL,
		   [IsTest] bit NOT NULL
             CONSTRAINT [PK_LetstalkAlertSports] PRIMARY KEY CLUSTERED([Id] ASC)
             WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
)
ON [PRIMARY];
GO


CREATE NONCLUSTERED INDEX [NonCIDX-TimeSetting-IsTest] ON [dbo].[LetstalkAlertSports]
(
	[TimeSetting] ASC, [IsTest] ASC
) 
       WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY];
GO