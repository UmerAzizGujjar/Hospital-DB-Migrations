-- Voucher.aspx: branch selected on the voucher (user-wise list from Branch_Wise_User_Detail -> Branch.branch_ID)
IF COL_LENGTH('dbo.GL_Vouchers', 'Branch_Id') IS NULL
    ALTER TABLE dbo.GL_Vouchers ADD Branch_Id INT NULL;
GO,
