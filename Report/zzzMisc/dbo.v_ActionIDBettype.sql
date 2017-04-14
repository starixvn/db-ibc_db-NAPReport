USE [bodb02]
GO
/****** Object:  View [dbo].[v_ActionIDBettype]    Script Date: 06/07/2016 13:02:53 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER view [dbo].[v_ActionIDBettype]
AS 
/*	Created by:  
	Date: 20160620
	Task: Add More Actions of Settlement to Daily Turnover Report (#57781)
	DB: DBACC/bobd02
	
*/

SELECT  100 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 129,136,138,143,151,165,167,179,181,182,188,191,200,201,202,203,204,205,207,209,303,304,403,404,410,411,412,414,17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157, 159, 161, 162, 163, 166, 170, 171, 172,189,190,194,195,196,197,198,199,206,208,301,302,401,402, 406, 407, 408, 409, 413,153, 154, 155, 156, 1301, 1302, 1303, 1305, 1306, 1308, 1311, 1312, 1316, 1317, 1318, 1324,501',',') 
				)b
UNION 

SELECT  101 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157,159, 161, 162, 163, 166, 170, 171, 172, 189, 190, 194, 195, 196, 197, 198, 199, 206, 208, 301, 302, 401, 402, 406, 407, 408, 409, 413',',') 
																				)b
UNION 																				
SELECT  102 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191, 200, 201, 202, 203, 204, 205, 207, 209,303, 304, 403, 404, 410, 411,412,414',',') 
 																)b
UNION 
SELECT  103 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 127, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191, 200, 201, 202, 203, 204, 205, 207, 209, 303, 304, 403, 404, 410, 411, 412, 414,17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 14, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157,159, 161, 162, 163, 166, 170, 171, 172, 189, 190, 194, 195, 196, 197, 198, 199, 206, 208, 301, 302, 401, 402, 406, 407, 408, 409, 413,153, 154, 155, 156, 1301, 1302, 1303, 1305, 1306, 1308, 1311, 1312, 1316, 1317, 1318, 1324,501',',') 
 																)b	
UNION 
SELECT  109 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191, 200, 201, 202, 203, 204, 205, 207, 209,303, 304, 403, 404, 410, 411, 412, 414,17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157,159, 161, 162, 163, 166, 170, 171, 172, 189, 190, 194, 195, 196, 197, 198, 199, 206, 208, 301, 302, 401, 402, 406, 407, 408, 409, 413,153, 154, 155, 156, 1301, 1302, 1303, 1305, 1306, 1308, 1311, 1312, 1316, 1317, 1318, 1324,501',',') 
																 )b	
UNION 
SELECT  110 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191, 200, 201, 202, 203, 204, 205, 207, 209,303, 304, 403, 404, 410, 411, 412, 414,17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,128, 140, 141, 142, 147, 148, 149, 150, 152, 189, 190',',') 
																 )b																	 
UNION 
SELECT  111 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157,159, 161, 162, 163, 166, 170, 171, 172, 189, 190, 194, 195, 196, 197, 198, 199, 206, 208, 301, 302, 401, 402, 406, 407, 408, 409, 413,501',',') 
																 )b	
UNION 
SELECT  112 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('14, 127',',') 
																 )b		
UNION 
SELECT  126 AS ActionID, -- Just only Betdaq tickets.
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191, 200, 201, 202, 203, 204, 205, 207, 209, 303, 304, 403, 404, 410, 411, 412, 414,17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157, 159, 161, 162, 163, 166, 170, 171, 172, 189, 190, 194, 195, 196, 197, 198, 199, 206, 208, 301, 302, 401, 402, 406, 407, 408, 409, 413',',') 
																 )b		
UNION 
SELECT  135 AS ActionID,-- Just only Betfair tickets.
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit( '7, 8, 12, 15, 21, 30, 125, 126, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191, 200, 201, 202, 203, 204, 205, 207, 209, 303, 304, 403, 404, 410, 411, 412, 414,17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157, 159, 161, 162, 163, 166, 170, 171, 172, 189, 190, 194, 195, 196, 197, 198, 199, 206, 208, 301, 302, 401, 402, 406, 407, 408, 409, 413',',') 
																 )b																	 
UNION 
SELECT  148 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('135, 160, 164, 168, 169, 173, 174, 175, 176, 180, 192, 193, 210, 211, 212, 213, 214, 215, 216, 217',',') 
																 )b		
UNION 
SELECT  149 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('135, 160, 164, 168, 169, 173, 174, 175, 176, 180, 192, 193, 210, 211, 212, 213, 214, 215, 216, 217',',') 
																 )b	
UNION 
SELECT  150 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('135, 160, 164, 168, 169, 173, 174, 175, 176, 180, 192, 193, 210, 211, 212, 213, 214, 215, 216, 217',',') 
																 )b
UNION 
SELECT  151 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('200, 201, 202, 203, 204, 205, 207, 209,194, 195, 196, 197, 198, 199, 206, 208',',') 
																 )b		
UNION 
SELECT  152 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('801,803, 804, 805, 806',',') 
																 )b	
UNION 
SELECT  153 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('801,803, 804, 805, 806',',') 
																 )b	
UNION 
SELECT  154 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('801,803, 804, 805, 806',',') 
																 )b		
UNION 
SELECT  157 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('7, 8, 12, 15, 21, 30, 125, 126, 129, 136, 138, 143, 151, 165, 167, 179, 181, 182, 188, 191,303, 304, 403, 404, 410, 411, 412, 414',',') 
																 )b			
UNION 
SELECT  158 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('17, 18, 146, 177, 178, 183, 184, 185, 186, 187, 405,1, 2, 3, 4, 5, 6, 13, 16, 20, 24, 25, 26, 27, 28, 121, 122, 123, 124, 128, 130, 131, 132, 133, 134, 137, 139, 140, 141, 142, 144, 145, 147, 148, 149, 150, 152, 157,159, 161, 162, 163, 166, 170, 171, 172, 189, 190,301, 302, 401, 402, 406, 407, 408, 409, 413',',') 
																 )b	
UNION 
SELECT  161 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('194, 195, 196, 197, 198, 199, 206, 208',',') 
																 )b			
UNION 
SELECT  162 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('200, 201, 202, 203, 204, 205, 207, 209',',') 
																 )b	
UNION 
SELECT  163 AS ActionID,
		CONVERT(INT,14) strbettye 
UNION 
SELECT  164 AS ActionID,
		CONVERT(INT,127) strbettye 	
UNION 
SELECT  165 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('221, 222, 223, 224',',') 
																 )b	
UNION 
SELECT  166 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('221, 222, 223, 224',',') 
																 )b
UNION 
SELECT  167 AS ActionID,
		strbettye FROM
				(SELECT val AS strbettye FROM
											bodb02.dbo.strSplit('221, 222, 223, 224',',') 
																 )b																	 
GO
GRANT SELECT ON [dbo].[v_ActionIDBettype] TO [bodbAdminNet]  
GO
GRANT VIEW DEFINITION ON [dbo].[v_ActionIDBettype] TO [vnteam]  


