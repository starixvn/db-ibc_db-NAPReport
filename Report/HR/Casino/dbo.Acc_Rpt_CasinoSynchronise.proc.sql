ALTER PROCEDURE [dbo].[Acc_Rpt_CasinoSynchronise]
	@Keyword nvarchar(20) = ''
AS
/*	Created by: Anh Tuan
	Date: 2009-03-25
	DB: DB05.BODB02
	Task: Get Casino unSynchronised List.	
*/

SET NOCOUNT ON

create table #CasinoSync 
(
	Num int PRIMARY KEY IDENTITY(1,1) NOT NULL,
	custid int,
	username nvarchar(20), 
	roleid int,
	srecommend int,
	mrecommend int,
	recommend int,
	disableCasino int
)

/***** Start: Use this Tmp_Table "#custinfo_Tmp" to increase performance *****/
create table #custinfo_Tmp
(
	custid int PRIMARY KEY,
	username nvarchar(20), 
	roleid int,
	srecommend int,
	mrecommend int,
	recommend int,
	disableCasino int	
)

Declare @custid_SAg int, @username_SAg nvarchar(20), 
			@custid_MAg int, @username_MAg nvarchar(20), 
			@custid_Ag int, @username_Ag nvarchar(20), 
			@custid_Mem int, @username_Mem nvarchar(20), 
			@gCustID int, @gRoleID int, @srecommend int, @mrecommend int, @recommend int, @disableCasino int
set @gCustID=-1

-- Set Data into Tmp_Table "#custinfo_Tmp"
Insert into #custinfo_Tmp
SELECT custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
FROM 	custinfo AS c WITH (nolock)
WHERE	c.SyncCasino=1 


if (@Keyword!='')
Begin
	-- Get information to check existence of that UserName
	Select @gCustID=CustID, @gRoleID=RoleID, @srecommend=srecommend, @mrecommend=mrecommend, @recommend=recommend, @disableCasino=disableCasino
	FROM 	custinfo AS c WITH (nolock)
	Where	c.SyncCasino=1 and c.username = @Keyword 

	if (@gCustID != -1)
	Begin
		-- Insert that UserName : @Keyword
		INSERT INTO #CasinoSync
		VALUES (@gCustID, @Keyword, @gRoleID, @srecommend, @mrecommend, @recommend, @disableCasino)

		/********************************** Start: Is Super **********************************/
		if (@gRoleID = 4)
		Begin			
			--START: *** Get Masters of this Super ***
			DECLARE CS_custid_MAg CURSOR FOR
				SELECT custid
				FROM 	#custinfo_Tmp AS c WITH (nolock)						
				WHERE	c.roleid = 3
						AND CASE	WHEN @gCustID <> 0 AND c.srecommend = @gCustID THEN 1
									WHEN @gCustID = 0 THEN 1 ELSE 0 END = 1
				order by username

			OPEN CS_custid_MAg
			FETCH NEXT FROM CS_custid_MAg INTO @custid_MAg

			WHILE @@FETCH_STATUS = 0
			BEGIN						
				--Insert Master
				INSERT INTO #CasinoSync 			   
				Select custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
				From #custinfo_Tmp WITH (nolock)
				Where custid = @custid_MAg

				--START: *** Get Agent of this Master ***
				DECLARE CS_custid_Ag CURSOR FOR
					SELECT custid
					FROM 	#custinfo_Tmp AS c WITH (nolock)						
					WHERE	c.roleid = 2
							AND CASE	WHEN @custid_MAg <> 0 AND c.mrecommend = @custid_MAg THEN 1
										WHEN @custid_MAg = 0 THEN 1 ELSE 0 END = 1
					order by username

				OPEN CS_custid_Ag
				FETCH NEXT FROM CS_custid_Ag INTO @custid_Ag

				WHILE @@FETCH_STATUS = 0
				BEGIN						
					--START: *** Get Member of this Agent
					INSERT INTO #CasinoSync
					SELECT custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
					FROM 	#custinfo_Tmp AS c WITH (nolock)						
					WHERE	c.roleid = 1
							AND CASE	WHEN @custid_Ag <> 0 AND c.recommend = @custid_Ag THEN 1
										WHEN @custid_Ag = 0 THEN 1 ELSE 0 END = 1
							or (custid = @custid_Ag) --Insert Agent
					order by roleid desc, username
					--END: Get Member of this Agent																		
					FETCH NEXT FROM CS_custid_Ag INTO @custid_Ag
				END

				CLOSE CS_custid_Ag
				DEALLOCATE CS_custid_Ag	
				--END: Get Agent of this Master ***									
					
				FETCH NEXT FROM CS_custid_MAg INTO @custid_MAg
			END

			CLOSE CS_custid_MAg
			DEALLOCATE CS_custid_MAg	
			--END: Get Masters of this Super
		End
		/********************************** End: Is Super **********************************/


		/********************************** Start: Is Master **********************************/
		if (@gRoleID = 3)
		Begin
			--START: *** Get Agent of this Master ***
			DECLARE CS_custid_Ag CURSOR FOR
				SELECT custid
				FROM 	#custinfo_Tmp AS c WITH (nolock)						
				WHERE	c.roleid = 2
						AND CASE	WHEN @gCustID <> 0 AND c.mrecommend = @gCustID THEN 1
									WHEN @gCustID = 0 THEN 1 ELSE 0 END = 1
				order by username

			OPEN CS_custid_Ag
			FETCH NEXT FROM CS_custid_Ag INTO @custid_Ag

			WHILE @@FETCH_STATUS = 0
			BEGIN						
				--START: *** Get Member of this Agent
				INSERT INTO #CasinoSync
				SELECT custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
				FROM 	#custinfo_Tmp AS c WITH (nolock)						
				WHERE	c.roleid = 1
						AND CASE	WHEN @custid_Ag <> 0 AND c.recommend = @custid_Ag THEN 1
									WHEN @custid_Ag = 0 THEN 1 ELSE 0 END = 1
						or (custid = @custid_Ag) --Insert Agent
				order by roleid desc, username
				--END: Get Member of this Agent																
				FETCH NEXT FROM CS_custid_Ag INTO @custid_Ag
			END

			CLOSE CS_custid_Ag
			DEALLOCATE CS_custid_Ag	
			--END: Get Agent of this Master ***	
		End
		/********************************** End: Is Master **********************************/


		/********************************** Start: Is Agent **********************************/
		if (@gRoleID = 2)
		Begin
			--START: *** Get Member of this Agent
			INSERT INTO #CasinoSync
			SELECT custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
			FROM 	#custinfo_Tmp AS c WITH (nolock)						
			WHERE	c.roleid = 1
					AND CASE	WHEN @gCustID <> 0 AND c.recommend = @gCustID THEN 1
								WHEN @gCustID = 0 THEN 1 ELSE 0 END = 1
			order by username
			--END: Get Member of this Agent
		End
		/********************************** End: Is Agent **********************************/
	End
