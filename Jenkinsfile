// Global variable to hold the list of discovered files
def discoveredFilesList = []

// Shared helper function for the safety scan
@NonCPS
def scanSqlSafety(String rawSql) {
    if (!rawSql || rawSql.trim() == "") return [error: "File is empty or whitespace-only."]
    if (rawSql.contains("\u0000")) return [error: "Null bytes detected. File may be binary."]

    def errors = []
    
    // Strip comments and strings to prevent false positives in the scanner
    def cleanSql = rawSql.replaceAll(/(?s)('(?:[^']|'')*')|(\/\*.*?\*\/)|(--[^\r\n]*)/) { match ->
        def text = match instanceof List ? match[0] : match.toString()
        if (text.startsWith("'")) return "''"
        return " "
    }

    def statements = cleanSql.split(/(?im)^\s*GO\s*$|;/)

    for (stmt in statements) {
        def s = stmt.trim()
        if (!s) continue
        
        if (s =~ /(?i)\bDROP\s+(TABLE|DATABASE|PROCEDURE|VIEW|INDEX|SCHEMA)\b/) {
            errors << "Destructive command 'DROP' is prohibited."
        }
        if (s =~ /(?i)\bTRUNCATE\s+TABLE\b/) {
            errors << "Destructive command 'TRUNCATE TABLE' is prohibited."
        }
        if (s =~ /(?i)\bDELETE\b/) {
            errors << "'DELETE' statements are prohibited in schema migrations."
        }
        if (s =~ /(?i)\bALTER\s+TABLE\s+.*?\bDROP\s+COLUMN\b/) {
            errors << "'ALTER TABLE ... DROP COLUMN' is restricted to prevent data loss."
        }
        if (s =~ /(?i)\bGRANT\b|\bREVOKE\b|\bDENY\b/) {
            errors << "Permission modification commands are prohibited."
        }
    }
    
    if (!errors.isEmpty()) return [error: errors.join(" | ")]
    return [error: null]
}

