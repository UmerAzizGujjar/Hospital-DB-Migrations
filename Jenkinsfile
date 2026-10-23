def environmentConfig = [:]
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
            steps { 
                checkout scm 
            }
        }

        stage('Load Configuration') {
            steps {
                script {
                    // Dynamically read the environments and databases from the external JSON file
                    environmentConfig = readJSON file: 'config/environments.json'
                }
            }
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

                    selectedDatabases = (params.DATABASES ?: '')
                        .toString()
                        .split(/[,;\r\n]+/)
                        .collect { it.trim() }
                        .findAll { it }

                    if (!selectedDatabases || selectedDatabases.contains('No_Databases_Configured')) {
                        error 'Select at least one valid database.'
                    }

                    def invalidDatabases = selectedDatabases.findAll { !(it in config.databases.keySet()) }

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
                expression { !(params.USE_CUSTOM_QUERY?.toString() == 'Yes') }
            }
            steps {
                script {
                    def fileOutput = powershell(
                        returnStdout: true,
                        script: './scripts/list-migrations.ps1'
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

                    selectedMigration = rawSelection.split('::')[0].trim()

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
                    def dbMap = environmentConfig[target].databases
                    def hasErrors = false

                    for (String db in selectedDatabases) {
                        def dbProps = dbMap[db]
                        
                        try {
                            // Dynamically switch to the specific server node for this database
                            node(dbProps.node) {
                                // Checking out SCM ensures the node pulls the external script files to its local workspace
                                checkout scm
                                
                                withCredentials([
                                    usernamePassword(credentialsId: dbProps.credentialId, usernameVariable: 'SQL_USER', passwordVariable: 'SQL_PASSWORD')
                                ]) {
                                    withEnv([
                                        "SQL_SERVER=${dbProps.server}",
                                        "SQL_DATABASE=${db}",
                                        "SQL_MIGRATION_FILE=${selectedMigration}",
                                        "USE_CUSTOM_QUERY=${useCustom}",
                                        "SQL_CUSTOM_TEXT=${params.CUSTOM_SQL_TEXT ?: ''}"
                                    ]) {
                                        powershell './scripts/execute-sql.ps1'
                                    }
                                }
                            }
                        } catch (Exception e) {
                            echo "--------------------------------------------------------"
                            echo "ERROR ON ${db}. CONTINUING TO NEXT DATABASE..."
                            echo "Pipeline Error Details: ${e.getMessage()}"
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
                expression { params.USE_CUSTOM_QUERY?.toString() == 'Yes' }
            }
            steps {
                script {
                    withCredentials([
                        usernamePassword(credentialsId: 'f2d6a7df-0fbc-46ae-a972-2aeb85e24bba', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')
                    ]) {
                        withEnv([
                            "CUSTOM_FILE_NAME=${params.CUSTOM_FILE_NAME ?: ''}",
                            "SQL_CUSTOM_TEXT=${params.CUSTOM_SQL_TEXT ?: ''}"
                        ]) {
                            powershell './scripts/commit-custom-query.ps1'
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
