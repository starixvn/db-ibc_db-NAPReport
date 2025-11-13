/*<info serverAlias="DBMA-bodb_Maintenance" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
/*
	Creator:	20251111@Robert
	Task:	Fail Safe System Control#244040

	Database:	DBMA.bodb_Maintenance
	
	Revisions:
		- Fail Safe System Control
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/
CREATE TABLE [dbo].[FailSafeSystemControl] (
	[Id] [tinyint] IDENTITY(1, 1),
	[UserId] [int] NOT NULL,
	[UserName] [varchar](30) NOT NULL,
	[ActionDate] [DateTime] NOT NULL,
	[IsAutoDisableProduct] BIT NOT NULL,
	[Description] [VARCHAR](200) NOT NULL CONSTRAINT [PK_FailSafeSystemControl] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (
		PAD_INDEX = OFF,
		STATISTICS_NORECOMPUTE = OFF,
		IGNORE_DUP_KEY = OFF,
		ALLOW_ROW_LOCKS = ON,
		ALLOW_PAGE_LOCKS = ON
		) ON [PRIMARY]
	) ON [PRIMARY];
GO

