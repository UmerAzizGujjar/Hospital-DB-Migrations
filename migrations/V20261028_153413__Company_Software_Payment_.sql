IF OBJECT_ID('dbo.Company_Software_Payment', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Company_Software_Payment
    (
        Payment_ID    INT IDENTITY(1,1) NOT NULL,
        Company_ID    INT NOT NULL,
        Payment_Year  SMALLINT NOT NULL,
        Payment_Month TINYINT NOT NULL,
        Is_Received   BIT NOT NULL CONSTRAINT DF_Company_Software_Payment_Is_Received DEFAULT (0),
        Received_Date DATETIME NULL,
        Created_By    UNIQUEIDENTIFIER NULL,
        Created_Time  DATETIME NULL CONSTRAINT DF_Company_Software_Payment_Created_Time DEFAULT (GETDATE()),
        Updated_By    UNIQUEIDENTIFIER NULL,
        Updated_Time  DATETIME NULL,
        CONSTRAINT PK_Company_Software_Payment PRIMARY KEY CLUSTERED (Payment_ID),
        CONSTRAINT UQ_Company_Software_Payment UNIQUE (Company_ID, Payment_Year, Payment_Month),
        CONSTRAINT CK_Company_Software_Payment_Month CHECK (Payment_Month BETWEEN 1 AND 12),
        CONSTRAINT FK_Company_Software_Payment_Company FOREIGN KEY (Company_ID) REFERENCES dbo.sys_Companys (Company_ID)
    );
END
GO
