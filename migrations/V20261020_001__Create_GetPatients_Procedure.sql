-- Create a stored procedure to retrieve all patients
-- Note: NO 'USE' statement is included here, as your Jenkins pipeline handles database targeting automatically.

CREATE OR ALTER PROCEDURE dbo.GetPatients
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM patients;
END
GO
