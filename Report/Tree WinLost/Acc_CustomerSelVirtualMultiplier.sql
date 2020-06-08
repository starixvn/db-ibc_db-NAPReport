/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE  [dbo].[Acc_CustomerSelVirtualMultiplier] 
	@CustID int,
	@IsTest BIT=0
AS
	/*
		Created: 
		Date: 
		DB: DBACC/bodb02
		Task: Get virtual rate settings of customers
		
		Revisions:
			- 20141226@Johnson: Separate virtual rate by sporttype, bettype [Redmine: #25840]	
			- 20151029@Billy: Using new Virtual Rate structure [Redmine: #46541]
			- 20160128@Billy: Update Virtual Rate's range from [-0.8, 1.6] to [-0.9, 1.6] - [Redmine: #51611]
			- 20160816@Winnie: Change sp for UAT purpose [Redmine: #61713]			
			- 20170328@Elodie: Expand the range of VR setting [RedmineID:#73808]
			- 20190725@Elodie: Extend range and interval steps [Redmine:#117609]
			- 20190702@Dominic: Not show E-Sports [RedmineID:#114830]
			- 20200608@Cherry: Not show Basketball (#134978)
		Parameter's Explanation:
	*/
BEGIN
	SET NOCOUNT ON

    DECLARE @ActualRate FLOAT
    DECLARE @CustVirtualRate TABLE (
                custid INT,
                sporttype SMALLINT,
                bettype SMALLINT,
                islive BIT,
                virtualMultiplier SMALLMONEY)

    SELECT      @ActualRate = actualrate
    FROM        exchange AS e WITH(NOLOCK)
    INNER JOIN  Customer AS c
            ON  e.exchangeid = c.currency
    WHERE       c.custid = @CustID

    SELECT  @ActualRate         AS ActualRate,
            VirtualMultiplier   AS EnableVirtualRate,
            -0.95                AS Min_VirtualMultiplier,
            2.0                 AS Max_VirtualMultiplier
    FROM    custInfo WITH(NOLOCK)
    WHERE   custid = @CustID

    INSERT INTO @CustVirtualRate
    SELECT      cvs.custid,
                pvs.sporttype,
                pvs.bettype,
                pvs.islive,
                dbo.f_GetVirtualSetting(cvs.bitmapVirtual, pvs.profileID) AS virtualMultiplier
    FROM        CustVirtualSetting    AS cvs WITH(NOLOCK)
    INNER JOIN  ProfileVirtualSetting       AS pvs WITH(NOLOCK)
            ON  cvs.seqNo = pvs.seqNo
    WHERE       cvs.custid = @CustID
			AND ((@IsTest=0 AND pvs.isActive = 1) OR (@IsTest=1))
			AND pvs.sporttype NOT IN (43, 2)
	ORDER BY sporttype, isLive DESC, bettype

    SELECT custid, sporttype, bettype, islive, virtualMultiplier
    FROM @CustVirtualRate
END