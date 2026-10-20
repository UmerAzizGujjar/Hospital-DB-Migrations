
import groovy.transform.Field

@Field List<String> discoveredFilesList = []
@Field List<String> selectedDatabases = []

// ============================================================
// ENVIRONMENT CONFIGURATION
// ============================================================

@Field Map<String, String> serverByEnvironment = [
    TEST: 'WIN-U6S7JB4ANMN',
    UAT : 'WIN-APTS20MHM62',
    LIVE: '' // Enter the verified LIVE SQL Server name.
]

@Field Map<String, List<String>> databasesByEnvironment = [
    TEST: [
        'H_U_ASSIRAAT',
        'H_U_Kaleem',
        'H_U_NHMC'
    ],
    UAT: [
        'pakred_uat'
    ],
    LIVE: [
        // Add the exact LIVE database names before using LIVE.
    ]
]

@Field Map<String, String> credentialsByEnvironment = [
    TEST: 'sql-test-dbs-credentials',
    UAT : 'sql-uat-dbs-credentials',
    LIVE: 'sql-live-dbs-credentials'
]

@Field String migrationPattern =
    '^V\\d{8}_\\d{3}__[a-zA-Z0-9_]+\\.sql$'

// ============================================================
// BASIC SQL SAFETY SCAN
// This is a guardrail, not a security boundary.
// ============================================================

@NonCPS
String removeSqlCommentsAndStrings(String sql) {
    String text = sql.replaceAll(/(?s)\/\*.*?\*\//, ' ')
    text = text.replaceAll(/(?m)--.*$/, ' ')
    text = text.replaceAll(/'(?:''|[^'])*'/, "''")
    text = text.replaceAll(/"(?:\"\"|[^"])*"/, '""')
    return text
}

@NonCPS
List<String> findUnsafeSql(String sql) {
    String clean = removeSqlCommentsAndStrings(sql)

    List<String> forbiddenPatterns = [
        '(?i)\\bDROP\\s+(TABLE|DATABASE|PROCEDURE|VIEW|INDEX|SCHEMA)\\b',
        '(?i)\\bTRUNCATE\\s+TABLE\\b',
        '(?i)\\bDELETE\\s+(FROM\\s+)?',
        '(?i)\\bALTER\\s+TABLE\\b[^;]*\\bDROP\\s+COLUMN\\b',
        '(?i)\\b(GRANT|REVOKE|DENY)\\b'
    ]

    return forbiddenPatterns.findAll { pattern ->
        clean =~ pattern
    }
}

// ============================================================
// PIPELINE
// ============================================================

