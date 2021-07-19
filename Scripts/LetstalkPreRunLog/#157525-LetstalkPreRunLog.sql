
/*<info serverAlias="DBMMS-bodb_MMS"></info>*/

/*
	Creator:	20210628@Robert
	Task:	Letstalk services - Store Log into DB instead of Json file #157525

	Database:	DBMMS.bodb_MMS
	
	Revisions:
		- 20210628@Robert:	Letstalk services - Store Log into DB instead of Json file #157525
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

CREATE TABLE [dbo].[LetstalkPreRunLog]
(
             [Id]           [BIGINT] IDENTITY(1,1), 
             [FolderName]   [VARCHAR](50) NULL, 
             [Date]         [VARCHAR](50) NULL, 
             [GenerateTime] [DATETIME] NULL, 
             [TargetName]   [VARCHAR](50) NULL, 
             [Group]        [VARCHAR](50) NULL, 
             [MailId]       [INT] NULL, 
             [Subject]      [VARCHAR](50) NULL, 
             [ReportType]   [VARCHAR](50) NULL, 
             [IsSent]       [BIT] NULL, 
             CONSTRAINT [PK_LetstalkPreRunLog] PRIMARY KEY CLUSTERED([Id] ASC)
             WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
)
ON [PRIMARY];
GO


CREATE NONCLUSTERED INDEX [NonCIDX-Date] ON [dbo].[LetstalkPreRunLog]
(
	[Date] ASC, [IsSent] ASC
) 
       WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY];
GO

CREATE NONCLUSTERED INDEX [NonCIDX-FolderName] ON [dbo].[LetstalkPreRunLog]
(
	[FolderName] ASC, [IsSent] ASC
) 
       WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY];
GO

GRANT SELECT ON OBJECT ::dbo.LetstalkPreRunLog TO bodbAdminNet;  