pipeline {
    agent none 

    parameters {
        choice(name: 'HOSPITAL', 
               choices: ['PAKRED'], 
               description: '<b>Target Environment:</b> Select the isolated hospital environment.')
               
        string(name: 'TARGET_DATABASE', 
               defaultValue: 'pakred_uat', 
               description: '<b>Database Name:</b> Enter the target SQL Server database.')
               
        choice(name: 'EXECUTION_MODE',
               choices: ['DRY_RUN_ROLLBACK', 'COMMIT_CHANGES', 'HEALTH_CHECK_ONLY'],
               description: '<b>Mode:</b><br>DRY_RUN_ROLLBACK: Test inside a transaction and revert.<br>COMMIT_CHANGES: Apply permanently.<br>HEALTH_CHECK_ONLY: Connectivity test.')
    }

    environment {
        AGENT_LABEL = "${params.HOSPITAL == 'PAKRED' ? 'PAKRED_LIVE_SERVER' : 'UNMAPPED_NODE'}"
        DB_SERVER_HOSTNAME = "WIN-APTS20MHM62"
        SQL_CREDENTIAL_ID = "sql-credentials-${params.HOSPITAL.toLowerCase()}" 
        REGEX_PATTERN = '^(V\\d{8}_\\d{3})__[a-zA-Z0-9_]+\\.sql$'
    }

    stages {
        stage('Checkout & File Discovery') {
            agent { label "${AGENT_LABEL}" }
            steps {
                script {
                    if (env.AGENT_LABEL == 'UNMAPPED_NODE') {
                        error("Security Exception: Hospital '${params.HOSPITAL}' lacks an approved node mapping.")
                    }
                }
                
                // Explicit Git checkout using your GitHub credential ID
                git branch: 'main', 
                    credentialsId: 'f2d6a7df-0fbc-46ae-a972-2aeb85e24bba', 
                    url: 'https://github.com/UmerAzizGujjar/Hospital-DB-Migrations.git'
                
                script {
                    def psOutput = powershell(script: '''
                        $ErrorActionPreference = 'Stop'
                        if (Test-Path "migrations") {
                            Get-ChildItem -Path "migrations" -Filter "*.sql" -Name
                        }
                    ''', returnStdout: true).trim()

                    discoveredFilesList = psOutput.split('\r?\n').collect { it.trim() }.findAll { it }

                    if (discoveredFilesList.isEmpty()) {
                        error "Validation Failed: No SQL files found in the 'migrations' directory."
                    }
                    
                    echo "Found ${discoveredFilesList.size()} migration files."
                }
            }
        }

        stage('Select Migration') {
            agent none 
            steps {
                script {
                    def selectedFile = input(
                        message: "Select a Migration File to deploy to ${params.TARGET_DATABASE}:",
                        parameters: [
                            choice(name: 'FILE_CHOICE', choices: discoveredFilesList, description: 'Select the script you wish to execute.')
                        ]
                    )
                    
                    env.SELECTED_FILENAME = selectedFile
                    env.MIGRATION_SCRIPT = "migrations\\${selectedFile}"
                    
                    echo "User selected: ${env.MIGRATION_SCRIPT}"
                }
            }
        }

        stage('Validation & Safety Scan') {
            agent { label "${AGENT_LABEL}" }
            steps {
                script {
                    if (!(env.SELECTED_FILENAME ==~ env.REGEX_PATTERN)) {
                        error "Validation Failed: Filename '${env.SELECTED_FILENAME}' does not match pattern (VYYYYMMDD_NNN__description.sql)."
                    }

                    if (!fileExists(env.MIGRATION_SCRIPT)) {
                        error "Validation Failed: File ${env.MIGRATION_SCRIPT} not found."
                    }

                    def rawSql = readFile(file: env.MIGRATION_SCRIPT, encoding: 'UTF-8')
                    def scanResult = scanSqlSafety(rawSql)
                    
                    if (scanResult.error) {
                        error "SECURITY VIOLATION: Migration failed safety policy -> ${scanResult.error}"
                    }
                    echo "Validation & Safety Scan Passed. File is safe."
                }
            }
        }

        stage('Manual Approval') {
            agent none 
            steps {
                script {
                    if (params.EXECUTION_MODE == 'COMMIT_CHANGES') {
                        def approvalMessage = """
                            =========================================
                            MIGRATION DEPLOYMENT REVIEW
                            =========================================
                            Hospital: ${params.HOSPITAL}
                            Database: ${params.TARGET_DATABASE}
                            Script:   ${env.MIGRATION_SCRIPT}
                            Mode:     ${params.EXECUTION_MODE}
                            =========================================
                            Proceed with execution?
                        """
                        input message: approvalMessage, ok: 'Execute Migration'
                    }
                }
            }
        }

        stage('Database Execution') {
            agent { label "${AGENT_LABEL}" }
            steps {
                withCredentials([usernamePassword(credentialsId: "${SQL_CREDENTIAL_ID}", passwordVariable: 'DB_PASS', usernameVariable: 'DB_USER')]) {
                    powershell '''
                        $ErrorActionPreference = 'Stop'
                        $conn = $null
                        $tran = $null
                        
                        try {
                            $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
                            $builder["Data Source"] = $env:DB_SERVER_HOSTNAME
                            $builder["Initial Catalog"] = $env:TARGET_DATABASE
                            $builder["User ID"] = $env:DB_USER
                            $builder["Password"] = $env:DB_PASS
                            $builder["Connect Timeout"] = 15
                            $builder["TrustServerCertificate"] = $true
                            $builder["Application Name"] = "Jenkins_Pipeline"

                            $conn = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
                            $conn.Open()

                            $pingCmd = $conn.CreateCommand()
                            $pingCmd.CommandText = "SELECT 1;"
                            $null = $pingCmd.ExecuteScalar()
                            Write-Output "DB_CONNECTED_OK"

                            if ($env:EXECUTION_MODE -eq "HEALTH_CHECK_ONLY") {
                                Write-Output "MODE_HEALTH_CHECK_COMPLETE"
                                exit 0
                            }

                            $sqlContent = Get-Content -Path $env:MIGRATION_SCRIPT -Raw -Encoding UTF8
                            $batches = [regex]::Split($sqlContent, '(?im)^\\s*GO\\s*$')

                            $tran = $conn.BeginTransaction()
                            $batchNum = 0
                            
                            foreach ($batch in $batches) {
                                $trimmed = $batch.Trim()
                                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                                $batchNum++
                                
                                $cmd = $conn.CreateCommand()
                                $cmd.Transaction = $tran
                                $cmd.CommandTimeout = 60
                                $cmd.CommandText = $trimmed
                                $null = $cmd.ExecuteNonQuery()
                                Write-Output "Batch #$batchNum executed successfully."
                            }

                            if ($env:EXECUTION_MODE -eq "DRY_RUN_ROLLBACK") {
                                $tran.Rollback()
                                Write-Output "DRY_RUN_ROLLBACK_COMPLETE: Changes rolled back cleanly on $env:TARGET_DATABASE."
                            }
                            elseif ($env:EXECUTION_MODE -eq "COMMIT_CHANGES") {
                                $fileNameOnly = Split-Path $env:MIGRATION_SCRIPT -Leaf
                                $histCmd = $conn.CreateCommand()
                                $histCmd.Transaction = $tran
                                $histCmd.CommandText = @"
                                    IF OBJECT_ID('dbo.JenkinsMigrationHistory', 'U') IS NULL
                                    BEGIN
                                        CREATE TABLE dbo.JenkinsMigrationHistory (
                                            Id INT IDENTITY(1,1) PRIMARY KEY,
                                            MigrationFile NVARCHAR(255) NOT NULL,
                                            AppliedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
                                        );
                                    END
                                    INSERT INTO dbo.JenkinsMigrationHistory (MigrationFile) VALUES (@file);
"@
                                $null = $histCmd.Parameters.AddWithValue("@file", $fileNameOnly)
                                $null = $histCmd.ExecuteNonQuery()

                                $tran.Commit()
                                Write-Output "COMMIT_CHANGES_COMPLETE: Changes permanently committed on $env:TARGET_DATABASE."
                            }
                        }
                        catch {
                            if ($null -ne $tran) {
                                try { $tran.Rollback() } catch {}
                            }
                            Write-Error "SQL_EXECUTION_ERROR: $($_.Exception.Message)"
                            exit 1
                        }
                        finally {
                            if ($null -ne $conn -and $conn.State -ne [System.Data.ConnectionState]::Closed) {
                                $conn.Close()
                                $conn.Dispose()
                            }
                        }
                    '''
                }
            }
        }
    }

    post {
        always {
            node("${AGENT_LABEL}") {
                cleanWs(deleteDirs: true)
            }
        }
        success {
            echo "SUCCESS: Pipeline completed on ${params.HOSPITAL} / ${params.TARGET_DATABASE} in mode ${params.EXECUTION_MODE}."
        }
    }
}
