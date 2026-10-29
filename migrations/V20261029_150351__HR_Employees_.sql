IF COL_LENGTH('dbo.HR_Employees', 'Sub_Account') IS NULL
    ALTER TABLE dbo.HR_Employees ADD Sub_Account NVARCHAR(100) NULL;
GO
