
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20250804@Robert
	Task:	Letstalk - No Bet Alerts (ID 48) - Enhancement - Auto Release Product on First Bet Detection for No Bet Alerts #234016

	Database:	DBACC.bodb02
	Revisions:
		- 20250804@Robert - Insert product.	
		- 20251020@Robert - change column SportType data type from tinyint to smallint
*/

CREATE PROC [dbo].[LetstalkAlertSportsInsertProduct] 
	@ProductId   TINYINT, 
	@SportType   SMALLINT, 
	@TimeSetting VARCHAR(10), 
	@IsTest      BIT
AS
    BEGIN
	   INSERT INTO LetstalkAlertSports
		 (
			ProductId, 
			SportType, 
			TimeSetting, 
			IsTest
		 )
	   VALUES
		    (
			@ProductId, 
			@SportType, 
			@TimeSetting, 
			@IsTest
		    );
    END;
GO
