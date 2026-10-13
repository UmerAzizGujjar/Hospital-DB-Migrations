pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        choice(
            name: 'MODE',
            choices: ['DRY_RUN'],
            description: 'Only DRY_RUN is enabled until database safeguards are verified.'
        )

        string(
            name: 'MIGRATION_FILE',
            defaultValue: '',
            description: 'Exact SQL file path, e.g. migrations/V20261013_001__example.sql'
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
                    if (params.MODE != 'DRY_RUN') {
                        error('Database deployment is disabled in this initial version.')
                    }

                    if (!params.MIGRATION_FILE?.trim()) {
                        error('Enter the exact migration file path.')
                    }

                    if (!(params.MIGRATION_FILE ==~
                        /migrations\/V[0-9]{8}_[0-9]{3}__[A-Za-z0-9_-]+\.sql/)) {
                        error('Invalid migration filename. Follow the documented naming format.')
                    }

                    if (!fileExists(params.MIGRATION_FILE)) {
                        error("Migration file not found: ${params.MIGRATION_FILE}")
                    }

                    echo "Requested migration: ${params.MIGRATION_FILE}"
                    echo 'Request validation passed.'
                }
            }
        }

        stage('Review Migration') {
            steps {
                script {
                    def sql = readFile(
                        file: params.MIGRATION_FILE,
                        encoding: 'UTF-8'
                    )

                    if (!sql.trim()) {
                        error('Migration file is empty.')
                    }

                    if (sql.contains('\u0000')) {
                        error('Migration contains a null character.')
                    }

                    echo "Migration size: ${sql.length()} characters."
                    echo 'Manual SQL review is still required.'
                    echo 'No SQL was executed and no database was contacted.'
                }
            }
        }

        stage('Dry-Run Report') {
            steps {
                echo 'DRY RUN ONLY'
                echo 'The selected migration passed basic file checks.'
                echo 'No database connection or database changes occurred.'
            }
        }
    }

    post {
        success {
            echo 'Initial validation completed successfully.'
        }

        failure {
            echo 'Validation failed. Review the Jenkins console output.'
        }

        always {
            echo 'Pipeline finished. Database deployment remains disabled.'
        }
    }
}
