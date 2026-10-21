def environmentConfig = [
    TEST: [
        server: 'WIN-U6S7JB4ANMN',
        credentialId: 'sql-test-dbs-credentials',
        databases: ['H_U_ASSIRAAT', 'H_U_Kaleem', 'H_U_NHMC']
    ],
    UAT: [
        server: 'WIN-APTS20MHM62',
        credentialId: 'sql-uat-dbs-credentials',
        databases: ['pakred_uat']
    ],
    LIVE: [
        server: '',
        credentialId: 'sql-live-dbs-credentials',
        databases: []
    ]
]

def selectedDatabases = []
def selectedMigration = ''

pipeline {
    agent { label 'built-in' }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timestamps()
    }

    stages {
        stage('Checkout Repository') {
            steps { checkout scm }
        }

        stage('Validate Request') {
            steps {
                script {
                    def target = params.TARGET_ENV?.toString()
                    def useCustom = params.USE_CUSTOM_QUERY?.toString() == 'Yes'

                    if (!environmentConfig.containsKey(target)) {
                        error "Invalid environment: ${target}"
                    }

                    if (useCustom && !params.CUSTOM_SQL_TEXT?.trim()) {
                        error "You chose to use a Custom Query but left the text box empty. Please paste your SQL code."
                    }

                    def config = environmentConfig[target]

                    if (!config.server?.trim()) {
                        error "LIVE is disabled until its SQL Server is configured."
                    }

                    selectedDatabases = (params.DATABASES ?: '')
                        .toString()
                        .split(/[,;\r\n]+/)
                        .collect { it.trim() }
                        .findAll { it }

                    if (!selectedDatabases || selectedDatabases.contains('No_Databases_Configured')) {
                        error 'Select at least one valid database.'
                    }

                    def invalidDatabases = selectedDatabases.findAll { !(it in config.databases) }

                    if (invalidDatabases) {
                        error "Database selection is invalid for ${target}: ${invalidDatabases}"
                    }

                    echo "Environment: ${target}"
                    echo "Databases: ${selectedDatabases.join(', ')}"
                    echo "Using Custom Text Query: ${useCustom}"
                }
            }
        }

        stage('Select Migration') {
            when {
                // Skip if they selected Yes for a custom UI query
                expression { !(params.USE_CUSTOM_QUERY?.toString() == 'Yes') }
            }
            steps {
                script {
                    def fileOutput = powershell(
                        returnStdout: true,
                        script: '''
$now = (Get-Date).Date
$files = Get-ChildItem -Path .\\migrations -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\\\/]\\.git[\\\\/]' } |
    Sort-Object -Property LastWriteTime -Descending

$outputList = @()
foreach ($f in $files) {
    $relPath = $f.FullName.Substring((Get-Location).Path.Length + 1)
    $fileDate = $f.LastWriteTime.Date
    $days = ($now - $fileDate).Days
    
    if ($days -lt 0) { $timeStr = "Future date" }
    elseif ($days -eq 0) { $timeStr = "Modified today" }
    elseif ($days -eq 1) { $timeStr = "Modified 1 day ago" }
    else { $timeStr = "Modified $days days ago" }
    
    $outputList += "$relPath | $timeStr"
}
$outputList
'''
                    ).trim()

                    def migrationFiles = fileOutput ? fileOutput.readLines().findAll { it.trim() } : []

                    if (!migrationFiles) {
                        error 'No valid migration files were found in the migrations folder.'
                    }

                    def rawSelection = input(
                        message: 'Select the SQL migration to execute',
                        ok: 'Select Migration',
                        parameters: [
                            choice(
                                name: 'MIGRATION_FILE',
                                choices: migrationFiles.join('\n'),
                                description: 'Files are sorted newest first based on modified date.'
                            )
                        ]
                    ).toString()

                    selectedMigration = rawSelection.tokenize('|')[0].trim()

                    if (!(selectedMigration ==~ /(?s)(?!.*(?:^|[\\\/])\.\.?(?:[\\\/]|$)).*\.sql/)) {
                        error 'Invalid migration file path. Must be a .sql file.'
                    }

                    def sqlText = readFile(selectedMigration)

                    if (sqlText ==~ /(?s).*(?im)^\s*USE\s+.*$/) {
                        error 'USE statements are not allowed in the script. The pipeline automatically routes to the selected databases.'
                    }

                    if (sqlText ==~ /(?s).*(?im)^\s*(DROP\s+DATABASE|TRUNCATE\s+TABLE|DELETE\s+FROM|ALTER\s+TABLE\s+.*DROP\s+COLUMN)\b.*$/) {
                        error 'Safety check blocked a potentially destructive SQL statement. Review the migration manually.'
                    }
                }
            }
        }

        stage('Approve Execution') {
            steps {
                script {
                    def target = params.TARGET_ENV.toString()
                    def useCustom = params.USE_CUSTOM_QUERY?.toString() == 'Yes'
                    
                    def fileNamePreview = "V[Timestamp]__UI_CustomQuery.sql"
                    if (useCustom && params.CUSTOM_FILE_NAME?.trim()) {
                        def cleanName = params.CUSTOM_FILE_NAME.trim().replaceAll(/\.sql$/, '').replaceAll(/[^a-zA-Z0-9_]/, '_')
                        fileNamePreview = "V[Timestamp]__${cleanName}.sql"
                    }
                    
                    def migrationLabel = useCustom ? "Direct UI Text Box Query (Saving as: ${fileNamePreview})" : selectedMigration

                    def summary = """
Environment: ${target}
Databases: ${selectedDatabases.join(', ')}
Migration Source: ${migrationLabel}
Action: PERMANENT COMMIT

Continue?
"""
                    input(message: summary, ok: 'Confirm Execution')
                }
            }
        }

        stage('Execute SQL') {
            steps {
                script {
                    def target = params.TARGET_ENV.toString()
                    def useCustom = params.USE_CUSTOM_QUERY?.toString() == 'Yes'
                    def config = environmentConfig[target]
                    def hasErrors = false 

                    for (String db in selectedDatabases) {
                        try {
                            withCredentials([
                                usernamePassword(credentialsId: config.credentialId, usernameVariable: 'SQL_USER', passwordVariable: 'SQL_PASSWORD')
                            ]) {
                                withEnv([
                                    "SQL_SERVER=${config.server}",
                                    "SQL_DATABASE=${db}",
                                    "SQL_MIGRATION_FILE=${selectedMigration}",
                                    "USE_CUSTOM_QUERY=${useCustom}",
                                    "SQL_CUSTOM_TEXT=${params.CUSTOM_SQL_TEXT ?: ''}"
                                ]) {
                                    powershell '''
$ErrorActionPreference = 'Stop'
$connectionString = "Server=$env:SQL_SERVER;Initial Catalog=$env:SQL_DATABASE;User ID=$env:SQL_USER;Password=$env:SQL_PASSWORD;Encrypt=True;TrustServerCertificate=True;Connect Timeout=15"
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)

$handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] {
    param($sender, $eventArgs)
    Write-Output "[$env:SQL_DATABASE] SQL MESSAGE: $($eventArgs.Message)"
}
$connection.add_InfoMessage($handler)

try {
    $connection.Open()
    Write-Output "--------------------------------------------------------"
    Write-Output "EXECUTING ON DATABASE: $env:SQL_DATABASE"
    Write-Output "--------------------------------------------------------"

    if ($env:USE_CUSTOM_QUERY -eq 'true') {
        $sql = $env:SQL_CUSTOM_TEXT
    } else {
        $sql = Get-Content -LiteralPath $env:SQL_MIGRATION_FILE -Raw
    }

    $batches = [regex]::Split($sql, '(?im)^\\s*GO\\s*(?:--.*)?$')
    $transaction = $connection.BeginTransaction()

    try {
        foreach ($batch in $batches) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }

            $command = $connection.CreateCommand()
            $command.Transaction = $transaction
            $command.CommandTimeout = 120
            $command.CommandText = $batch

            try {
                $rowsAffected = $command.ExecuteNonQuery()
                if ($rowsAffected -ge 0) {
                    Write-Output "[$env:SQL_DATABASE] ($rowsAffected row(s) affected)"
                } else {
                    Write-Output "[$env:SQL_DATABASE] Command completed successfully."
                }
            }
            finally { $command.Dispose() }
        }
        
        $transaction.Commit()
        Write-Output "[$env:SQL_DATABASE] >> Migration committed successfully."
    }
    catch {
        Write-Output " "
        Write-Output "[$env:SQL_DATABASE] !!! SQL ERROR !!!"
        Write-Output "[$env:SQL_DATABASE] Error Details: $($_.Exception.Message)"
        Write-Output " "
        try { 
            $transaction.Rollback()
            Write-Output "[$env:SQL_DATABASE] >> Transaction successfully rolled back to protect the database." 
        } catch { 
            Write-Warning "[$env:SQL_DATABASE] Rollback failed. Check the database state immediately." 
        }
        throw "Execution failure on $env:SQL_DATABASE"
    }
    finally { $transaction.Dispose() }
}
finally {
    $connection.remove_InfoMessage($handler)
    $connection.Dispose()
}
'''
                                }
                            }
                        } catch (Exception e) {
                            echo "--------------------------------------------------------"
                            echo "❌ ERROR ON ${db}. CONTINUING TO NEXT DATABASE..."
                            echo "--------------------------------------------------------"
                            hasErrors = true
                        }
                    }

                    if (hasErrors) {
                        error "Pipeline halted: One or more databases failed during execution. Review the logs above."
                    }
                }
            }
        }

        stage('Auto-Commit to GitHub') {
            when {
                // Only trigger if they ran a custom text box query
                expression { params.USE_CUSTOM_QUERY?.toString() == 'Yes' }
            }
            steps {
                script {
                    def target = params.TARGET_ENV.toString()
                    def config = environmentConfig[target]
                    
                    withCredentials([
                        usernamePassword(credentialsId: config.credentialId, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')
                    ]) {
                        withEnv([
                            "CUSTOM_FILE_NAME=${params.CUSTOM_FILE_NAME ?: ''}",
                            "SQL_CUSTOM_TEXT=${params.CUSTOM_SQL_TEXT ?: ''}"
                        ]) {
                            powershell '''
$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Read the custom name from UI, default to UI_CustomQuery if blank
$baseName = $env:CUSTOM_FILE_NAME
if ([string]::IsNullOrWhiteSpace($baseName)) {
    $baseName = "UI_CustomQuery"
} else {
    # Remove .sql if the user typed it, and replace spaces with underscores to keep it clean
    $baseName = $baseName -replace '\\.sql$', ''
    $baseName = $baseName -replace '[^a-zA-Z0-9_]', '_'
}

$fileName = "V${timestamp}__${baseName}.sql"
$filePath = ".\\migrations\\$fileName"

if (!(Test-Path '.\\migrations')) { New-Item -ItemType Directory -Path '.\\migrations' }

$env:SQL_CUSTOM_TEXT | Out-File -FilePath $filePath -Encoding UTF8
Write-Output "Created migration file: $fileName"

git config user.name "Jenkins Automation"
git config user.email "jenkins@automation.local"

$remoteUrl = git remote get-url origin
if ($remoteUrl -match 'https://github.com/(.*)') {
    $repoPath = $Matches[1]
    git remote set-url origin "https://$env:GIT_USER:$env:GIT_PASS@github.com/$repoPath"
}

git add $filePath
git commit -m "Auto-commit custom query from Jenkins UI: $fileName"
git push origin main
Write-Output "Successfully pushed new migration file to GitHub!"
'''
                        }
                    }
                }
            }
        }
    }

    post {
        success { echo 'Pipeline completed successfully.' }
        failure { echo 'Pipeline failed. Review the console output and database state.' }
        always { echo 'Hospital database migration pipeline finished.' }
    }
}
