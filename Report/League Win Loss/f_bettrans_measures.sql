/*<info serverAlias="DBACC-bodb02" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="1"></info>*/

USE bodb02
GO

ALTER FUNCTION [dbo].[f_bettrans_measures] (@IsNoDraw BIT = 0)
RETURNS TABLE
/**
    Created: Jaden.Tang@20201015
    DB: DBACC.bodb02
    Remarks: bettrans table with added calculations for common measures

    Revisions:
		- 20201016@Jaden.Tang: creation

    Param's Explanation:
		- @IsNoDraw: To include the draw tickets in Turnovers or not
                     Refer to feature id #120417 on how to determine DRAW tickets from bettrans
**/
AS  
RETURN (
    WITH Source AS (
        SELECT 
            transid
            ,custid
            ,transdate
            ,oddsid
            ,hdp1
            ,hdp2
            ,odds
            ,stake
            ,status
            ,winlost
            ,awinlost
            ,mwinlost
            ,playercomm
            ,comm
            ,acomm
            ,apositiontaking
            ,mpositiontaking
            ,tpositiontaking
            ,playerdiscount
            ,discount
            ,adiscount
            ,livehomescore
            ,liveawayscore
            ,liveindicator
            ,betteam
            ,creator
            ,refno
            ,comstatus
            ,winlostdate
            ,betfrom
            ,betcheck
            ,checktime
            ,oddsspread
            ,actualrate
            ,matchid
            ,recommend
            ,mrecommend
            ,ruben
            ,betid
            ,statuswinlost
            ,modds
            ,bettype
            ,betdaqid
            ,tstamp
            ,actual_stake
            ,currency
            ,ip
            ,transdesc
            ,sdiscount
            ,scomm
            ,spositiontaking
            ,swinlost
            ,srecommend
            ,Username
            ,CurrencyName
            ,virtualrate
            ,oddstype
            ,statusID
            ,currency2
            ,balance
            ,SecAcceptFlag
            ,transid2
            ,RecommDate
            ,ExtraInfo
            ,WalletType
            ,BonusID
            ,RefCode
            ,SettlementTime
            ,ReasonID
            ,ISNULL(CAST(epositiontaking AS DECIMAL(9, 8)), 0) AS epositiontaking
        FROM
            bodb02.dbo.bettrans WITH (NOLOCK)
    ),
    Base_Measures AS (
        SELECT
            *,

            scomm                                                                                       AS CommissionS_Orig,
            ISNULL(scomm / NULLIF(1 - tpositiontaking, 0), 0)                                           AS GrossCommission,

            winlost - actual_stake                                                                      AS MemberWinLoss_Orig,
            awinlost + mwinlost + swinlost                                                              AS SMAWinLoss_Orig,

            1 - tpositiontaking                                                                         AS GrossCompanyPT_Orig,
            /*  tpositiontaking + epositiontaking + housepositiontaking = 1
                let tpositiontaking = 1 => epositiontaking = 0 */
            1 - tpositiontaking - epositiontaking                                                       AS NetCompanyPT_Orig,

            CASE WHEN virtualrate > actualrate THEN virtualrate ELSE actualrate END                     AS [Whichever-is-higher Rate],
            CASE WHEN virtualrate < actualrate THEN virtualrate / actualrate ELSE 1 END                 AS VarianceVR,
            actualrate - virtualrate                                                                    AS [aRate - vRate],

            CASE WHEN @IsNoDraw = 1 
                 THEN CASE WHEN (bettype < 999 OR bettype BETWEEN 1301 AND 1399 OR bettype BETWEEN 9001 AND 9399) --SportBooks
                                 AND bettype NOT IN (29, 38, 911, 912, 913, 914) --exclude parlay, bet builder, cashout
                                 AND bettype NOT BETWEEN 81 AND 120 --exclude number game
                                 AND statusID IN (112, 113) --WON, LOSE
                                 AND ABS(modds) = 0.25 --to actually identify tickets that settled as Half won/lost
                           THEN 0.5
                      ELSE 1 END
                 ELSE 1 END                                                                             AS DrawMultiplier
        FROM Source
        WHERE
            (@IsNoDraw = 0 OR (@IsNoDraw = 1 AND statusID NOT IN (111)))
    ),
    Tier2_Measures AS (
        SELECT
            *,
            DrawMultiplier *
                stake * GrossCompanyPT_Orig                                                             AS TurnoverIBC_Orig,
            DrawMultiplier *
                ABS(stake) * NetCompanyPT_Orig                                                          AS NetTurnoverIBC_Orig,
            GrossCommission * epositiontaking                                                           AS [Extra's Commission Orig],
            MemberWinLoss_Orig * epositiontaking                                                        AS [Extra's Winloss Orig]
        FROM Base_Measures
    ),
    Tier3_Measures AS (
        SELECT 
            *,
            (MemberWinLoss_Orig + SMAWinLoss_Orig - [Extra's Winloss Orig] 
            + CASE WHEN VirtualRate < ActualRate 
                    THEN CommissionS_Orig - [Extra's Commission Orig] ELSE 0 END)                         AS VarianceIncome_Orig
        FROM Tier2_Measures
    )
    SELECT /* (rates applied) */ 
        *,
        -- Member winloss before player commission
        MemberWinLoss_Orig                                                  * ActualRate                   AS MemberWinLoss,
        -- Total winloss of super, master, agent    
        SMAWinLoss_Orig                                                     * ActualRate                   AS SMAWinLoss,

        [Extra's Winloss Orig]                                              * 1                            AS [Extra's Winloss],
        
        [Extra's Commission Orig]                                           * 1                            AS [Extra's Commission],
        -- Amount that House pays to/gets from Extra group    
        ([Extra's Winloss Orig] + [Extra's Commission Orig])                * ActualRate                   AS [Extra's Amount],
        -- Commision that House gives to Super level    
        CommissionS_Orig                                                    * ActualRate                   AS CommissionS,
        -- House income from controling virtual rate   
        VarianceIncome_Orig                                                 * [aRate - vRate]              AS VarianceHouseIncome,
        -- House income after ExtraPT and Super commission based on virtual rate   
        (MemberWinLoss_Orig + SMAWinLoss_Orig - [Extra's Winloss Orig])     * VirtualRate    
        + (CommissionS_Orig - [Extra's Commission Orig]) * VarianceVR       * ActualRate                   AS VirtualHouseIncome,
        -- House income after ExtraPT and Super commission based on actual rate   
        (MemberWinLoss_Orig + SMAWinLoss_Orig - [Extra's Winloss Orig]
        + CommissionS_Orig - [Extra's Commission Orig])                     * ActualRate                   AS RealHouseIncome,   
        -- House Turnover after ExtraPT based on virtual rate   
        NetTurnoverIBC_Orig                                                 * VirtualRate                  AS VirtualHouseTurnover,
        -- House Turnover after ExtraPT based on actual rate        
        NetTurnoverIBC_Orig                                                 * [Whichever-is-higher Rate]   AS RealHouseTurnover
        
    FROM Tier3_Measures
)