/*<info serverAlias="DBWH-bodb_dwrs" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_dwrs
GO

ALTER PROCEDURE Acc_Rpt_CompanyWinloss_LeagueSel @SearchText    NVARCHAR(1000),
											  	 @SearchExactly BIT = 0
AS
/*
	Created: 20200916@Jaden
	Task : Get list of Leagues
	DB: DBDW.bodb_dwrs

	Revisions:
		20210601@Jaden: Add the League textbox and Division dropdown (#???)
*/
BEGIN
	SET NOCOUNT ON

	IF @SearchExactly = 0
	BEGIN
		CREATE TABLE #SearchWord(SearchWord NVARCHAR(100))

		DECLARE @word NVARCHAR(100)
		DECLARE @pos INT

		WHILE CHARINDEX(',', @SearchText) > 0
		BEGIN
			SET @pos  = CHARINDEX(',', @SearchText)  
			SET @word = SUBSTRING(@SearchText, 1, @pos-1)
			SET @SearchText = SUBSTRING(@SearchText, @pos+1, LEN(@SearchText)-@pos)
			INSERT INTO #SearchWord (SearchWord) VALUES (@word)
		END

		INSERT INTO #SearchWord (SearchWord) VALUES (@SearchText)
		
		SELECT leaguename [Name]
		FROM
			(SELECT DISTINCT TOP 20 leaguename, len(leaguename) as lnlen
			FROM bodb02.dbo.League league (NOLOCK)
			WHERE Istest=0
				AND EXISTS (SELECT 1 FROM #SearchWord WHERE CHARINDEX(SearchWord, leaguename) > 0)
			ORDER BY len(leaguename),leaguename) as tmp

		DROP TABLE #SearchWord
	END
	ELSE
	BEGIN
		SELECT leagueid
			,leaguename
		INTO #tmpLeague
		FROM bodb02.dbo.League league(NOLOCK)
		WHERE Istest = 0 AND leaguename = @SearchText
		
		--Make sure the resultset is single row
		SELECT TOP 1 leaguename [Name]
			,ID = STUFF((
					SELECT ',' + convert(NVARCHAR(10), leagueid)
					FROM #tmpLeague t1
					WHERE t1.leaguename = t2.leaguename
					ORDER BY t1.leagueid
					FOR XML PATH('')
				), 1, 1, '')
		FROM #tmpLeague t2
		GROUP BY leaguename;

		DROP TABLE #tmpLeague
	END
END
