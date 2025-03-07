/*<info serverAlias="DBRPT-bodb_report" executers="" viewers="vnteam" isFunction="0"></info>*/


use msdb
go

EXEC dbo.sp_update_job
    @job_name = N'bodb_report_checkNAPDuplicatedTicket',
    @enabled = 0;
GO
--rename agent job to DEL_bodb_report_checkNAPDuplicatedTicket
EXEC msdb.dbo.sp_update_job
    @job_name = N'bodb_report_checkNAPDuplicatedTicket',
    @new_name = N'DEL_bodb_report_checkNAPDuplicatedTicket';
GO







