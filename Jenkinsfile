pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(
            numToKeepStr: '15',
            daysToKeepStr: '15'
        ))
    }

    parameters {
        choice(
            name: 'MODE',
            choices: ['DRY_RUN'],
            description: 'Only dry-run validation is enabled.'
        )

        string(
            name: 'MIGRATION_FILE',
            defaultValue: '',
            description: 'Exact path, e.g. migrations/V20261013_001__example.sql'
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
                        error('Database deployment is disabled.')
                    }

                    def migration = params.MIGRATION_FILE?.trim()

                    if (!migration) {
                        error('Enter the exact migration file path.')
                    }

                    def validName = migration.matches(
                        'migrations/V[0-9]{8}_[0-9]{3}__[A-Za-z0-9_-]+[.]sql'
                    )

                    if (!validName) {
                        error('Invalid path or filename. Check the required naming format.')
                    }

                    if (!fileExists(migration)) {
                        error("Migration file not found: ${migration}")
                    }

                    echo "Requested migration: ${migration}"
                    echo 'Request validation passed.'
                }
            }
        }

        stage('Review Migration File') {
            steps {
                script {
                    def migration = params.MIGRATION_FILE.trim()

                    def sql = readFile(
                        file: migration,
                        encoding: 'UTF-8'
                    )

                    if (!sql.trim()) {
                        error('Migration file is empty.')
                    }

                    echo "File size: ${sql.length()} characters."
                    echo 'Basic file validation passed.'
                    echo 'Manual SQL review is still required.'
                }
            }
        }

        stage('Dry-Run Report') {
            steps {
                echo 'DRY RUN ONLY'
                echo 'No SQL was executed.'
                echo 'No database connection was made.'
                echo 'No database changes occurred.'
            }
        }
    }

    post {
        success {
            echo 'Migration file validation completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Review the console output.'
        }

        always {
            echo 'Database deployment remains disabled.'
        }
    }
}
