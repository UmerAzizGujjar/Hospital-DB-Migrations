// Global variables accessible across stages
def discoveredFilesList = []
def selectedHospitals = []

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(name: 'CHK_PAKRED_UAT', defaultValue: true, description: 'Deploy to Pakred UAT (WIN-APTS20MHM62)')
        booleanParam(name: 'CHK_ASIRAAT', defaultValue: false, description: 'Deploy to ASIRAAT (WIN-U6S7JB4ANMN)')
        booleanParam(name: 'CHK_CPTH', defaultValue: false, description: 'Deploy to CPTH')
        booleanParam(name: 'CHK_NATIONAL', defaultValue: false, description: 'Deploy to National')
        
        choice(
            name: 'EXECUTION_MODE',
            choices: ['DRY_RUN_ROLLBACK', 'COMMIT_CHANGES', 'HEALTH_CHECK_ONLY'],
            description: 'DRY_RUN_ROLLBACK: Runs migration inside a transaction and rolls back.\nCOMMIT_CHANGES: Permanently applies migration.\nHEALTH_CHECK_ONLY: Connectivity check (SELECT 1).'
        )
    }

    environment {
        MIGRATION_DIR = 'migrations'
        REGEX_PATTERN = '^(V\\d{8}_\\d{3})__[a-zA-Z0-9_]+\\.sql$'
    }

    stages {
        stage('StagePreflight & Config Lookup') {
            steps {
                echo "Preflight checks starting..."
                script {
                    if (!isUnix()) {
                        bat 'echo Jenkins Agent OS: Windows'
                    } else {
                        error "This pipeline requires a Windows agent."
                    }

                    selectedHospitals.clear()
                    if (params.CHK_PAKRED_UAT) selectedHospitals << 'Pakred_UAT'
                    if (params.CHK_ASIRAAT)    selectedHospitals << 'ASIRAAT'
                    if (params.CHK_CPTH)       selectedHospitals << 'CPTH'
                    if (params.CHK_NATIONAL)   selectedHospitals << 'National'

                    if (selectedHospitals.isEmpty()) {
                        error "No hospitals selected! Please check at least one hospital box to proceed."
                    }

                    echo "=========================================="
                    echo "Selected Target Hospitals : ${selectedHospitals.join(', ')}"
                    echo "Execution Mode            : ${params.EXECUTION_MODE}"
                    echo "=========================================="
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
                    def psDiscoverAndGit = '''
                        $ErrorActionPreference = 'Stop'
                        $path = $env:MIGRATION_DIR
                        if (-not (Test-Path -Path $path)) { Write-Output "ERROR_MISSING"; exit 0 }
                        $files = Get-ChildItem -Path $path -Filter "*.sql" -File
                        if ($null -eq $files -or $files.Count -eq 0) { Write-Output "ERROR_EMPTY"; exit 0 }
                        
                        foreach ($f in $files) {
                            $relPath = "$path/$($f.Name)"
                            $ct = ""; $cr = ""
                            try {
                                $ct = (git log -1 --format="%ct" -- $relPath 2>$null) | Select-Object -Last 1
                                $cr = (git log -1 --format="%cr" -- $relPath 2>$null) | Select-Object -Last 1
                            } catch { $ct = "0"; $cr = "Unknown age" }
                            if ([string]::IsNullOrWhiteSpace($ct)) { $ct = "0" }
                            if ([string]::IsNullOrWhiteSpace($cr)) { $cr = "Unknown age" }
                            Write-Output "$($f.Name)|$($ct.Trim())|$($cr.Trim())"
                        }
                    '''
                    def dirOutput = powershell(script: psDiscoverAndGit, returnStdout: true).trim()

                    if (dirOutput.contains("ERROR_MISSING") || dirOutput.contains("ERROR_EMPTY") || !dirOutput) {
                        error "Validation Failed: No SQL migration files found in ${env.MIGRATION_DIR} directory."
                    }
                    
                    def lines = dirOutput.split('\r?\n').collect { it.trim() }.findAll { it && it.contains('|') }
                    def fileObjects = []
                    for (line in lines) {
                        def parts = line.tokenize('|')
                        def fName = parts[0]
                        long cTime = parts.size() > 1 && parts[1].isNumber() ? parts[1].toLong() : 0L
                        def relAge = parts.size() > 2 ? parts[2] : "Unknown age"
                        fileObjects << [name: fName, timestamp: cTime, ageDisplay: relAge, choiceLabel: "${fName} (${relAge})"]
                    }
                    
                    fileObjects.sort { a, b -> b.timestamp <=> a.timestamp }
                    discoveredFilesList = fileObjects.collect { it.name }
                    
                    def duplicateError = checkDuplicateVersions(discoveredFilesList)
                    if (duplicateError) {
                        error "Pre-Validation Failed: Ambiguous deployment state. ${duplicateError}"
                    }

                    List<String> choicesList = fileObjects.collect { it.choiceLabel.toString() }

                    env.SELECTED_CHOICE = input(
                        message: "Apply migration to: [${selectedHospitals.join(', ')}]",
                        parameters: [
                            choice(name: 'MIGRATION_FILE', choices: choicesList, description: 'Select the file to deploy')
                        ]
                    )
                    
                    def selectedFileObj = fileObjects.find { it.choiceLabel == env.SELECTED_CHOICE }
                    env.SELECTED_FILENAME = selectedFileObj ? selectedFileObj.name : "UNKNOWN"
                    env.COMMIT_AGE = selectedFileObj ? selectedFileObj.ageDisplay : "Unknown"
                    env.SELECTED_PATH = "${env.MIGRATION_DIR}\\${env.SELECTED_FILENAME}"
                }
            }
        }

        stage('StageValidate Migration') {
            steps {
                script {
                    def filename = env.SELECTED_FILENAME
                    def selectionError = validateMigrationFilename(filename, discoveredFilesList, env.REGEX_PATTERN)
                    if (selectionError) error "Validation Failed: ${selectionError}"

                    def expectedPath = env.SELECTED_PATH
                    if (!fileExists(expectedPath)) error "Validation Failed: File ${expectedPath} not found."

                    def rawSql = readFile(file: expectedPath, encoding: 'UTF-8')
                    def scanResult = scanSqlSafety(rawSql)
                    
                    if (scanResult.error) {
                        error "SECURITY VIOLATION: Migration failed safety policy -> ${scanResult.error}"
                    }
                    echo "Validation & Safety Scan Passed. File is safe for execution."
                }
            }
        }

        stage('StageDatabase Execution / Test') {
            steps {
                script {
                    if (params.EXECUTION_MODE == 'COMMIT_CHANGES') {
                        input(
                            message: "CONFIRMATION: Permanently apply ${env.SELECTED_FILENAME} to: [${selectedHospitals.join(', ')}]?",
                            ok: "Yes, Commit Migration"
                        )
                    }

                    def hospitalConfigs = [
                        'Pakred_UAT': [ 
                            server: 'WIN-APTS20MHM62', 
                            dbName: 'pakred_uat', 
                            credId: 'pakred-uat-creds' 
                        ],
                        'ASIRAAT': [ 
                            server: 'WIN-U6S7JB4ANMN', 
                            dbName: 'STH_U_ASIRAAT', 
                            credId: 'hospital-demo-sql-creds' 
                        ],
                        'CPTH': [ 
                            server: '192.168.1.100', 
                            dbName: 'CPTH_DB', 
                            credId: 'cpth-sql-creds' 
                        ],
                        'National': [ 
                            server: '192.168.1.105', 
                            dbName: 'National_DB', 
                            credId: 'national-sql-creds' 
                        ]
                    ]

                    env.EXEC_MODE = params.EXECUTION_MODE
                    def failedHospitals = []

                    for (hosp in selectedHospitals) {
                        def config = hospitalConfigs[hosp]
                        if (!config) {
                            echo "❌ Missing config map entry for ${hosp}"
                            failedHospitals << hosp
                            continue
                        }

                        echo "====================================================="
                        echo "Processing [${hosp}] -> Server: ${config.server}, DB: ${config.dbName}"
                        echo "====================================================="

                        env.TARGET_DB_SERVER = config.server
                        env.TARGET_DB_NAME   = config.dbName

                        try {
                            withCredentials([usernamePassword(
                                credentialsId: config.credId,
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
                                        $builder["Application Name"] = "Jenkins_Pipeline"

                                        $conn = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
                                        $conn.Open()

                                        $pingCmd = $conn.CreateCommand()
                                        $pingCmd.CommandText = "SELECT 1;"
                                        $null = $pingCmd.ExecuteScalar()
                                        Write-Output "DB_CONNECTED_OK"

                                        if ($env:EXEC_MODE -eq "HEALTH_CHECK_ONLY") {
                                            Write-Output "MODE_HEALTH_CHECK_COMPLETE"
                                            exit 0
                                        }

                                        $sqlContent = Get-Content -Path $env:SELECTED_PATH -Raw -Encoding UTF8
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

                                        if ($env:EXEC_MODE -eq "DRY_RUN_ROLLBACK") {
                                            $tran.Rollback()
                                            Write-Output "DRY_RUN_ROLLBACK_COMPLETE: Changes rolled back cleanly on $env:TARGET_DB_NAME."
                                        }
                                        elseif ($env:EXEC_MODE -eq "COMMIT_CHANGES") {
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
                                            Write-Output "COMMIT_CHANGES_COMPLETE: Changes permanently committed on $env:TARGET_DB_NAME."
                                        }
                                    }
                                    catch {
                                        if ($null -ne $tran) {
                                            try { $tran.Rollback() } catch {}
                                        }
                                        Write-Output "SQL_EXECUTION_ERROR: $($_.Exception.Message)"
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
                                    echo "❌ FAILED on ${hosp}"
                                    failedHospitals << hosp
                                } else {
                                    echo "✅ PASSED on ${hosp}"
                                }
                            }
                        } catch (Exception e) {
                            echo "❌ ERROR on ${hosp}: ${e.message}"
                            failedHospitals << hosp
                        }
                    }

                    if (!failedHospitals.isEmpty()) {
                        error "Pipeline failed on the following target(s): ${failedHospitals.join(', ')}."
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
                    echo "Executed File       : ${env.SELECTED_FILENAME}"
                    echo "Commit Age          : ${env.COMMIT_AGE}"
                    echo "Target Hospitals    : ${selectedHospitals.join(', ')}"
                    echo "Execution Mode      : ${params.EXECUTION_MODE}"
                    echo "Result              : ALL TARGETS PASSED"
                    echo "====================================================="
                }
            }
        }
    }
}

// ============================================================================
// --- SHARED HELPER FUNCTIONS ---
// ============================================================================

@NonCPS
def validateMigrationFilename(String filename, List<String> validList, String patternStr) {
    if (!filename || filename.trim() == "") return "Empty selection."
    if (!validList.contains(filename)) return "Selected file '${filename}' is not in the discovered list."
    if (!(filename ==~ patternStr)) return "Filename '${filename}' does not match pattern (VYYYYMMDD_NNN__description.sql)."
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
def scanSqlSafety(String rawSql) {
    if (!rawSql || rawSql.trim() == "") return [error: "File is empty or whitespace-only.", warnings: []]
    if (rawSql.contains("\u0000")) return [error: "Null bytes detected. File may be binary.", warnings: []]

    def errors = []
    def warnings = []
    
    // Strip comments and strings to prevent false positives
    def cleanSql = rawSql.replaceAll(/(?s)('(?:[^']|'')*')|(\/\*.*?\*\/)|(--[^\r\n]*)/) { match ->
        def text = match instanceof List ? match[0] : match.toString()
        if (text.startsWith("'")) return "''"
        return " "
    }

    def statements = cleanSql.split(/(?im)^\s*GO\s*$|;/)

    for (stmt in statements) {
        def s = stmt.trim()
        if (!s) continue
        
        // Block destructive commands
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
    
    if (!errors.isEmpty()) {
        return [error: errors.join(" | "), warnings: []]
    }
    return [error: null, warnings: warnings]
}
