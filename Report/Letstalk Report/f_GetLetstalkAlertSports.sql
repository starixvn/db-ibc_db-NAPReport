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
	   (28, 220, '10 Mins', 0),
	   (55, 232, '10 Mins', 0),
	   (32, 248, '10 Mins', 0),
	   (65, 170, '10 Mins', 0),
	   (8, 202, '10 Mins', 0),
	   (39, 244, '10 Mins', 0),
	   (42, 150, '10 Mins', 0),
	   (42, 200, '10 Mins', 0),
	   (66, 171, '10 Mins', 0),
	   (66, 173, '10 Mins', 0),
	   (5, 180, '10 Mins', 0),
	   (5, 181, '10 Mins', 0),
	   (5, 182, '10 Mins', 0),
	   (5, 183, '10 Mins', 0),
	   (5, 184, '10 Mins', 0),
	   (5, 185, '10 Mins', 0),
	   (5, 186, '10 Mins', 0),
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
	   (45, 243, '15 Mins', 0),
	   (21, 211, '15 Mins', 0),
	   (60, 237, '15 Mins', 0),
	   (96, 138, '15 Mins', 0),
	   (40, 222, '15 Mins', 0),
	   (80, 228, '15 Mins', 0),
	   (34, 165, '60 Mins', 0),
	   (103, 130, '60 Mins', 0),
	   (57, 239, '60 Mins', 0),
	   (89, 146, '60 Mins', 0),
	   (87, 230, '60 Mins', 0),
	   (61, 238, '60 Mins', 0),
	   (46, 242, '60 Mins', 0),
	   (75, 158, '60 Mins', 0),
	   (22, 212, '60 Mins', 0),
	   (73, 155, '60 Mins', 0),
	   (85, 229, '60 Mins', 0),
	   (91, 143, '60 Mins', 0),
	   (100, 148, '60 Mins', 0),
	   (6, 208, '60 Mins', 0),
	   (6, 209, '60 Mins', 0),
	   (6, 210, '60 Mins', 0),
	   (6, 251, '60 Mins', 0),
	   (36, 247, '60 Mins', 0),
	   (76, 159, '60 Mins', 0),
	   (67, 172, '90 Mins', 0),
	   (62, 167, '90 Mins', 0),
	   (70, 176, '90 Mins', 0),
	   (104, 131, '90 Mins', 0),
	   (48, 145, '90 Mins', 0),
	   (90, 144, '90 Mins', 0),
	   (52, 225, '90 Mins', 0),
	   (56, 234, '90 Mins', 0),
	   (79, 227, '90 Mins', 0),
	   (3, 161, '90 Mins', 0),
	   (3, 164, '90 Mins', 0),
	   (3, 168, '90 Mins', 0),
	   (86, 240, '90 Mins', 0),
	   (72, 156, '90 Mins', 0),
	   (63, 169, '90 Mins', 0),
	   (78, 216, '90 Mins', 0),
	   (38, 245, '90 Mins', 0),
	   (77, 178, '90 Mins', 0),
	   (77, 179, '90 Mins', 0),
	   (83, 188, '90 Mins', 0),
	   (88, 147, '90 Mins', 0),
	   (51, 233, '90 Mins', 0),
	   (102, 133, '90 Mins', 0),
	   (95, 139, '90 Mins', 0),
	   (98, 136, '90 Mins', 0),
	   (107, 124, '90 Mins', 0),
	   (106, 125, '90 Mins', 0),
	   (106, 126, '90 Mins', 0),
	   (106, 127, '90 Mins', 0),
	   (108, 123, '90 Mins', 0),
	   (101, 129, '90 Mins', 0);
    RETURN;
END
GO