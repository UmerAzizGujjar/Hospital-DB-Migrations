USE [pakred_uat];
GO

CREATE OR ALTER PROCEDURE dbo.GetAllPatients
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT * 
    FROM dbo.Patients;
END;
GO
