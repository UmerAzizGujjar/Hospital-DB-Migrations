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
        # Also drop a stray backslash sitting right before a real line break
        $sql = $sql -replace '\\(?=\r?\n)', ''
        # Jenkins/Active Choices can append a stray trailing comma (joined parameter values); no valid SQL ends with one
        $sql = $sql -replace ',\s*$', ''
    } else {
        $sql = Get-Content -LiteralPath $env:SQL_MIGRATION_FILE -Raw
    }

    # Normalise every kind of line ending to LF, then split on GO line by line
    $sql = $sql -replace "`r`n", "`n" -replace "`r", "`n"

    $batches = @()
    $current = New-Object System.Text.StringBuilder
    foreach ($line in $sql.Split("`n")) {
        if ($line -match '^\s*GO\s*[,;]?\s*(--.*)?$') {
            $batches += $current.ToString()
            [void]$current.Clear()
        } else {
            [void]$current.AppendLine($line)
        }
    }
    $batches += $current.ToString()

    Write-Output "[$env:SQL_DATABASE] Parsed $($batches.Count) batch(es)."
    $transaction = $connection.BeginTransaction()

    try {
        foreach ($batch in $batches) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }

            $command = $connection.CreateCommand()
            $command.Transaction = $transaction
            $command.CommandTimeout = 120
            $command.CommandText = $batch

            try {
                # Determine if it's a SELECT query to display results
                if ($batch.Trim() -match '^(?i)SELECT') {
                    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
                    $dataset = New-Object System.Data.DataSet
                    [void]$adapter.Fill($dataset)
                    
                    if ($dataset.Tables.Count -gt 0 -and $dataset.Tables[0].Rows.Count -gt 0) {
                        Write-Output "[$env:SQL_DATABASE] Query Results:"
                        $dataset.Tables[0] | Format-Table -AutoSize | Out-String | Write-Output
                    } else {
                        Write-Output "[$env:SQL_DATABASE] (0 row(s) returned)"
                    }
                } else {
                    $rowsAffected = $command.ExecuteNonQuery()
                    if ($rowsAffected -ge 0) {
                        Write-Output "[$env:SQL_DATABASE] ($rowsAffected row(s) affected)"
                    } else {
                        Write-Output "[$env:SQL_DATABASE] Command completed successfully."
                    }
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
        if ($batch) {
            $preview = ($batch -replace "`r", '<CR>' -replace "`n", '<LF>')
            if ($preview.Length -gt 400) { $preview = $preview.Substring(0, 400) }
            Write-Output "[$env:SQL_DATABASE] Failing batch (first 400 chars): $preview"
        }
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
