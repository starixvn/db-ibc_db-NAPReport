 --*************************************************--
-- TASK: SCRIPT FOR SUPER MOVEMENT REPORT		   --
-- DATE: 2009-09-05							       --
-- Created: Jamie								   -- 
--*************************************************--

-- == STEP 1 == 
-- CREATE Table rptCustBalance ON DBO06.bodb_Report AND CalcList_Customer ON DB06.bodb02 

	USE [bodb_Report]
	GO
	/****** Object:  Table [dbo].[rptCustBalance]    Script Date: 09/05/2009 09:54:50 ******/
	SET ANSI_NULLS ON
	GO
	SET QUOTED_IDENTIFIER ON
	GO
	CREATE TABLE [dbo].[rptCustBalance](
		[winlostdate] [datetime] NOT NULL,
		[custid] [int] NOT NULL CONSTRAINT [DF_rptCustBalance_custid]  DEFAULT ((0)),
		[status] [tinyint] NOT NULL CONSTRAINT [DF_rptCustBalance_Status]  DEFAULT ((0)),
		[roleID] [int] NOT NULL CONSTRAINT [DF_rptCustBalance_roleID]  DEFAULT ((0)),
		[PosOriginal] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_PosOriginal]  DEFAULT ((0)),
		[PosBase] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_PosBase]  DEFAULT ((0)),
		[ComOriginal] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_ComOriginal]  DEFAULT ((0)),
		[ComBase] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_ComBase]  DEFAULT ((0)),
		[BetOriginal] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_BetOriginal]  DEFAULT ((0)),
		[BetBase] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_BetBase]  DEFAULT ((0)),
		[TraOriginal] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_TraOriginal]  DEFAULT ((0)),
		[TraBase] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_TraBase]  DEFAULT ((0)),
		[BalOriginal] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_BalOriginal]  DEFAULT ((0)),
		[BalBase] [money] NOT NULL CONSTRAINT [DF_rptCustBalance_BalBase]  DEFAULT ((0)),
		[UpdDate] [datetime] NOT NULL CONSTRAINT [DF_rptCustBalance_UpdDate]  DEFAULT (getdate()),
	 CONSTRAINT [PK_rptCustBalance] PRIMARY KEY CLUSTERED 
	(
		[winlostdate] ASC,
		[custid] ASC,
		[status] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
	) ON [DATA]
	GO
	----
	USE [bodb02]
	GO
	/****** Object:  Table [dbo].[CalcList_Customer]    Script Date: 09/05/2009 09:59:26 ******/
	SET ANSI_NULLS ON
	GO
	SET QUOTED_IDENTIFIER ON
	GO
	CREATE TABLE [dbo].[CalcList_Customer](
		[winlostdate] [datetime] NOT NULL,
		[custID] [int] NOT NULL,
		[roleID] [int] NOT NULL CONSTRAINT [DF_CalcList_Customer_roleID]  DEFAULT ((0)),
		[addTime] [datetime] NOT NULL CONSTRAINT [DF_CalcList_Customer_addTime]  DEFAULT (getdate()),
	 CONSTRAINT [PK_CalcList_Customer] PRIMARY KEY CLUSTERED 
	(
		[winlostdate] ASC,
		[custID] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
	) ON [DATA]
	GO
	USE [bodb02]
	GO
	/****** Object:  Index [IX_AddTime]    Script Date: 09/05/2009 10:05:30 ******/
	CREATE NONCLUSTERED INDEX [IX_AddTime] ON [dbo].[CalcList_Customer] 
	(
		[addTime] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [DATA]
	GO
--== STEP 2 ==-- 
-- Insert initial Historical Balance into DB06.bodb_Report.dbo.rptCustBalance
	USE [bodb02]
	GO
	DECLARE @yesterday datetime 
	SELECT  @yesterday = convert(varchar(10), CURRENT_TIMESTAMP -1, 120)

	INSERT INTO bodb_Report.dbo.rptCustBalance(
		winlostdate, 
		CustID,
		[status], 
		RoleID,
		ComOriginal, 
		PosOriginal, 
		BetOriginal, 
		TraOriginal, 
		BalOriginal,
		ComBase, 
		PosBase, 
		BetBase, 
		TraBase, 
		BalBase
	)
		
	SELECT	@yesterday,
			srecommend,
			1,	
			4,
			0,0,0,0,
			IsNull(sum((case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)),0)
			+ IsNull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)),0)
			+ IsNull(sum((case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end)),0)
			+ IsNull(sum((case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end)),0) 
				AS BalOriginal,
			0,0,0,0,
			IsNull(sum((case when custid=srecommend then winlost-actual_stake else swinlost+scomm-acomm end)*b.actualrate),0)
			+ IsNull(sum((case when custid=mrecommend then winlost-actual_stake else mwinlost+acomm-comm end)*b.actualrate),0)
			+ IsNull(sum((case when custid=recommend  then winlost-actual_stake else awinlost+comm-playercomm end)*b.actualrate),0)
			+ IsNull(sum((case when custid <> recommend and custid <> mrecommend and custid <> srecommend and ruben=1 then winlost-actual_stake+playercomm else 0 end)*b.actualrate),0) 
				AS BalBase
		
	FROM bettrans b with (nolock) 
	where Winlostdate <= @yesterday AND ruben = 1 AND status NOT IN ('VOID','REJECT','REFUND')
	GROUP BY srecommend
	
	GO
	-----------------------------
