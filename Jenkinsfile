// Hospital-DB-Migrations: VALIDATION-ONLY pipeline.
// It never connects to SQL Server and never executes SQL.

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '15', daysToKeepStr: '15'))
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {

        stage('Preflight') {
            steps {
                script {
                    if (isUnix()) {
                        error('This pipeline requires a Windows Jenkins agent.')
                    }
                    winOut('git --version')
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def shallow = winOut('git rev-parse --is-shallow-repository')
                    if (shallow == 'true') {
                        echo 'WARNING: Shallow clone detected. Commit times may be inaccurate. ' +
                             'Disable "Shallow clone" in the job SCM settings.'
                    }
                }
            }
        }

        stage('Select Migration') {
            steps {
                script {
                    // 1. Discover tracked files under migrations/
                    def lines = winOut('git ls-files -- migrations').split(/\r?\n/)
                    def files = []
                    for (String line : lines) {
                        String f = line.trim()
                        if (f && (f ==~ migrationRegex())) {
                            files << f
                        }
                    }
                    if (files.isEmpty()) {
                        error('No valid migration files found in migrations/. ' +
                              'Expected: migrations/VYYYYMMDD_NNN__description.sql')
                    }

                    // 2. Latest commit time (epoch seconds) per file
                    def items = []
                    for (String f : files) {
                        String ts = winOut("git log -1 --format=%%ct -- \"${f}\"")
                        if (!(ts ==~ /[0-9]+/)) {
                            error("Could not read the latest Git commit time for ${f}")
                        }
                        items << [file: f, ts: ts.toLong()]
                    }

                    // 3. Newest commit first, then build labels
                    items = sortNewestFirst(items)
                    long nowEpoch = (long) (new Date().getTime() / 1000)

                    def labelToFile = [:]
                    def labels = []
                    for (def it2 : items) {
                        long age = nowEpoch - (long) it2.ts
                        if (age < 0) { age = 0 }   // agent/committer clock skew
                        String label = "${it2.file} \u2014 ${relativeAge(age)}"
                        labels << label
                        labelToFile[label] = it2.file
                    }

                    // 4. Ask the user
                    def selectedLabel
                    timeout(time: 10, unit: 'MINUTES') {
                        selectedLabel = input(
                            message: 'Select a migration to validate (newest first)',
                            ok: 'Validate migration',
                            parameters: [
                                choice(
                                    name: 'MIGRATION_FILE',
                                    choices: labels,
                                    description: 'Time shown is since the latest Git commit of each file.'
                                )
                            ]
                        )
                    }

                    // 5. Map label back to path (no string splitting)
                    String selected = labelToFile[selectedLabel as String]
                    if (!selected) {
                        error("Unknown selection: ${selectedLabel}")
                    }
                    env.SELECTED_MIGRATION = selected
                    echo "Selected migration: ${env.SELECTED_MIGRATION}"
                }
            }
        }

        stage('Validate Migration') {
            steps {
                script {
                    String path = env.SELECTED_MIGRATION

                    if (!(path ==~ migrationRegex())) {
                        error("Selected path does not match the naming convention: ${path}")
                    }
                    if (!fileExists(path)) {
                        error("Selected file does not exist in the workspace: ${path}")
                    }

                    String content = readFile(file: path, encoding: 'UTF-8')
                    content = content.replace('\uFEFF', '')   // strip BOM if present
                    if (content.trim().isEmpty()) {
                        error("Migration file is empty or whitespace-only: ${path}")
                    }

                    String winPath = path.replace('/', '\\')
                    String size = winOut("for %%A in (\"${winPath}\") do @echo %%~zA")

                    echo "Validated migration: ${path}"
                    echo "File size: ${size} bytes"
                }
            }
        }

        stage('Dry-Run Report') {
            steps {
                echo '=============================================='
                echo 'DRY RUN - VALIDATION ONLY'
                echo "Migration checked : ${env.SELECTED_MIGRATION}"
                echo 'No SQL was executed.'
                echo 'No database connection was made.'
                echo 'No database changes occurred.'
                echo '=============================================='
            }
        }
    }

    post {
        success { echo 'Validation finished successfully (dry run).' }
        failure { echo 'Validation failed. See the error above. No database was touched.' }
    }
}

// ---------- Helpers ----------

String migrationRegex() {
    return '^migrations/V[0-9]{8}_[0-9]{3}__[A-Za-z0-9_-]+[.]sql$'
}

// Runs a Windows batch command quietly and returns trimmed stdout.
// Remember to double % signs (%%) because Jenkins writes a .bat file.
String winOut(String cmd) {
    return bat(returnStdout: true, script: "@echo off\r\n${cmd}").trim()
}

// Sorting with closures must not run under CPS.
@NonCPS
List sortNewestFirst(List items) {
    return items.sort(false) { a, b ->
        int c = (b.ts <=> a.ts)
        c != 0 ? c : (a.file <=> b.file)
    }
}

String plural(long n, String unit) {
    return n == 1 ? "1 ${unit} ago" : "${n} ${unit}s ago"
}

String relativeAge(long s) {
    if (s < 60)    { return plural(s, 'second') }
    if (s < 3600)  { return plural((long) (s / 60), 'minute') }
    if (s < 86400) { return plural((long) (s / 3600), 'hour') }
    return plural((long) (s / 86400), 'day')
}
