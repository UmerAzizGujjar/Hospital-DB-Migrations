
stage('Select Migration') {
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
                    it && it.matches(
                        'migrations/(.*/)?V[0-9]{8}_[0-9]{3}__[A-Za-z0-9_-]+[.]sql'
                    )
                }

            if (files.isEmpty()) {
                error('No valid migration files found in migrations/.')
            }

            def migrations = files.collect { file ->
                def timestamp = bat(
                    returnStdout: true,
                    script: "@echo off\r\ngit log -1 --format=%%ct -- \"${file}\""
                ).trim()

                if (!(timestamp ==~ /[0-9]+/)) {
                    error("Could not read the last commit time for ${file}")
                }

                [
                    file: file,
                    timestamp: timestamp.toLong()
                ]
            }

            migrations.sort { a, b ->
                b.timestamp <=> a.timestamp
            }

            def now = System.currentTimeMillis() / 1000L

            def choices = migrations.collect { m ->
                def age = Math.max(0L, now - m.timestamp)
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

                "${m.file} — ${ageText}"
            }

            def selected = input(
                message: 'Select a migration to validate (newest first)',
                ok: 'Validate migration',
                parameters: [
                    choice(
                        name: 'MIGRATION_FILE',
                        choices: choices.join('\n'),
                        description: 'Each option includes the time since its latest Git commit.'
                    )
                ]
            )

            env.SELECTED_MIGRATION = selected.split(/ — /, 2)[0]

            echo "Selected migration: ${env.SELECTED_MIGRATION}"
        }
    }
}
