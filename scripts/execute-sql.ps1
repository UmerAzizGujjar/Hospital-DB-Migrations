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
    Write-Output '--------------------------------------------------------'
    Write-Output "EXECUTING ON DATABASE: $env:SQL_DATABASE"
    Write-Output '--------------------------------------------------------'

    if ($env:USE_CUSTOM_QUERY -eq 'true') {
        # Active Choices may inject literal \n / \r text; convert back to real line breaks
        $sql = $env:SQL_CUSTOM_TEXT -replace '\\n', "`n" -replace '\\r', "`r"
    } else {
        $sql = Get-Content -LiteralPath $env:SQL_MIGRATION_FILE -Raw
    }

    $batches = [regex]::Split($sql, '(?im)^\s*GO\s*(?:--.*)?$')
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
        Write-Output ' '
        Write-Output "[$env:SQL_DATABASE] !!! SQL ERROR !!!"
        Write-Output "[$env:SQL_DATABASE] Error Details: $($_.Exception.Message)"
        Write-Output ' '
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
