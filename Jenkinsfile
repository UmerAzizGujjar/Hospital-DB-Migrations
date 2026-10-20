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
    agent {
        label 'built-in'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timestamps()
    }

    parameters {
        choice(
            name: 'TARGET_ENV',
            choices: ['TEST', 'UAT', 'LIVE'],
            description: 'Select the target database environment'
        )
        choice(
            name: 'EXECUTION_MODE',
            choices: ['DRY_RUN_ROLLBACK', 'COMMIT_CHANGES', 'HEALTH_CHECK_ONLY'],
            description: 'Select how the SQL should be executed'
        )
        string(
            name: 'DATABASES',
            defaultValue: '',
            description: 'Comma-separated list of databases (e.g. H_U_ASSIRAAT, H_U_Kaleem)'
        )
    }

    stages {
        stage('Checkout Repository') {
            steps {
                checkout scm
            }
        }

        stage('Validate Request') {
            steps {
                script {
                    def target = params.TARGET_ENV?.toString()
                    def mode = params.EXECUTION_MODE?.toString()

                    if (!environmentConfig.containsKey(target)) {
                        error "Invalid environment: ${target}"
                    }

                    if (!(mode in [
                        'DRY_RUN_ROLLBACK',
                        'COMMIT_CHANGES',
                        'HEALTH_CHECK_ONLY'
                    ])) {
                        error "Invalid execution mode: ${mode}"
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

                    if (!selectedDatabases) {
                        error 'Select at least one database.'
                    }

                    def invalidDatabases = selectedDatabases.findAll {
                        !(it in config.databases)
                    }

                    if (invalidDatabases) {
                        error "Database selection is invalid for ${target}: ${invalidDatabases}"
                    }

                    echo "Environment: ${target}"
                    echo "SQL Server: ${config.server}"
                    echo "Databases: ${selectedDatabases.join(', ')}"
                    echo "Execution mode: ${mode}"
                }
            }
        }

        stage('Select Migration') {
            when {
                expression {
                    params.EXECUTION_MODE != 'HEALTH_CHECK_ONLY'
                }
            }

            steps {
                script {
                    def fileOutput = powershell(
                        returnStdout: true,
                        script: '''
$files = Get-ChildItem -Path .\\migration -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '^V\\d{8}_\\d{3}__[a-zA-Z0-9_]+\\.sql$' -and
        $_.FullName -notmatch '[\\\\/]\\.git[\\\\/]'
    } |
    ForEach-Object {
        $_.FullName.Substring((Get-Location).Path.Length + 1)
    }

$files | Sort-Object
'''
                    ).trim()

                    def migrationFiles = fileOutput
                        ? fileOutput.readLines().findAll { it.trim() }
                        : []

                    if (!migrationFiles) {
                        error 'No valid migration files were found in the migration folder.'
                    }

                    selectedMigration = input(
                        message: 'Select the SQL migration to execute',
                        ok: 'Select Migration',
                        parameters: [
                            choice(
                                name: 'MIGRATION_FILE',
                                choices: migrationFiles.join('\n'),
                                description: 'Choose one migration file from the migration folder.'
                            )
                        ]
                    ).toString()

                    if (!(selectedMigration ==~ /(?s)(?!.*(?:^|[\\\/])\.\.?(?:[\\\/]|$)).*V\d{8}_\d{3}__[a-zA-Z0-9_]+\.sql/)) {
                        error 'Invalid migration file path.'
                    }

                    def sqlText = readFile(selectedMigration)

                    if (sqlText ==~ /(?s).*(?im)^\s*USE\s+.*$/) {
                        error 'USE statements are not allowed in the script. The pipeline automatically routes to the selected databases.'
                    }

                    if (sqlText ==~ /(?s).*(?im)^\s*(DROP\s+DATABASE|TRUNCATE\s+TABLE|DELETE\s+FROM|ALTER\s+TABLE\s+.*DROP\s+COLUMN)\b.*$/) {
                        error 'Safety check blocked a potentially destructive SQL statement. Review the migration manually.'
                    }

                    echo "Selected migration: ${selectedMigration}"
                }
            }
        }

        stage('Approve Execution') {
            steps {
                script {
                    def target = params.TARGET_ENV.toString()
                    def mode = params.EXECUTION_MODE.toString()

                    def summary = """
Environment: ${target}
Databases: ${selectedDatabases.join(', ')}
Mode: ${mode}
Migration: ${mode == 'HEALTH_CHECK_ONLY' ? 'Not applicable' : selectedMigration}

Continue?
"""

                    input(
                        message: summary,
                        ok: 'Confirm Execution'
                    )
                }
            }
        }

        stage('Execute SQL') {
            steps {
                script {
                    def target = params.TARGET_ENV.toString()
                    def mode = params.EXECUTION_MODE.toString()
                    def config = environmentConfig[target]

                    for (String db in selectedDatabases) {
                        echo "Processing database: ${db}"

                        withCredentials([
                            usernamePassword(
                                credentialsId: config.credentialId,
                                usernameVariable: 'SQL_USER',
                                passwordVariable: 'SQL_PASSWORD'
                            )
                        ]) {
                            withEnv([
                                "SQL_SERVER=${config.server}",
                                "SQL_DATABASE=${db}",
                                "SQL_EXECUTION_MODE=${mode}",
                                "SQL_MIGRATION_FILE=${selectedMigration}"
                            ]) {
                                powershell '''
$ErrorActionPreference = 'Stop'

$connectionString = @(
    "Server=$env:SQL_SERVER"
    "Initial Catalog=$env:SQL_DATABASE"
    "User ID=$env:SQL_USER"
    "Password=$env:SQL_PASSWORD"
    "Encrypt=True"
    "TrustServerCertificate=True"
    "Connect Timeout=15"
) -join ';'

$connection = New-Object System.Data.SqlClient.SqlConnection(
    $connectionString
)

try {
    $connection.Open()
    Write-Output "Connected to $env:SQL_SERVER / $env:SQL_DATABASE"

    if ($env:SQL_EXECUTION_MODE -eq 'HEALTH_CHECK_ONLY') {
        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT 1'
        $result = $command.ExecuteScalar()
        $command.Dispose()

        if ($result -ne 1) {
            throw 'Health check failed.'
        }

        Write-Output 'Health check successful.'
    }
    else {
        $sql = Get-Content -LiteralPath $env:SQL_MIGRATION_FILE -Raw

        $batches = [regex]::Split(
            $sql,
            '(?im)^\\s*GO\\s*(?:--.*)?$'
        )

        $transaction = $connection.BeginTransaction()

        try {
            foreach ($batch in $batches) {
                if ([string]::IsNullOrWhiteSpace($batch)) {
                    continue
                }

                $command = $connection.CreateCommand()
                $command.Transaction = $transaction
                $command.CommandTimeout = 120
                $command.CommandText = $batch

                try {
                    [void]$command.ExecuteNonQuery()
                }
                finally {
                    $command.Dispose()
                }
            }

            if ($env:SQL_EXECUTION_MODE -eq 'DRY_RUN_ROLLBACK') {
                $transaction.Rollback()
                Write-Output 'Dry run completed; transaction rolled back.'
            }
            elseif ($env:SQL_EXECUTION_MODE -eq 'COMMIT_CHANGES') {
                $transaction.Commit()
                Write-Output 'Migration committed successfully.'
            }
            else {
                throw 'Unsupported execution mode.'
            }
        }
        catch {
            try {
                $transaction.Rollback()
            }
            catch {
                Write-Warning 'Rollback failed. Check the database state immediately.'
            }

            throw
        }
        finally {
            $transaction.Dispose()
        }
    }
}
finally {
    $connection.Dispose()
}
'''
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Review the console output and database state.'
        }
        always {
            echo 'Hospital database migration pipeline finished.'
        }
    }
}
