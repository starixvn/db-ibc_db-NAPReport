
/*<info serverAlias="DBACC-bodb02" executers="" isFunction="0"></info>*/

/*
    Created: 20250414@Robert
	Task:Create System Setting Key No Bet sAlert [Redmine:#223831]
	DB: DBACC-bodb02
*/

USE [bodb02];
GO

DECLARE 
	@Sid    BIGINT
   , @SidRNG BIGINT
   , @SidLC  BIGINT;

SELECT 
	  @Sid = MAX(b.sequenceid)
FROM bettrans b WITH(NOLOCK);

SELECT 
	  @SidRNG = MAX(b.sequenceid)
FROM bettransRnG b WITH(NOLOCK);

SELECT 
	  @SidLC = MAX(b.sequenceid)
FROM bettransLC b WITH(NOLOCK);


INSERT INTO SystemSettings
   (
	  VName, 
	  VValue
   )
	  SELECT 
		    'Bettrans_NoBetsAlert' VName, 
		    @Sid VValue
	  UNION ALL
	  SELECT 
		    'BettransRNG_NoBetsAlert' VName, 
		    @SidRNG VValue
	  UNION ALL
	  SELECT 
		    'BettransLC_NoBetsAlert' VName, 
		    @SidLC VValue;

