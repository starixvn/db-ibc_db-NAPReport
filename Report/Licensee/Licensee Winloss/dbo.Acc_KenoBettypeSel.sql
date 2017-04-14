USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Acc_KenoBettypeSel]
AS
/*
Created: Kyan
Task : Get bettype for Keno
DB: DBEXT/bodb02 
	* Revision:
				+20140602@Jim: put NOLOCK after SELECT command
				+20140702@Jim:add more filter to not show disable bettype
*/
SET NOCOUNT ON

SELECT typeid AS BettypeId
	 ,typenamee AS BettypeName
FROM dbo.bettype b  WITH (NOLOCK)
	INNER JOIN GameType g WITH (NOLOCK) ON b.typeid=g.IBCBetTypeID
WHERE b.typeid between 1501 and 1599
	AND g.IsDisabled=0

GO
GRANT EXECUTE ON [dbo].[Acc_KenoBettypeSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Acc_KenoBettypeSel] TO [vnteam]
