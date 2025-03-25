/*<info serverAlias="DBRPT-bodb_report" executers="" viewers="vnteam" isFunction="0"></info>*/

/*
https://nexdev.net/issues/221652
sequenceid setting is too stale leading to frequent bettrans table scan from duplicate ticket check service job,
causing timeouts

this script is band-aid fix
*/


update bodb02.dbo.SystemSettings
set vvalue = (select max(sequenceid) from bodb02.dbo.bettrans)
where vname = 'DuplTicketLastID'