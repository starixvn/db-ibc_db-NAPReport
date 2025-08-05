/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO 

ALTER PROCEDURE [dbo].[Acc_API_Soccer_Pingoal] 
    @RptDate DATE = NULL
    , @LeagueGroupID INT = 252
AS
/*
    Created:
    Task: Develop an API to return ticket data in detail (Requestor: Tony)
    DB: DB06.bodb02
    Revisions:
    - 20250805@Jaden: Develop an API to return ticket data in detail (Requestor: Tony)
*/
BEGIN
    IF @RptDate IS NULL
        SET @RptDate = DATEADD(DAY, -1, GETDATE())

    select m.leagueid,
        b.transid,
        b.custid,
        b.transdate,
        b.oddsid,
        b.hdp1,
        b.hdp2,
        b.odds,
        b.stake,
        b.status,
        b.winlost,
        b.awinlost,
        b.mwinlost,
        b.playercomm,
        b.comm,
        b.acomm,
        b.apositiontaking,
        b.mpositiontaking,
        b.tpositiontaking,
        b.playerdiscount,
        b.discount,
        b.adiscount,
        b.livehomescore,
        b.liveawayscore,
        b.liveindicator,
        b.betteam,
        b.creator,
        b.refno,
        b.comstatus,
        b.winlostdate,
        b.betfrom,
        b.betcheck,
        b.checktime,
        b.oddsspread,
        b.actualrate,
        b.matchid,
        b.recommend,
        b.mrecommend,
        b.ruben,
        b.betid,
        b.statuswinlost,
        b.modds,
        b.bettype,
        b.betdaqid,
        b.tstamp,
        b.actual_stake,
        b.currency,
        b.transdesc,
        b.sdiscount,
        b.scomm,
        b.spositiontaking,
        b.swinlost,
        b.srecommend,
        b.virtualrate,
        b.oddstype,
        b.statusID,
        b.currency2,
        b.balance,
        b.SecAcceptFlag,
        b.transid2,
        b.recommdate,
        b.ExtraInfo,
        b.WalletType,
        b.BonusID,
        b.RefCode,
        b.SettlementTime,
        b.epositiontaking,
        b.ReasonID
    from dbo.bettrans b with (nolock)
        inner join dbo.match m with (nolock) on b.matchid = m.matchid
        inner join dbo.league l with (nolock) on m.leagueid = l.leagueid
    where l.leaguegroupid = @LeagueGroupID
        and b.winlostdate = @RptDate
        and b.currency not in (20, 72)
END
GO