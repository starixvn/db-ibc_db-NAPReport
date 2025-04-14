/*<info serverAlias="DBACC-bodb02" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
/*
	Creator:	20250402@Robert
	Task: #222345 - Letstalk - No Bets Alert [ReportID 48]
	Database:	DBACC.bodb02 
	
	Revisions:
		- 20250402@Robert: #222345 - Letstalk - No Bets Alert [ReportID 48]		
		
	Parameter's Explaination:
		- @Example:			
		
	Developer's Notes:		
*/

CREATE FUNCTION [dbo].[f_GetLetstalkAlertSports]()
RETURNS @SportSettings TABLE 
(
    ProductId    TINYINT,
    SportType    SMALLINT,
    TimeSetting  VARCHAR(10),
    IsTest       BIT
)
AS
BEGIN    
    INSERT INTO @SportSettings (ProductId, SportType, TimeSetting, IsTest)
    VALUES 
        (5, 180, '10 Mins', 0),
	   (5, 181, '10 Mins', 0),
	   (5, 182, '10 Mins', 0),
	   (5, 183, '10 Mins', 0),
	   (5, 184, '10 Mins', 0),
	   (5, 185, '10 Mins', 0),
	   (5, 186, '10 Mins', 0),
	   (8, 202, '10 Mins', 0),
	   (21, 211, '10 Mins', 0),
	   (27, 177, '10 Mins', 0),
	   (27, 190, '10 Mins', 0),
	   (27, 191, '10 Mins', 0),
	   (27, 192, '10 Mins', 0),
	   (27, 193, '10 Mins', 0),
	   (27, 194, '10 Mins', 0),
	   (27, 195, '10 Mins', 0),
	   (27, 196, '10 Mins', 0),
	   (27, 197, '10 Mins', 0),
	   (27, 198, '10 Mins', 0),
	   (28, 220, '10 Mins', 0),
	   (32, 248, '10 Mins', 0),
	   (39, 244, '10 Mins', 0),
	   (40, 222, '10 Mins', 0),
	   (42, 150, '10 Mins', 0),
	   (42, 200, '10 Mins', 0),
	   (45, 243, '10 Mins', 0),
	   (55, 232, '10 Mins', 0),
	   (60, 237, '10 Mins', 0),
	   (65, 170, '10 Mins', 0),
	   (66, 171, '10 Mins', 0),
	   (66, 173, '10 Mins', 0),
	   (80, 228, '10 Mins', 0),
	   (96, 138, '10 Mins', 0),
	   (6, 208, '30 Mins', 0),
	   (6, 209, '30 Mins', 0),
	   (6, 210, '30 Mins', 0),
	   (6, 251, '30 Mins', 0),
	   (22, 212, '30 Mins', 0),
	   (34, 165, '30 Mins', 0),
	   (36, 247, '30 Mins', 0),
	   (46, 242, '30 Mins', 0),
	   (57, 239, '30 Mins', 0),
	   (61, 238, '30 Mins', 0),
	   (73, 155, '30 Mins', 0),
	   (75, 158, '30 Mins', 0),
	   (76, 159, '30 Mins', 0),
	   (85, 229, '30 Mins', 0),
	   (87, 230, '30 Mins', 0),
	   (89, 146, '30 Mins', 0),
	   (91, 143, '30 Mins', 0),
	   (100, 148, '30 Mins', 0),
	   (103, 130, '30 Mins', 0),
	   (3, 161, '60 Mins', 0),
	   (3, 164, '60 Mins', 0),
	   (3, 168, '60 Mins', 0),
	   (38, 245, '60 Mins', 0),
	   (48, 145, '60 Mins', 0),
	   (51, 233, '60 Mins', 0),
	   (52, 225, '60 Mins', 0),
	   (56, 234, '60 Mins', 0),
	   (90, 144, '60 Mins', 0),
	   (95, 139, '60 Mins', 0),
	   (102, 133, '60 Mins', 0),
	   (107, 124, '60 Mins', 0),
	   (62, 167, '60 Mins', 0),
	   (63, 169, '60 Mins', 0),
	   (67, 172, '60 Mins', 0),
	   (70, 176, '60 Mins', 0),
	   (72, 156, '60 Mins', 0),
	   (77, 178, '60 Mins', 0),
	   (77, 179, '60 Mins', 0),
	   (78, 216, '60 Mins', 0),
	   (79, 227, '60 Mins', 0),
	   (83, 188, '60 Mins', 0),
	   (86, 240, '60 Mins', 0),
	   (88, 147, '60 Mins', 0),
	   (104, 131, '60 Mins', 0),
	   (106, 125, '60 Mins', 1),
	   (106, 126, '60 Mins', 1),
	   (106, 127, '60 Mins', 1),
	   (108, 123, '60 Mins', 1);

    RETURN;
END
GO