
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

CREATE PROC [dbo].[Acc_Rpt_LetstalkPreRunLog_Generated] 
	@Date       VARCHAR(50), 
	@ReportType VARCHAR(50)
AS
    BEGIN
	   SELECT 
			l.FolderName, 
			l.Date, 
			l.GenerateTime, 
			l.TargetName, 
			l.[Group], 
			l.MailId, 
			l.Subject
	   FROM dbo.LetstalkPreRunLog l(NOLOCK)
	   WHERE l.Date = @Date
		    AND l.ReportType = @ReportType;
    END;
