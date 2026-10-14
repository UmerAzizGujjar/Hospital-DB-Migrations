// Global variables accessible across stages
def discoveredFilesList = []

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    parameters {
        string(
            name: 'DB_SERVER',
            defaultValue: 'WIN-U6S7JB4ANMN',
            description: 'Demo/Test SQL Server host/instance (e.g., WIN-U6S7JB4ANMN or localhost,1433). Production hosts are strictly blocked.'
        )
        string(
            name: 'DB_NAME',
            defaultValue: 'STH_U_ASIRAAT',
            description: 'Target Demo/Test Database Name (Must NOT be a production database).'
        )
        string(
            name: 'DB_CREDENTIALS_ID',
            defaultValue: 'hospital-demo-sql-creds',
            description: 'Jenkins Credentials ID (Username with password) for Test DB.'
        )
        choice(
            name: 'EXECUTION_MODE',
            choices: ['DRY_RUN_ROLLBACK', 'COMMIT_CHANGES', 'HEALTH_CHECK_ONLY'],
            description: 'DRY_RUN_ROLLBACK: Runs the SQL migration inside a transaction to test ADD COLUMN/DDL, then rolls back.\nCOMMIT_CHANGES: Permanently applies the migration to the Test DB.\nHEALTH_CHECK_ONLY: Only runs SELECT 1.'
        )
    }

    environment {
        MIGRATION_DIR = 'migrations'
        REGEX_PATTERN = '^(V\\d{8}_\\d{3})__[a-zA-Z0-9_]+\\.sql$'
    }

    stages {
        stage('StagePreflight') {
            steps {
                echo "Preflight checks starting..."
                script {
                    if (!isUnix()) {
                        bat 'echo Jenkins Agent OS: Windows'
                        bat 'git --version'
                    } else {
                        error "This pipeline requires a Windows agent."
                    }

                    def dbTargetError = validateDbTarget(
                        params.DB_SERVER,
                        params.DB_NAME,
                        params.DB_CREDENTIALS_ID
                    )
                    if (dbTargetError) {
                        error "Preflight DB Target Validation Failed: ${dbTargetError}"
                    }
                    echo "Preflight DB Target Check: Verified non-production target [${params.DB_SERVER} / ${params.DB_NAME}]."
                    echo "Selected Execution Mode: ${params.EXECUTION_MODE}"
                }
            }
        }

        stage('StageCheckout') {
            steps {
                checkout scm
            }
        }

        stage('StageSelect Migration') {
            steps {
                script {
                    // 1. Discover using robust PowerShell logic.
                    // - Distinguishes missing path, non-directory, empty directory, and genuine enumeration failures.
                    // - $ErrorActionPreference = 'Stop' ensures unexpected IO/permission errors fail the step naturally.
                    def psScript = '''
                        $ErrorActionPreference = 'Stop'
                        $path = $env:MIGRATION_DIR
                        
                        if (-not (Test-Path -Path $path)) {
                            Write-Output "ERROR_MISSING"
                            exit 0
                        }
                        
                        $item = Get-Item -Path $path
                        if (-not $item.PSIsContainer) {
                            Write-Output "ERROR_NOT_DIR"
                            exit 0
                        }
                        
                        $files = Get-ChildItem -Path $path -Filter "*.sql" -File
                        if ($null -eq $files -or $files.Count -eq 0) {
                            Write-Output "ERROR_EMPTY"
                            exit 0
                        }
                        
                        $files.Name
                    '''
                    
                    def dirOutput = powershell(script: psScript, returnStdout: true).trim()

                    if (dirOutput.contains("ERROR_MISSING")) {
                        error "Validation Failed: The path ${env.MIGRATION_DIR}\\ does not exist."
                    }
                    if (dirOutput.contains("ERROR_NOT_DIR")) {
                        error "Validation Failed: The path ${env.MIGRATION_DIR}\\ exists but is not a directory."
                    }
                    if (dirOutput.contains("ERROR_EMPTY")) {
                        error "No SQL migration files found in ${env.MIGRATION_DIR}\\ directory."
                    }
                    
                    def rawFiles = dirOutput.split('\r?\n').collect { it.trim() }.findAll { it && !it.startsWith("ERROR_") }
                    
                    def fileObjects = []
                    for (f in rawFiles) {
                        def cTimeStr = bat(script: "@echo off && git log -1 --format=%%ct -- \"${env.MIGRATION_DIR}\\${f}\"", returnStdout: true).trim()
                        def relAge = bat(script: "@echo off && git log -1 --format=%%cr -- \"${env.MIGRATION_DIR}\\${f}\"", returnStdout: true).trim()
                        
                        long cTime = 0
                        if (cTimeStr && cTimeStr.isNumber()) {
                            cTime = cTimeStr.toLong()
                        } else {
                            relAge = "Unknown age (Git lookup failed)"
                        }
                        
                        def choiceStr = "${f} (${relAge})"
                        fileObjects << [name: f, timestamp: cTime, ageDisplay: relAge, choiceLabel: choiceStr]
                    }
                    
                    // 2. Sort by Git timestamp (newest first)
                    fileObjects.sort { a, b -> b.timestamp <=> a.timestamp }
                    discoveredFilesList = fileObjects.collect { it.name }
                    
                    // 3. Prevent ambiguous states BEFORE prompting user
                    echo "--- Checking for Duplicate Migrations ---"
                    def duplicateError = checkDuplicateVersions(discoveredFilesList)
                    if (duplicateError) {
                        error "Pre-Validation Failed: Ambiguous deployment state. ${duplicateError}"
                    }
                    
                    def choices = fileObjects.collect { it.choiceLabel }

                    // 4. Interactive prompt
                    env.SELECTED_CHOICE = input(
                        message: "Select a migration (${params.EXECUTION_MODE}):",
                        parameters: [
                            choice(name: 'MIGRATION_FILE', choices: choices.join('\n'), description: 'Select the file and view its commit age')
                        ]
                    )
                    
                    // 5. Safely extract filename using exact label match
                    def selectedFileObj = fileObjects.find { it.choiceLabel == env.SELECTED_CHOICE }
                    if (selectedFileObj) {
                        env.SELECTED_FILENAME = selectedFileObj.name
                        env.COMMIT_AGE = selectedFileObj.ageDisplay
                    } else {
                        env.SELECTED_FILENAME = "UNKNOWN_SELECTION"
                        env.COMMIT_AGE = "UNKNOWN"
                    }
                    env.SELECTED_PATH = "${env.MIGRATION_DIR}\\${env.SELECTED_FILENAME}"
                }
            }
        }

        stage('StageValidate Migration') {
            steps {
                script {
                    def filename = env.SELECTED_FILENAME
                    
                    echo "--- A. Validating Migration Selection ---"
                    def selectionError = validateMigrationFilename(filename, discoveredFilesList, env.REGEX_PATTERN)
                    if (selectionError) error "Validation Failed: ${selectionError}"
                    
                    def expectedPath = "${env.MIGRATION_DIR}\\${filename}"
                    if (!fileExists(expectedPath)) error "Validation Failed: The file ${expectedPath} does not exist in the workspace."

                    echo "--- B. Validating File Contents ---"
                    def rawSql = readFile(file: expectedPath, encoding: 'UTF-8')
                    
                    env.FILE_SIZE_BYTES = rawSql.getBytes("UTF-8").length.toString()
                    env.FILE_LINE_COUNT = rawSql.readLines().size().toString()

                    echo "--- C. Non-Blocking SQL Safety Scan ---"
                    def scanResult = scanSqlSafety(rawSql)
                    
                    if (scanResult.error) error "Validation Failed: ${scanResult.error}"
                    
                    if (scanResult.warnings.isEmpty()) {
                        env.SAFETY_WARNINGS = "None"
                    } else {
                        env.SAFETY_WARNINGS = scanResult.warnings.join(" | ")
                        echo "MANUAL REVIEW REQUIRED: Suspicious patterns flagged by static scan."
                    }
                }
            }
        }

        stage('StageDatabase Execution / Test') {
            steps {
                script {
                    if (params.EXECUTION_MODE == 'COMMIT_CHANGES') {
                        input(
                            message: "CONFIRMATION: Permanently apply ${env.SELECTED_FILENAME} to Test DB [${params.DB_NAME}]?",
                            ok: "Yes, Commit Migration"
                        )
                    }

                    env.TARGET_DB_SERVER = params.DB_SERVER.trim()
                    env.TARGET_DB_NAME   = params.DB_NAME.trim()
                    env.EXEC_MODE        = params.EXECUTION_MODE

                    withCredentials([usernamePassword(
                        credentialsId: params.DB_CREDENTIALS_ID.trim(),
                        usernameVariable: 'DB_USER',
                        passwordVariable: 'DB_PASS'
                    )]) {
                        def sqlRunnerPs = '''
                            $ErrorActionPreference = 'Stop'
                            $conn = $null
                            $tran = $null
                            try {
                                $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
                                $builder["Data Source"] = $env:TARGET_DB_SERVER
                                $builder["Initial Catalog"] = $env:TARGET_DB_NAME
                                $builder["User ID"] = $env:DB_USER
                                $builder["Password"] = $env:DB_PASS
                                $builder["Connect Timeout"] = 15
                                $builder["TrustServerCertificate"] = $true

                                $conn = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
                                $conn.Open()

                                # 1. Verify connectivity first
                                $pingCmd = $conn.CreateCommand()
                                $pingCmd.CommandText = "SELECT 1;"
                                $null = $pingCmd.ExecuteScalar()
                                Write-Output "DB_CONNECTED_OK"

                                if ($env:EXEC_MODE -eq "HEALTH_CHECK_ONLY") {
                                    Write-Output "MODE_HEALTH_CHECK_COMPLETE"
                                    exit 0
                                }

                                # 2. Read migration file and split by standalone GO lines
                                $sqlContent = Get-Content -Path $env:SELECTED_PATH -Raw -Encoding UTF8
                                $batches = [regex]::Split($sqlContent, '(?im)^\\s*GO\\s*$')

                                # 3. Begin Transaction (Used for both DRY_RUN_ROLLBACK and COMMIT_CHANGES)
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
                                    $rows = $cmd.ExecuteNonQuery()
                                    Write-Output "Executed Batch #$batchNum successfully."
                                }

                                if ($env:EXEC_MODE -eq "DRY_RUN_ROLLBACK") {
                                    $tran.Rollback()
                                    Write-Output "DRY_RUN_ROLLBACK_COMPLETE: All batches compiled and executed against real schema, then safely rolled back."
                                }
                                elseif ($env:EXEC_MODE -eq "COMMIT_CHANGES") {
                                    # Record migration in history table inside the same transaction
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
                                    $null = $histCmd.Parameters.AddWithValue("@file", $env:SELECTED_FILENAME)
                                    $null = $histCmd.ExecuteNonQuery()

                                    $tran.Commit()
                                    Write-Output "COMMIT_CHANGES_COMPLETE: Migration permanently committed and logged in dbo.JenkinsMigrationHistory."
                                }
                            }
                            catch {
                                if ($null -ne $tran) {
                                    try { $tran.Rollback() } catch {}
                                }
                                if ($_.Exception.InnerException -is [System.Data.SqlClient.SqlException]) {
                                    $sqlEx = [System.Data.SqlClient.SqlException]$_.Exception.InnerException
                                    Write-Output "SQL_EXECUTION_ERROR: Line $($sqlEx.LineNumber) - $($sqlEx.Message)"
                                } elseif ($_.Exception -is [System.Data.SqlClient.SqlException]) {
                                    $sqlEx = [System.Data.SqlClient.SqlException]$_.Exception
                                    Write-Output "SQL_EXECUTION_ERROR: Line $($sqlEx.LineNumber) - $($sqlEx.Message)"
                                } else {
                                    Write-Output "GENERAL_DB_ERROR: $($_.Exception.Message)"
                                }
                                exit 1
                            }
                            finally {
                                if ($null -ne $conn -and $conn.State -ne [System.Data.ConnectionState]::Closed) {
                                    $conn.Close()
                                    $conn.Dispose()
                                }
                            }
                        '''

                        def status = powershell(script: sqlRunnerPs, returnStatus: true)
                        if (status != 0) {
                            env.DB_EXEC_STATUS = "FAILED"
                            error "Database execution failed in mode [${params.EXECUTION_MODE}]. Any open transaction was automatically rolled back. Check console logs above for the exact SQL line number and error."
                        }
                        env.DB_EXEC_STATUS = "PASSED (${params.EXECUTION_MODE})"
                    }
                }
            }
        }

        stage('StageMigration Report') {
            steps {
                script {
                    echo "====================================================="
                    echo "              MIGRATION EXECUTION REPORT             "
                    echo "====================================================="
                    echo "Selected Path       : ${env.SELECTED_PATH}"
                    echo "Commit Age          : ${env.COMMIT_AGE}"
                    echo "File Size           : ${env.FILE_SIZE_BYTES} bytes"
                    echo "Line Count          : ${env.FILE_LINE_COUNT} lines"
                    echo "Duplicate Versions  : None (Verified pre-selection)"
                    echo "Validation Checks   : PASSED"
                    echo "Safety Warnings     : ${env.SAFETY_WARNINGS}"
                    echo "Target Test Server  : ${params.DB_SERVER}"
                    echo "Target Test DB      : ${params.DB_NAME}"
                    echo "Execution Mode      : ${params.EXECUTION_MODE}"
                    echo "Database Result     : ${env.DB_EXEC_STATUS}"
                    echo "-----------------------------------------------------"
                    echo "DISCLAIMER: Scan is heuristic and conservative. It is not an AST"
                    echo "SQL parser. It cannot guarantee safety for complex SQL, multi-line"
                    echo "constructs, stored procedures, or dynamic SQL. Finding a WHERE"
                    echo "clause does not definitively prove a DELETE statement is safe."
                    echo "====================================================="
                    
                    if (env.SAFETY_WARNINGS != "None") {
                        unstable("Completed with static safety warnings.")
                    }
                }
            }
        }
        
        stage('StagePost Actions') {
            steps {
                echo "Post actions complete. Diagnostics preserved in workspace."
            }
        }
    }
}

