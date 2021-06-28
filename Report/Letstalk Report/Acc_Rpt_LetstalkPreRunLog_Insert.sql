
/*<info serverAlias="DBMMS-bodb_MMS" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

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

CREATE PROC [dbo].[Acc_Rpt_LetstalkPreRunLog_Insert] 
	@FolderName   VARCHAR(50), 
	@Date         VARCHAR(50), 
	@GenerateTime DATETIME, 
	@TargetName   VARCHAR(50), 
	@Group        VARCHAR(50) , 
	@MailId       INT         = 0, 
	@Subject      VARCHAR(50) = '', 
	@ReportType   VARCHAR(50) = '', 
	@IsSent       BIT
AS
    BEGIN

	   INSERT INTO dbo.LetstalkPreRunLog
		 (
			FolderName, 
			Date, 
			GenerateTime, 
			TargetName, 
			[Group], 
			MailId, 
			Subject, 
			ReportType, 
			IsSent
		 )
	   VALUES
		    (
			@FolderName, 
			@Date, 
			@GenerateTime, 
			@TargetName, 
			@Group, 
			@MailId, 
			@Subject, 
			@ReportType, 
			@IsSent
		    );
    END;