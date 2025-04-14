/*<info serverAlias="DBACC-bodb02" executers="" isFunction="0"></info>*/
/*
    Created: 20250411@Louisa
	Task:Creat eindex on bettransLC, bettransRnG [Redmine:#223831]
	DB: DBACC-bodb02
*/

USE [bodb02]
GO
 
CREATE NONCLUSTERED INDEX [IX_sequenceid] ON [dbo].[bettransLC]
(
	[sequenceid] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = ON, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) 
ON [bettransLC_index]
GO

CREATE NONCLUSTERED INDEX [IX_sequenceid] ON [dbo].[bettransRnG]
(
	[sequenceid] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = ON, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) 
ON [bettransRNG_index]
GO