// ============================================================================
// --- SHARED FUNCTIONS ---
// (Do not remove this comment block. Used by offline tests for extraction)
// ============================================================================

@NonCPS
def validateMigrationFilename(String filename, List<String> validList, String patternStr) {
    if (!filename || filename.trim() == "") return "Empty selection."
    if (!validList.contains(filename)) return "Selected file '${filename}' is not in the strictly discovered list (Path traversal/manipulation attempt)."
    if (!(filename ==~ patternStr)) return "Filename '${filename}' does not match the required convention (VYYYYMMDD_NNN__description.sql)."
    return null
}

@NonCPS
def checkDuplicateVersions(List<String> files) {
    def versions = [:]
    for (f in files) {
        def matcher = (f =~ /^(V\d{8}_\d{3})__/)
        if (matcher) {
            def v = matcher[0][1]
            versions[v] = versions.containsKey(v) ? versions[v] + [f] : [f]
        }
    }
    def duplicates = versions.findAll { it.value.size() > 1 }
    if (duplicates) {
        def msgs = []
        duplicates.each { k, v -> msgs << "${k} (${v.join(', ')})" }
        return "Duplicate versions detected: " + msgs.join("; ")
    }
    return null
}

@NonCPS
def validateDbTarget(String server, String dbName, String credId) {
    if (!server || server.trim() == "") return "DB_SERVER cannot be empty."
    if (!dbName || dbName.trim() == "") return "DB_NAME cannot be empty."
    if (!credId || credId.trim() == "") return "DB_CREDENTIALS_ID cannot be empty."

    def s = server.trim()
    def d = dbName.trim()
    def c = credId.trim()

    if (!(s ==~ /^[a-zA-Z0-9._\-,\\]+$/)) return "DB_SERVER contains invalid or unsafe characters."
    if (!(d ==~ /^[a-zA-Z0-9_\-]+$/)) return "DB_NAME contains invalid or unsafe characters."
    if (!(c ==~ /^[a-zA-Z0-9_\-.]+$/)) return "DB_CREDENTIALS_ID contains invalid or unsafe characters."

    def forbiddenPattern = /(?i)(^|[\W_])(prod|production|prd|live|primary|clinical_live|his_main)($|[\W_])/
    if (s =~ forbiddenPattern || d =~ forbiddenPattern) {
        return "SAFETY VIOLATION: Target server or database matches restricted production naming patterns. Only Demo/Test environments are permitted."
    }

    return null
}

