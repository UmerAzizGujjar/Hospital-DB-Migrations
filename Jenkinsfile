pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    stages {
        stage('Checkout Repository') {
            steps {
                checkout scm
            }
        }

        stage('Validate Migration Files') {
            steps {
                script {
                    def migrations = findFiles(
                        glob: 'migrations/**/*.sql'
                    )

                    if (migrations.length == 0) {
                        error('No SQL migration files found. No database changes were made.')
                    }

                    echo "Found ${migrations.length} SQL migration file(s):"

                    migrations.each { migration ->
                        echo " - ${migration.path}"
                    }
                }
            }
        }

        stage('Deployment Status') {
            steps {
                echo 'Validation only. Database deployment is not enabled.'
            }
        }
    }
}
