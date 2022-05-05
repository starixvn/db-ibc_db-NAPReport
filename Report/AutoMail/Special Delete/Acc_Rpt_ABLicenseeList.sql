/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

ALTER PROCEDURE dbo.Acc_Rpt_ABLicenseeList 
	@RptDate    DATETIME 
   , @IsTest     BIT         = 0 
AS
/*
	Creator: Cherry
	Date: 2022-04-28
	DB: DBACC.bodb02
	Task: Get recipient list for Abnormal Bet
	Revisions:		
		- 20220428@Cherry: Get recipient list for Abnormal Bet (#171985)

	Param's Explanation:	 
*/

    BEGIN
	   SET NOCOUNT ON;

	   CREATE TABLE #TmpVoidedTransaction(
		   TransId           BIGINT
		 , SubIssueTypeId    TINYINT);  

	   CREATE TABLE #tmpLicensee (LicenseeName NVARCHAR(50))

	   DECLARE @RptDate_From    DATETIME = @RptDate
		    , @RptDate_To      DATETIME;

	   SELECT @RptDate_From = CONVERT(VARCHAR(10), @RptDate_From, 101)
		   , @RptDate_To = DATEADD(d, 1, @RptDate_From);

	   INSERT INTO #TmpVoidedTransaction(TransId
								, SubIssueTypeId)
			SELECT b.TransId
				, b.SubIssueTypeId
			FROM bodb02.dbo.TicketVoiding_VoidedTransaction AS b WITH(NOLOCK)
			WHERE b.CustID > 0
				 AND b.CreatedDate >= @RptDate_From
				 AND b.CreatedDate < @RptDate_To
				 AND b.IssueTypeID = 11;

	   CREATE CLUSTERED INDEX IX_TransId ON #TmpVoidedTransaction(TransId ASC);

	   IF @IsTest = 0
	   BEGIN
		    INSERT INTO #tmpLicensee (LicenseeName)
			SELECT DISTINCT s.site LicenseeName			
			FROM bodb02.dbo.bettrans AS b WITH(NOLOCK)
			    INNER JOIN #TmpVoidedTransaction AS tmp ON b.transid = tmp.TransId
			    LEFT JOIN bodb02.dbo.Customer AS c WITH(NOLOCK) ON b.srecommend = c.custid
			    LEFT JOIN bodb02.dbo.Site AS s WITH(NOLOCK) ON c.site = s.site
			WHERE s.isDeposit = 1
				 AND b.Currency <> 20						 
	   END
	   ELSE -- @IsTest = 1
			INSERT INTO #tmpLicensee (LicenseeName) VALUES ('spondemo'),('Athena000')

	   SELECT LicenseeName FROM #tmpLicensee

	   DROP TABLE #TmpVoidedTransaction
	   DROP TABLE #tmpLicensee

    END