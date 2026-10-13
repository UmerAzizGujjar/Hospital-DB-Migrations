# Database Migrations

This folder contains version-controlled SQL Server database migration scripts for the Hospital ERP.

## Rules
- Use one new `.sql` file for each database change.
- Never modify a migration that has already been applied.
- Test every migration before production deployment.
- Never store passwords, connection strings, or patient data in this repository.
- Production deployment remains disabled until backups and restore procedures are verified.
