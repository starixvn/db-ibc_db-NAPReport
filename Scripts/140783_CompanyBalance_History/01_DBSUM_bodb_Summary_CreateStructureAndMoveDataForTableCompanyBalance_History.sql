/*<info serverAlias="DBSUM-bodb_Summary"></info>*/

/*
	Created: 20200914@Ned.Le
	DB: DBSUM.bodb_Summary
	Task:
		[1] - Create data structure for CompanyBalance_History
		[2] - Move data from bodb_CustomerLog to bodb_Summary
	RedmineID:
		#140783 - Migrate Log DBs from DB052 to DB054 (Phase 1)
*/


USE bodb_Summary
GO


-- [1] - Create data structure for CompanyBalance_History

CREATE TABLE [dbo].[CompanyBalance_History](
	[BalanceUpDay] [smalldatetime] NOT NULL,
	[Currency] [int] NOT NULL,
	[CompBalBefore] [float] NULL,
	[CompBalAfter] [float] NULL,
 CONSTRAINT [PK_CompanyBalance_History] PRIMARY KEY CLUSTERED 
(
	[BalanceUpDay] ASC,
	[Currency] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [DATA]
) ON [DATA]
GO


-- [2] - Move data from bodb_CustomerLog to bodb_Summary

TRUNCATE TABLE [dbo].[CompanyBalance_History]

INSERT INTO [dbo].[CompanyBalance_History] (
	[BalanceUpDay],
	[Currency],
	[CompBalBefore],
	[CompBalAfter]
)
SELECT [BalanceUpDay],
       [Currency],
       [CompBalBefore],
       [CompBalAfter]
FROM [DB052].[bodb_CustomerLog].[dbo].[CompanyBalance_History]