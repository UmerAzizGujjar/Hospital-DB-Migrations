-- ============================================================================
-- Migration: V20261014_001__test_add_column.sql
-- Purpose  : Safely test Jenkins pipeline table creation and ADD COLUMN
-- Target DB: STH_U_ASIRAAT
-- ============================================================================

-- Batch 1: Create an isolated test table if it does not already exist
IF OBJECT_ID('dbo.Jenkins_Migration_Test', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Jenkins_Migration_Test (
        TestId INT IDENTITY(1,1) PRIMARY KEY,
        TestName NVARCHAR(100) NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Batch 2: Add a new column (Remarks) to the test table
IF COL_LENGTH('dbo.Jenkins_Migration_Test', 'Remarks') IS NULL
BEGIN
    ALTER TABLE dbo.Jenkins_Migration_Test
    ADD Remarks NVARCHAR(250) NULL;
END
GO

-- Batch 3: Insert a verification record using the newly added column
INSERT INTO dbo.Jenkins_Migration_Test (TestName, Remarks)
VALUES (N'Jenkins Pipeline Test', N'Added Remarks column via V20261014_001');
GO