pipeline {
    agent none

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timestamps()
        skipDefaultCheckout(true)
    }

    parameters {
        choice(
            name: 'TARGET_ENV',
            choices: ['TEST', 'UAT', 'LIVE'],
            description: 'Choose TEST, UAT, or LIVE.'
        )

        choice(
            name: 'EXECUTION_MODE',
            choices: [
                'DRY_RUN_ROLLBACK',
                'COMMIT_CHANGES',
                'HEALTH_CHECK_ONLY'
            ],
            description: 'Choose dry run, commit changes, or health check.'
        )
    }

    stages {

        // ----------------------------------------------------
        // 1. Validate environment configuration
        // ----------------------------------------------------

        stage('Validate Configuration') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                script {
                    String targetEnv = params.TARGET_ENV

                    String targetServer =
                        serverByEnvironment[targetEnv]

                    List<String> configuredDatabases =
                        databasesByEnvironment[targetEnv] ?: []

                    String credentialId =
                        credentialsByEnvironment[targetEnv]

                    if (!targetServer?.trim()) {
                        error(
                            "The SQL Server for ${targetEnv} is not configured. " +
                            'Update serverByEnvironment before running this environment.'
                        )
                    }

                    if (configuredDatabases.isEmpty()) {
                        error(
                            "No databases are configured for ${targetEnv}. " +
                            'Update databasesByEnvironment first.'
                        )
                    }

                    if (!credentialId?.trim()) {
                        error(
                            "No Jenkins credential ID is configured for ${targetEnv}."
                        )
                    }

                    echo "Environment: ${targetEnv}"
                    echo "SQL Server: ${targetServer}"
                    echo "Configured databases: ${configuredDatabases.join(', ')}"
                    echo "Execution mode: ${params.EXECUTION_MODE}"
                }
            }
        }

        // ----------------------------------------------------
        // 2. Checkout migration repository
        // ----------------------------------------------------

        stage('Checkout Repository') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                deleteDir()

                git(
                    url: 'https://github.com/UmerAzizGujjar/Hospital-DB-Migrations.git',
                    branch: 'main',
                    credentialsId: 'f2d6a7df-0fbc-46ae-a972-2aeb85e24bba'
                )

                script {
                    if (!fileExists('migrations')) {
                        error('The migrations directory was not found.')
                    }
                }
            }
        }

        // ----------------------------------------------------
        // 3. Discover and select migration file
        // ----------------------------------------------------

        stage('Select Migration File') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                script {
                    def files = findFiles(
                        glob: 'migrations/*.sql'
                    )

                    discoveredFilesList = files
                        .collect { it.name }
                        .findAll { it ==~ migrationPattern }
                        .sort()

                    if (discoveredFilesList.isEmpty()) {
                        error(
                            'No migration files matched the required pattern: ' +
                            'VYYYYMMDD_NNN__description.sql'
                        )
                    }

                    echo 'Available migration files:'
                    discoveredFilesList.each {
                        echo " - ${it}"
                    }

                    def chosenFile = input(
                        message: 'Select the SQL migration file.',
                        ok: 'Continue',
                        parameters: [
                            choice(
                                name: 'MIGRATION_FILE',
                                choices: discoveredFilesList.join('\n'),
                                description: 'Choose one migration file.'
                            )
                        ]
                    )

                    env.SELECTED_MIGRATION_FILE =
                        chosenFile.toString()

                    if (!(env.SELECTED_MIGRATION_FILE ==~ migrationPattern)) {
                        error('Invalid migration filename.')
                    }

                    if (!fileExists(
                        "migrations/${env.SELECTED_MIGRATION_FILE}"
                    )) {
                        error('The selected migration file does not exist.')
                    }

                    echo "Selected migration: ${env.SELECTED_MIGRATION_FILE}"
                }
            }
        }

        // ----------------------------------------------------
        // 4. SQL safety scan
        // ----------------------------------------------------

        stage('SQL Safety Scan') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                script {
                    String sql = readFile(
                        "migrations/${env.SELECTED_MIGRATION_FILE}"
                    )

                    List<String> matches = findUnsafeSql(sql)

                    if (!matches.isEmpty()) {
                        error(
                            'The safety scan found a prohibited SQL pattern. ' +
                            'Review the migration before proceeding.'
                        )
                    }

                    echo 'Basic SQL safety scan passed.'
                }
            }
        }

        // ----------------------------------------------------
        // 5. Select one or more databases
        // ----------------------------------------------------

        stage('Select Target Databases') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                script {
                    List<String> candidates =
                        databasesByEnvironment[params.TARGET_ENV] ?: []

                    if (candidates.isEmpty()) {
                        error('No databases are available for selection.')
                    }

                    def checkboxParams = candidates.withIndex().collect {
                        dbName, index ->
                            booleanParam(
                                name: "DB_${index}",
                                defaultValue: false,
                                description: dbName
                            )
                    }

                    def answers = input(
                        message:
                            "Select the database(s) for ${params.TARGET_ENV}.",
                        ok: 'Continue',
                        parameters: checkboxParams
                    )

                    selectedDatabases = []

                    candidates.eachWithIndex { dbName, index ->
                        String key = "DB_${index}"

                        boolean selected = false

                        if (answers instanceof Map) {
                            selected =
                                answers[key] == true ||
                                answers[key]?.toString()
                                    ?.equalsIgnoreCase('true')
                        } else if (candidates.size() == 1) {
                            selected =
                                answers == true ||
                                answers?.toString()
                                    ?.equalsIgnoreCase('true')
                        }

                        if (selected) {
                            selectedDatabases.add(dbName)
                        }
                    }

                    if (selectedDatabases.isEmpty()) {
                        error(
                            'No databases were selected. Nothing was executed.'
                        )
                    }

                    echo "Selected databases: ${selectedDatabases.join(', ')}"
                }
            }
        }

        // ----------------------------------------------------
        // 6. Approval before sensitive execution
        // ----------------------------------------------------

        stage('Approve Migration') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                script {
                    String summary = """
Environment: ${params.TARGET_ENV}
SQL Server: ${serverByEnvironment[params.TARGET_ENV]}
Execution mode: ${params.EXECUTION_MODE}
Migration file: ${env.SELECTED_MIGRATION_FILE}
Target databases: ${selectedDatabases.join(', ')}
""".trim()

                    if (
                        params.TARGET_ENV == 'LIVE' ||
                        params.EXECUTION_MODE == 'COMMIT_CHANGES'
                    ) {
                        input(
                            message: """Review the migration details carefully:

${summary}

Approve only if the target environment and databases are correct.""",
                            ok: 'Approve Execution',
                            submitterParameter: 'APPROVED_BY'
                        )
                    } else {
                        echo summary
                    }
                }
            }
        }

        // ----------------------------------------------------
        // 7. Execute migration on each selected database
        // ----------------------------------------------------

        stage('Execute Migration') {
            agent {
                label 'PAKRED_LIVE_SERVER'
            }

            steps {
                script {
                    String targetServer =
                        serverByEnvironment[params.TARGET_ENV]

                    String credentialId =
                        credentialsByEnvironment[params.TARGET_ENV]

                    for (String dbName : selectedDatabases) {

                        echo "Processing database: ${dbName}"

                        withCredentials([
                            usernamePassword(
                                credentialsId: credentialId,
                                usernameVariable: 'DB_USER',
                                passwordVariable: 'DB_PASS'
                            )
                        ]) {
                            withEnv([
                                "TARGET_DATABASE=${dbName}",
                                "DB_SERVER=${targetServer}",
                                "RUN_MODE=${params.EXECUTION_MODE}",
                                "SQL_FILE_PATH=${pwd()}\\migrations\\${env.SELECTED_MIGRATION_FILE}"
                            ]) {
                                powershell(
                                    label:
                                        "SQL ${params.EXECUTION_MODE}: ${dbName}",
                                    script: '''
$ErrorActionPreference = 'Stop'

# Build the connection string safely, including passwords
# that contain semicolons or other special characters.
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source'] = $env:DB_SERVER
$builder['Initial Catalog'] = $env:TARGET_DATABASE
$builder['User ID'] = $env:DB_USER
$builder['Password'] = $env:DB_PASS
$builder['Encrypt'] = $true
$builder['TrustServerCertificate'] = $true
$builder['Connect Timeout'] = 15

$connection = New-Object System.Data.SqlClient.SqlConnection(
    $builder.ConnectionString
)

$transaction = $null

try {
    $connection.Open()

    # Health check: connect and verify SQL execution only.
    if ($env:RUN_MODE -eq 'HEALTH_CHECK_ONLY') {
        $command = $connection.CreateCommand()

        try {
            $command.CommandText = 'SELECT 1'
            $command.CommandTimeout = 15
            $null = $command.ExecuteScalar()
        }
        finally {
            $command.Dispose()
        }

        Write-Output "Health check passed for $($env:TARGET_DATABASE)."
        exit 0
    }

    $sqlPath = $env:SQL_FILE_PATH

    if (-not (Test-Path -LiteralPath $sqlPath)) {
        throw 'The migration file was not found.'
    }

    $sqlText = Get-Content -LiteralPath $sqlPath -Raw

    if ([string]::IsNullOrWhiteSpace($sqlText)) {
        throw 'The migration file is empty.'
    }

    if (
        $env:RUN_MODE -ne 'DRY_RUN_ROLLBACK' -and
        $env:RUN_MODE -ne 'COMMIT_CHANGES'
    ) {
        throw 'Unsupported execution mode.'
    }

    $transaction = $connection.BeginTransaction()

    # Split SQL Server batches separated by GO on a line.
    $batches = [regex]::Split(
        $sqlText,
        '(?im)^\s*GO\s*(?:--.*)?$'
    )

    foreach ($batch in $batches) {
        if ([string]::IsNullOrWhiteSpace($batch)) {
            continue
        }

        $command = $connection.CreateCommand()
        $command.Transaction = $transaction
        $command.CommandTimeout = 120
        $command.CommandText = $batch

        try {
            $null = $command.ExecuteNonQuery()
        }
        finally {
            $command.Dispose()
        }
    }

    if ($env:RUN_MODE -eq 'DRY_RUN_ROLLBACK') {
        $transaction.Rollback()

        Write-Output (
            "Dry run completed and transaction rolled back for " +
            "$($env:TARGET_DATABASE)."
        )
    }
    else {
        $transaction.Commit()

        Write-Output (
            "Migration committed successfully for " +
            "$($env:TARGET_DATABASE)."
        )
    }
}
catch {
    if ($null -ne $transaction) {
        try {
            if ($transaction.Connection -ne $null) {
                $transaction.Rollback()
            }
        }
        catch {
            Write-Warning 'Rollback could not be completed.'
        }
    }

    Write-Error (
        "Migration failed for $($env:TARGET_DATABASE). " +
        "Review the SQL Server and Jenkins logs."
    )

    throw
}
finally {
    if ($null -ne $transaction) {
        $transaction.Dispose()
    }

    if ($connection.State -ne 'Closed') {
        $connection.Close()
    }

    $connection.Dispose()
}
'''
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Jenkins pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Review the logs before retrying.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
