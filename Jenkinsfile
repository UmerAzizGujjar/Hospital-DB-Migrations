
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

    stages {
        stage('Checkout Repository') {
            steps {
                checkout scm
            }
        }

        stage('Discover Migrations') {
            steps {
                script {
                    def output = bat(
                        returnStdout: true,
                        script: '@echo off\r\ngit ls-files migrations'
                    ).trim()

                    def files = output
                        .split(/\r?\n/)
                        .collect { it.trim() }
                        .findAll {
                            it &&
                            it.matches(
                                'migrations/(.*/)?V[0-9]{8}_[0-9]{3}__[A-Za-z0-9_-]+[.]sql'
                            )
                        }

                    if (files.isEmpty()) {
                        error('No valid migration files found in migrations/.')
                    }

                    def migrations = []

                    for (file in files) {
                        def timestampText = bat(
                            returnStdout: true,
                            script: "@echo off\r\ngit log -1 --format=%%ct -- \"${file}\""
                        ).trim()

                        if (!timestampText.isLong()) {
                            error("Could not determine last commit time for ${file}")
                        }

                        migrations.add([
                            file: file,
                            timestamp: timestampText.toLong()
                        ])
                    }

                    migrations.sort { a, b ->
                        b.timestamp <=> a.timestamp
                    }

                    def nowSeconds =
                        (System.currentTimeMillis() / 1000L) as long

                    def choices = migrations.collect { m ->
                        def age = Math.max(
                            0L, nowSeconds - m.timestamp
                        )

                        def ageText

                        if (age < 60) {
                            ageText = "${age}s ago"
                        } else if (age < 3600) {
                            ageText = "${(age / 60) as long}m ago"
                        } else if (age < 86400) {
                            ageText = "${(age / 3600) as long}h ago"
                        } else {
                            ageText = "${(age / 86400) as long}d ago"
                        }

                        "${m.file} || ${ageText}"
                    }

                    echo "Found ${choices.size()} migration file(s)."

                    env.MIGRATION_CHOICES = choices.join('\n')
                }
            }
        }

        stage('Select Migration') {
            steps {
                script {
                    def selected = input(
                        message: 'Choose a migration to validate',
                        ok: 'Validate selected migration',
                        parameters: [
                            choice(
                                name: 'MIGRATION_CHOICE',
                                choices: env.MIGRATION_CHOICES,
                                description: 'Newest migration commits appear first.'
                            )
                        ]
                    )

                    env.SELECTED_MIGRATION =
                        selected.split(/\s+\|\|\s+/, 2)[0]

                    echo "Selected migration: ${env.SELECTED_MIGRATION}"
                }
            }
        }

        stage('Validate Request') {
            steps {
                script {
                    def migration = env.SELECTED_MIGRATION

                    if (!migration || !fileExists(migration)) {
                        error('Selected migration file was not found.')
                    }

                    echo 'Migration path validation passed.'
                }
            }
        }

        stage('Review Migration File') {
            steps {
                script {
                    def sql = readFile(
                        file: env.SELECTED_MIGRATION,
                        encoding: 'UTF-8'
                    )

                    if (!sql.trim()) {
                        error('Migration file is empty.')
                    }

                    echo "File size: ${sql.length()} characters."
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
