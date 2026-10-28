IF COL_LENGTH('dbo.GL_Accounts', 'Branch_ID') IS NULL
    ALTER TABLE dbo.GL_Accounts ADD Branch_ID INT NULL;


