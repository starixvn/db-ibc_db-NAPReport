USE bodb02;
GO

ALTER VIEW dbo.v_ActionIDBettype
AS
/*	Created by:  
	Date: 20160620
	Task: Add More Actions of Settlement to Daily Turnover Report (#57781)
	DB: DBACC/bobd02

	Revisions:
	   20170815@Tom: Add some bettype missing (#81287)
	   20170926@Tom: Add New Bet Types with Decimal Odds only (#83778)
*/

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Calculate All- Soccer and Others (1H)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Calculate All- Soccer and Others (FT)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Calculate All- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Calculate All- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Calculate All- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('153,154,155,156,1301,1302,1303,1305,1306,1308,1311,1312,1316,1317,1318,1324',',')
	    ) b --Calculate All- Tennis

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Calculate All- Soccer and Others (2H)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Calculate All- Soccer» Goals (FT)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Calculate All- Soccer» Corner (FT)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Calculate All- Soccer» Corner (1H)

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('501',',')
	    ) b --Calculate All- Cricket

    UNION ALL

    SELECT 100 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('601,602,603,605,608,609,610,611,612,614,615,616,617',',')
	    ) b --Calculate All- Basketball

    UNION ALL

    SELECT 101 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Calculate FT- Soccer and Others (FT)

    UNION ALL

    SELECT 101 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Calculate FT- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 101 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Calculate FT- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 101 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Calculate FT- Soccer and Others (2H)

    UNION ALL

    SELECT 101 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Calculate FT- Soccer» Goals (FT)

    UNION ALL

    SELECT 101 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Calculate FT- Soccer» Corner (FT)

    UNION ALL

    SELECT 102 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Calculate HT- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 102 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Calculate HT- Soccer» Corner (1H)

    UNION ALL

    SELECT 102 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Calculate HT- Soccer and Others (1H)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Undo Settlement- Soccer and Others (FT)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Undo Settlement- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Undo Settlement- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Undo Settlement- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('153,154,155,156,1301,1302,1303,1305,1306,1308,1311,1312,1316,1317,1318,1324',',')
	    ) b --Undo Settlement- Tennis

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Undo Settlement- Soccer and Others (2H)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Undo Settlement- Soccer» Goals (FT)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Undo Settlement- Soccer» Corner (FT)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Undo Settlement- Soccer» Corner (1H)

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('501',',')
	    ) b --Undo Settlement- Cricket

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('601,602,603,605,608,609,610,611,612,614,615,616,617',',')
	    ) b --Undo Settlement- Basketball

    UNION ALL

    SELECT 103 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Undo Settlement- Soccer and Others (1H)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Refund All- Soccer and Others (FT)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Refund All- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Refund All- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Refund All- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('153,154,155,156,1301,1302,1303,1305,1306,1308,1311,1312,1316,1317,1318,1324',',')
	    ) b --Refund All- Tennis

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Refund All- Soccer and Others (2H)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Refund All- Soccer» Goals (FT)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Refund All- Soccer» Corner (FT)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Refund All- Soccer» Corner (1H)

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('501',',')
	    ) b --Refund All- Cricket

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('601,602,603,605,608,609,610,611,612,614,615,616,617',',')
	    ) b --Refund All- Basketball

    UNION ALL

    SELECT 109 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Refund All- Soccer and Others (1H)

    UNION ALL

    SELECT 110 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Refund HT- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 110 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Refund HT- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 110 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Refund HT- Soccer and Others (2H)

    UNION ALL

    SELECT 110 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Refund HT- Soccer» Corner (1H)

    UNION ALL

    SELECT 110 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414',',')
	    ) b --Refund HT- Soccer and Others (1H)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Refund FT- Soccer and Others (FT)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Refund FT- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Refund FT- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Refund FT- Soccer and Others (2H)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Refund FT- Soccer» Goals (FT)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Refund FT- Soccer» Corner (FT)

    UNION ALL

    SELECT 111 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('501',',')
	    ) b --Refund FT- Cricket

    UNION ALL

    SELECT 112 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14,127',',')
	    ) b --Refund FGLG- First Goal/Last Goal

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Refund Running Betdaq Tickets- Soccer and Others (FT)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Refund Running Betdaq Tickets- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Refund Running Betdaq Tickets- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Refund Running Betdaq Tickets- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Refund Running Betdaq Tickets- Soccer and Others (2H)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Refund Running Betdaq Tickets- Soccer» Goals (FT)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Refund Running Betdaq Tickets- Soccer» Corner (FT)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Refund Running Betdaq Tickets- Soccer» Corner (1H)

    UNION ALL

    SELECT 126 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Refund Running Betdaq Tickets- Soccer and Others (1H)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Refund Running Betfair Tickets- Soccer and Others (FT)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Refund Running Betfair Tickets- Soccer» FG/LG (1H)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Refund Running Betfair Tickets- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Refund Running Betfair Tickets- Soccer» FG/LG (FT)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Refund Running Betfair Tickets- Soccer and Others (2H)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Refund Running Betfair Tickets- Soccer» Goals (FT)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Refund Running Betfair Tickets- Soccer» Corner (FT)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Refund Running Betfair Tickets- Soccer» Corner (1H)

    UNION ALL

    SELECT 135 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Refund Running Betfair Tickets- Soccer and Others (1H)

    UNION ALL

    SELECT 148 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('135,160,164,168,169,173,174,175,176,180,192,193,210,211,212,213,214,215,216,217,424',',')
	    ) b --Auto settlement - Calculate- Auto-settled

    UNION ALL

    SELECT 149 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('135,160,164,168,169,173,174,175,176,180,192,193,210,211,212,213,214,215,216,217,424',',')
	    ) b --Auto settlement - Undo- Auto-settled

    UNION ALL

    SELECT 150 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('135,160,164,168,169,173,174,175,176,180,192,193,210,211,212,213,214,215,216,217,424',',')
	    ) b --Auto settlement - Refund- Auto-settled

    UNION ALL

    SELECT 151 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Calculate Corner- Corners (FT)

    UNION ALL

    SELECT 151 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Calculate Corner- Corners (1H)

    UNION ALL

    SELECT 152 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('801,803,804,805,806',',')
	    ) b --Super Live - Calculate- Super Live

    UNION ALL

    SELECT 153 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('801,803,804,805,806',',')
	    ) b --Super Live - Undo- Super Live

    UNION ALL

    SELECT 154 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('801,803,804,805,806',',')
	    ) b --Super Live - Refund- Super Live

    UNION ALL

    SELECT 157 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('7,8,12,15,21,30,125,126,129,136,138,143,151,165,167,179,181,182,188,191,303,304,403,404,410,411,412,414,426,427,463,464',',')
	    ) b --Auto Payout - Calculate HT- Soccer and Others (1H)

    UNION ALL

    SELECT 158 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('1,2,3,4,5,6,13,16,20,24,25,26,27,28,121,122,123,124,130,131,132,133,134,137,139,144,145,157,159,161,162,163,166,170,171,301,302,401,402,406,407,408,409,413,417,418,461,462',',')
	    ) b --Auto Payout - Calculate FT- Soccer and Others (FT)

    UNION ALL

    SELECT 158 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('128,140,141,142,147,148,149,150,152,189,190,416,419,420,421,434,435,436,437,438,439,440,441,442,443,444,445,446,447',',')
	    ) b --Auto Payout - Calculate FT- Soccer (HT/FT,Both Halves)

    UNION ALL

    SELECT 158 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('17,18,146,177,178,183,184,185,186,187,405,428,429,430,431,432,433',',')
	    ) b --Auto Payout - Calculate FT- Soccer and Others (2H)

    UNION ALL

    SELECT 161 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('194,195,196,197,198,199,206,208',',')
	    ) b --Calculate FT Corner- Corners (FT)

    UNION ALL

    SELECT 162 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('200,201,202,203,204,205,207,209',',')
	    ) b --Calculate HT Corner- Corners (1H)

    UNION ALL

    SELECT 163 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('14',',')
	    ) b --Calculate FT - FGLG- FT First Goal/Last Goal

    UNION ALL

    SELECT 163 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('172,415,422,423,425',',')
	    ) b --Calculate FT - FGLG- Soccer» Goals (FT)

    UNION ALL

    SELECT 164 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('127',',')
	    ) b --Calculate HT - FGLG- 1H First Goal/Last Goal

    UNION ALL

    SELECT 165 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('221,222,223,224,225',',')
	    ) b --Auto settlement - Fast market - Calculate- Fast Markets

    UNION ALL

    SELECT 166 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('221,222,223,224,225',',')
	    ) b --Auto settlement - Fast market - Undo- Fast Markets

    UNION ALL

    SELECT 167 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('221,222,223,224,225',',')
	    ) b --Auto settlement - Fast market - Refund- Fast Markets

    UNION ALL

    SELECT 189 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('604,606,607,613',',')
	    ) b --Early Settlement- Calculate- Basketball early settled

    UNION ALL

    SELECT 190 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('604,606,607,613',',')
	    ) b --Early Settlement- Uncalculate- Basketball early settled

    UNION ALL

    SELECT 191 AS ActionID
	    ,strbettye
    FROM (
	    SELECT val AS strbettye
	    FROM bodb02.dbo.strSplit('604,606,607,613',',')
	    ) b --Early Settlement- Refund- Basketball early settled




GO
GRANT SELECT ON [dbo].v_ActionIDBettype TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].v_ActionIDBettype TO [vnteam] AS [dbo]