--== STEP 3 ==--
-- CREATE JOBS AT 2:00 AM every day 
-- [Task_rptBalanceMovementIns_Daily] 
-- [Task_rptBalanceMovementSum_Daily]
-- [Task_rptBalanceMovementUpd_RealTime] (every 1-minute)
/****** Object:  Job [Task_rptBalanceMovementIns_Daily]    Script Date: 09/16/2009 13:58:52 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 09/16/2009 13:58:52 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Task_rptBalanceMovementIns_Daily', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Inserting Balance Daily', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Step_rptBalanceMovementIns]    Script Date: 09/16/2009 13:58:53 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step_rptBalanceMovementIns', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'DECLARE @Yesterday datetime, @BeforeYesterday datetime
SELECT    @Yesterday = DATEADD(day, -1, CONVERT(varchar(10), CURRENT_TIMESTAMP, 120))
SELECT    @BeforeYesterday = DATEADD(day, -2, CONVERT(varchar(10), CURRENT_TIMESTAMP, 120))

EXEC dbo.Task_rptBalanceMovementIns @winlostdate = @yesterday 
EXEC dbo.Task_rptBalanceMovementIns @winlostdate = @beforeYesterday ', 
		@database_name=N'bodb02', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Sch_rptBalanceMovementIns', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20090904, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO
/****** Object:  Job [Task_rptBalanceMovementSum_Daily]    Script Date: 09/16/2009 13:58:53 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 09/16/2009 13:58:53 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Task_rptBalanceMovementSum_Daily', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Sum up historical balance', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Step_rptBalanceMovementSum]    Script Date: 09/16/2009 13:58:54 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step_rptBalanceMovementSum', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'DECLARE @OldDay DATETIME 
SELECT    @OldDay = DATEADD(day, -7, CONVERT(varchar(10), CURRENT_TIMESTAMP, 120))

EXEC dbo.Task_rptBalanceMovementSum @winlostdate = @OldDay 
', 
		@database_name=N'bodb_Report', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Sch_rptBalanceMovementSum', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20090904, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO
/****** Object:  Job [Task_rptBalanceMovementUpd_RealTime]    Script Date: 09/16/2009 13:58:54 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 09/16/2009 13:58:54 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Task_rptBalanceMovementUpd_RealTime', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Updating Balance every 2 minute', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Step_rptBalanceMovementUpd]    Script Date: 09/16/2009 13:58:55 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step_rptBalanceMovementUpd', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'DECLARE @checkTime DATETIME 

SELECT @checkTime = DATEADD(Minute,-2,CURRENT_TIMESTAMP)

EXEC dbo.Task_rptBalanceMovementUpd @checkTime = @checkTime 
', 
		@database_name=N'bodb02', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Sch_rptBalanceMovementUpd', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20090904, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave: