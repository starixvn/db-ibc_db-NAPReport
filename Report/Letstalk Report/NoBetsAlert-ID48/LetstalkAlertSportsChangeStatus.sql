
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250804@Robert
	Task:	Letstalk - No Bet Alerts (ID 48) - Enhancement - Auto Release Product on First Bet Detection for No Bet Alerts #234016

	Database:	DBACC.bodb02	
	Revisions:
		- 20250804@Robert - Update status

*/

CREATE PROC [dbo].[LetstalkAlertSportsChangeStatus] 
	@ProductId TINYINT, 
	@IsTest    BIT
AS
    BEGIN
	   UPDATE l
		SET 
		    l.IsTest = @IsTest
	   FROM LetstalkAlertSports l WITH (UPDLOCK)
	   WHERE 
		    l.ProductId = @ProductId;
    END;
GO
