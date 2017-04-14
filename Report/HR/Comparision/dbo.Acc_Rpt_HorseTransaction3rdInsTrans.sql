USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[Acc_DumpBettransInsTransaction]    Script Date: 05/21/2010 09:19:35 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[Acc_Rpt_HorseTransaction3rdInsTrans]
@transdate DATETIME = null,
@merchantname varchar(50) = null,
@provider VARCHAR(50) = null,
@transid BIGINT = null,
@poolid BIGINT = null,
@meetingname VARCHAR(100) = null,
@bettype VARCHAR(50) = null,
@race VARCHAR(50) = null,
@formattedselection VARCHAR(100) = null,
@betoption VARCHAR(50) = null,
@totetransid VARCHAR(100) = null,
@currency VARCHAR(50) = null,
@stake money = null,
@cost money = null,
@payout money = null,
@othercurrency VARCHAR(50) = null,
@othercost money = null,
@otherpayout money = null,
@cancelamount money = null,
@reconciled VARCHAR(1) = null,
@cancelled VARCHAR(1) = null,
@isrefund VARCHAR(1)= null,
@ispayout VARCHAR(1) = null,
@clientcashed VARCHAR(5) = null,
@refmerchant VARCHAR(50) = null,
@status VARCHAR(10) = null,
@rate FLOAT = null

AS

/*
    Created by: @KhoaTran
    Date: 20100430
    Task: Insert transactions's I-neda
    DB: DB06.BODB02
   
    Revisions:
       
 */

INSERT INTO Acc_HorseTransaction3rd
           (                
               transdate
			   ,merchantname
               ,provider
               ,transid
               ,poolid
               ,meetingname
               ,bettype
               ,race
               ,formattedselection
               ,betoption
               ,totetransid
               ,currency
               ,stake
               ,cost
               ,payout
               ,othercurrency
               ,othercost
               ,otherpayout
               ,cancelamount
               ,reconciled
               ,cancelled
               ,isrefund
               ,ispayout
               ,clientcashed
               ,refmerchant
               ,status
               ,rate
            )
     VALUES
           (
                @transdate ,
				@merchantname,
                @provider ,
                @transid ,
                @poolid ,
                @meetingname ,
                @bettype ,
                @race ,
                @formattedselection ,
                @betoption ,
                @totetransid ,
                @currency ,
                @stake ,
                @cost ,
                @payout ,
                @othercurrency ,
                @othercost ,
                @otherpayout ,
                @cancelamount ,
                @reconciled ,
                @cancelled ,
                @isrefund ,
                @ispayout ,
                @clientcashed ,
                @refmerchant ,
                @status ,
                @rate
            )

GO
GRANT EXECUTE ON [dbo].[Acc_Rpt_HorseTransaction3rdInsTrans] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_Rpt_HorseTransaction3rdInsTrans] TO [vnteam]