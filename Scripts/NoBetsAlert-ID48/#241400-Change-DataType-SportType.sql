
/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/

/*
	Creator:	20251020@Robert
	Task:	#241400-Change-DataType-SportType

	Database:	DBACC.bodb02
	
	Revisions:
		- #241400-Change-DataType-SportType
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

-- Script to change SportType column data type from tinyint to smallint
-- in table LetstalkAlertSports

-- Step 1: Check current data type and constraints
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'LetstalkAlertSports' 
    AND COLUMN_NAME = 'SportType';

-- Step 2: Check for any indexes on SportType column
SELECT 
    i.name AS IndexName,
    i.type_desc AS IndexType,
    c.name AS ColumnName
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID('dbo.LetstalkAlertSports')
    AND c.name = 'SportType';

-- Step 3: Check current data range to ensure compatibility
SELECT 
    MIN(SportType) AS MinValue,
    MAX(SportType) AS MaxValue,
    COUNT(*) AS TotalRows,
    COUNT(DISTINCT SportType) AS DistinctValues
FROM [dbo].[LetstalkAlertSports];

-- Step 4: Alter the column data type from tinyint to smallint
ALTER TABLE [dbo].[LetstalkAlertSports]
ALTER COLUMN SportType smallint NOT NULL;

-- Step 5: Verify the change
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'LetstalkAlertSports' 
    AND COLUMN_NAME = 'SportType';

PRINT 'SportType column data type has been successfully changed from tinyint to smallint';