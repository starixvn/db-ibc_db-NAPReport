
/*<info serverAlias="DBMMS-bodb_MMS" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20210628@Robert
	Task:	Letstalk services - Store Log into DB instead of Json file #157525

	Database:	DBMMS.bodb_MMS
	
	Revisions:
		- 20210628@Robert:	Letstalk services - Store Log into DB instead of Json file #157525
		
	Parameter's Explaination:
		- @Example:		
		• @MemNotify: XML.format(<notify><row custid = "1" productid="1" winlostdate="" bettypeid="" /></notify>)
		
	Developer's Notes:		
*/

CREATE PROC [dbo].[Acc_Rpt_LetstalkPreRunLog_Update] 
	@FolderSent XML
AS
    BEGIN
	   CREATE TABLE #temp
				 (
		   FolderName VARCHAR(50), 
		   Date       VARCHAR(50)
				 );

	   INSERT INTO #temp
			SELECT 
				  Tbl.Col.value('@FolderName', 'varchar(50)'), 
				  Tbl.Col.value('@Date', 'varchar(50)')
			FROM @FolderSent.nodes('//notify/row') Tbl(Col);


	   UPDATE l
		SET 
		    l.IsSent = 1
	   FROM dbo.LetstalkPreRunLog l(NOLOCK)
		   INNER JOIN #temp t ON l.FolderName = t.FolderName
							AND l.Date = t.Date;

	   DELETE l
	   FROM dbo.LetstalkPreRunLog l(NOLOCK)
	   WHERE 
		    DATEADD(HOUR, 5, l.GenerateTime) <= GETDATE() 


	   DROP TABLE #temp;
    END;