End
Else
Begin
	--START
	DECLARE CS_custid_SAg CURSOR FOR
		SELECT custid
		FROM 	#custinfo_Tmp AS c WITH (nolock)
		WHERE	c.roleid = 4 
		order by username		

	OPEN CS_custid_SAg
	FETCH NEXT FROM CS_custid_SAg INTO @custid_SAg

	WHILE @@FETCH_STATUS = 0
	BEGIN							
		--Insert Super
		INSERT INTO #CasinoSync 			   
		Select custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
		From #custinfo_Tmp WITH (nolock)
		Where custid = @custid_SAg

		--START: *** Get Masters of this Super ***
		DECLARE CS_custid_MAg CURSOR FOR
			SELECT custid
			FROM 	#custinfo_Tmp AS c WITH (nolock)						
			WHERE	c.roleid = 3
					AND CASE	WHEN @custid_SAg <> 0 AND c.srecommend = @custid_SAg THEN 1
								WHEN @custid_SAg = 0 THEN 1 ELSE 0 END = 1
			order by username

		OPEN CS_custid_MAg
		FETCH NEXT FROM CS_custid_MAg INTO @custid_MAg

		WHILE @@FETCH_STATUS = 0
		BEGIN						
			--Insert Master
			INSERT INTO #CasinoSync 			   
			Select custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
			From #custinfo_Tmp WITH (nolock)
			Where custid = @custid_MAg

			--START: *** Get Agent of this Master ***
			DECLARE CS_custid_Ag CURSOR FOR
				SELECT custid
				FROM 	#custinfo_Tmp AS c WITH (nolock)						
				WHERE	c.roleid = 2
						AND CASE	WHEN @custid_MAg <> 0 AND c.mrecommend = @custid_MAg THEN 1
									WHEN @custid_MAg = 0 THEN 1 ELSE 0 END = 1
				order by username

			OPEN CS_custid_Ag
			FETCH NEXT FROM CS_custid_Ag INTO @custid_Ag

			WHILE @@FETCH_STATUS = 0
			BEGIN						
				--START: *** Get Member of this Agent
				INSERT INTO #CasinoSync
				SELECT custid, username, roleid, srecommend, mrecommend, recommend, disableCasino
				FROM 	#custinfo_Tmp AS c WITH (nolock)						
				WHERE	c.roleid = 1
						AND CASE	WHEN @custid_Ag <> 0 AND c.recommend = @custid_Ag THEN 1
									WHEN @custid_Ag = 0 THEN 1 ELSE 0 END = 1
						or (custid = @custid_Ag) --Insert Agent
				order by roleid desc, username
				--END: Get Member of this Agent																
				FETCH NEXT FROM CS_custid_Ag INTO @custid_Ag
			END

			CLOSE CS_custid_Ag
			DEALLOCATE CS_custid_Ag	
			--END: Get Agent of this Master ***									
				
			FETCH NEXT FROM CS_custid_MAg INTO @custid_MAg
		END

		CLOSE CS_custid_MAg
		DEALLOCATE CS_custid_MAg	
		--END: Get Masters of this Super
			
		FETCH NEXT FROM CS_custid_SAg INTO @custid_SAg
	END

	CLOSE CS_custid_SAg
	DEALLOCATE CS_custid_SAg
	--END
End

--insert into #CasinoSync
--Select * from #custinfo_Tmp t WITH (nolock)
--where not EXISTS (Select c.custid from #CasinoSync c WITH (nolock) where t.custid=c.custid)
--order by mrecommend

select * from #CasinoSync WITH (nolock)	

DROP TABLE #CasinoSync
DROP TABLE #custinfo_Tmp




GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_CasinoSynchronise] TO [bodbAdminNet]