@NonCPS
def scanSqlSafety(String rawSql) {
    if (!rawSql || rawSql.trim() == "") return [error: "File is empty or whitespace-only.", warnings: []]
    if (rawSql.contains("\u0000")) return [error: "Null bytes detected. File may be binary or incorrectly encoded.", warnings: []]

    def warnings = []
    def cleanSql = rawSql.replaceAll(/(?s)('(?:[^']|'')*')|(\/\*.*?\*\/)|(--[^\r\n]*)/) { match ->
        def text = match instanceof List ? match[0] : match.toString()
        if (text.startsWith("'")) return "''"
        return " "
    }

    def statements = cleanSql.split(/(?im)^\s*GO\s*$|;/)

    for (stmt in statements) {
        def s = stmt.trim()
        if (!s) continue
        
        if (s =~ /(?i)\bDROP\s+(TABLE|DATABASE|PROCEDURE)\b/) warnings << "Destructive DDL (DROP TABLE/DATABASE/PROCEDURE) detected."
        if (s =~ /(?i)\bTRUNCATE\s+TABLE\b/) warnings << "TRUNCATE TABLE detected."
        if (s =~ /(?i)\bDELETE\b/ && !(s =~ /(?i)\bWHERE\b/)) warnings << "DELETE statement potentially missing a WHERE clause."
        if (s =~ /(?i)\bALTER\s+TABLE\s+.*?\bDROP\s+COLUMN\b/) warnings << "ALTER TABLE ... DROP COLUMN detected."
        if (s =~ /(?i)\b(EXEC|EXECUTE)\s*\(/ || s =~ /(?i)\bsp_executesql\b/) warnings << "Dynamic SQL execution detected."
        if (s =~ /(?i)\bGRANT\b|\bREVOKE\b|\bDENY\b/) warnings << "Permissions modification detected."
    }
    
    return [error: null, warnings: warnings.unique()]
}
