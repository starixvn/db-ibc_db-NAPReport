USE [bodb_dwrs]
GO

ALTER PROC [dbo].[Acc_SiteSel_Credit]
	@Mode INT = 0
AS
/*
    Created by: Jaden
    Date: 2022-01-18
    Task : GET active CREDIT sites
    DB: DBDW
    Original SP: [DB052.bodb02.dbo.Acc_SiteSel_Credit] 
    Parameter's explaination: @Mode  = 0: No sites CN88 and isActive = 1
                                    = 1: All Site
    Revisions:
        - 20220118@Jaden: Cloned from DB052 for #182497
*/
BEGIN
    SET NOCOUNT ON  

    SELECT siteid, site, SiteDBGroupID
    FROM bodb02.[dbo].Site  WITH (NOLOCK)
    WHERE islicensee = 0  AND (@Mode = 1 OR (@Mode = 0 AND isactive=1 AND [siteid]<>329))
END
GO


