Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupDir = Join-Path $scriptDir "backups"
if (-not (Test-Path $backupDir)) { [void](New-Item -ItemType Directory -Path $backupDir) }

function UndoSql-ForRule($ruleId) {
    return @"
DELETE FROM "FRM_ALERT_DOCUMENT" WHERE "alert_Id" IN (SELECT id FROM "FRM_ALERTS" WHERE "rule_Id" = $ruleId);
DELETE FROM "FRM_ALERT_INVESTIGATION_DATA" WHERE "alert_Id" IN (SELECT id FROM "FRM_ALERTS" WHERE "rule_Id" = $ruleId);
DELETE FROM "FRM_ALERT_GENERATED_FOR_DATA" WHERE "alert_Id" IN (SELECT id FROM "FRM_ALERTS" WHERE "rule_Id" = $ruleId);
DELETE FROM "FRM_ALERTS" WHERE "rule_Id" = $ruleId;
DELETE FROM "FRM_RULE_HISTORY" WHERE "frmRule_Id" = $ruleId;
DELETE FROM "FRM_RULE" WHERE id = $ruleId;
"@
}

# Undo reverses exactly what the matching seed script's INSERTs create - alerts/evidence for the
# rule first (FK children), then the rule itself, then that script's own seed rows (FK parents last).
# STOCK/SECURITY_DETAILS ids 31-33 are seeded by BOTH Inventory and Receivables (shared ON CONFLICT
# DO NOTHING fixture) - undoing one while the other's alerts still reference them is a known gap,
# flagged in the confirmation dialog rather than silently left broken.
# SMA_LOG id 201 (account 31) is shared by Default In SMA1 and Quick SMA the same way, but its
# insert now lives only in Foundation (item 0), so only undoing Foundation removes it - undoing
# item 3 or 4 alone leaves it in place for the other to keep using.
$items = @(
    @{ Label = "0. Foundation setup (account/customer/hierarchy/user)"; File = "00_foundation.sql"; RuleId = $null
       UndoSql = @'
DELETE FROM "FRM_ALERT_GENERATED_FOR_DATA" WHERE "smaLogs_Id" = 201;
DELETE FROM "SMA_LOG" WHERE id = 201;
DELETE FROM "ACCOUNT_CUSTOMER" WHERE id = 31;
DELETE FROM "CUSTOMER_DETAILS" WHERE id = 31;
DELETE FROM "ACCOUNT" WHERE id = 31;
DELETE FROM "GENERAL_LEDGER" WHERE id = 71;
DELETE FROM "USER" WHERE id = 1;
DELETE FROM "FRM_ALERT_HIERARCHY" WHERE id = 1;
'@ },
    @{ Label = "1. Significant Movement In Inventory";                  File = "01_inventory.sql"; RuleId = 501
       UndoSql = (UndoSql-ForRule 501) + @'

DELETE FROM "FRM_ALERT_GENERATED_FOR_DATA" WHERE "stock_Id" IN (31,32,33);
DELETE FROM "STOCK" WHERE id IN (31,32,33);
DELETE FROM "SECURITY_DETAILS" WHERE id = 31;
'@ },
    @{ Label = "2. Significant Movement In Receivables";                File = "02_receivables.sql"; RuleId = 502
       UndoSql = (UndoSql-ForRule 502) + @'

DELETE FROM "FRM_ALERT_GENERATED_FOR_DATA" WHERE "stock_Id" IN (31,32,33);
DELETE FROM "STOCK" WHERE id IN (31,32,33);
DELETE FROM "SECURITY_DETAILS" WHERE id = 31;
'@ },
    @{ Label = "3. Default In SMA1";                                    File = "03_default_sma1.sql"; RuleId = 503
       # No SMA_LOG delete here - id 201 is now owned by Foundation (item 0), shared with Quick SMA.
       UndoSql = UndoSql-ForRule 503 },
    @{ Label = "4. Quick SMA";                                          File = "04_quick_sma.sql"; RuleId = 504
       # No SMA_LOG/ACCOUNT delete here - reuses Foundation's shared account 31 / SMA_LOG 201, same
       # as Default In SMA1; nothing of its own left to clean up beyond the rule/alerts/evidence.
       UndoSql = UndoSql-ForRule 504 },
    @{ Label = "5. Credit Summation vs Account Limit";                  File = "05_credit_summation.sql"; RuleId = 505
       UndoSql = (UndoSql-ForRule 505) + @'

DELETE FROM "FRM_ALERT_GENERATED_FOR_DATA" WHERE "transaction_Id" IN (311,312);
DELETE FROM "TRANSACTIONS" WHERE id IN (311,312);
DELETE FROM "LOAN_ACCOUNT" WHERE id = 31;
'@ }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "FRM Test Rule Runner"
$form.Size = New-Object System.Drawing.Size(620, 1035)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# ---- Connection group ----
$grpConn = New-Object System.Windows.Forms.GroupBox
$grpConn.Text = "Database connection"
$grpConn.Location = New-Object System.Drawing.Point(15, 10)
$grpConn.Size = New-Object System.Drawing.Size(580, 130)
$form.Controls.Add($grpConn)

function New-Field($labelText, $x, $y, $default, $isPassword) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.Location = New-Object System.Drawing.Point($x, $y)
    $lbl.Size = New-Object System.Drawing.Size(70, 20)
    $grpConn.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(($x + 75), ($y - 2))
    $txt.Size = New-Object System.Drawing.Size(160, 20)
    $txt.Text = $default
    if ($isPassword) { $txt.PasswordChar = '*' }
    $grpConn.Controls.Add($txt)
    return $txt
}

$txtHost = New-Field "Host"     15  25 "localhost"  $false
$txtPort = New-Field "Port"     315 25 "5432"        $false
$txtUser = New-Field "User"     15  55 "postgres"    $false
$txtDb   = New-Field "Database" 315 55 "FRM"         $false
$txtPwd  = New-Field "Password" 15  85 "root"        $true

# ---- Rule multi-select list ----
$grpRules = New-Object System.Windows.Forms.GroupBox
$grpRules.Text = "Select rules to create (Active = FRM_RULE.status on insert)"
$grpRules.Location = New-Object System.Drawing.Point(15, 150)
$grpRules.Size = New-Object System.Drawing.Size(580, 190)
$form.Controls.Add($grpRules)

$dgvRules = New-Object System.Windows.Forms.DataGridView
$dgvRules.Location = New-Object System.Drawing.Point(10, 20)
$dgvRules.Size = New-Object System.Drawing.Size(560, 160)
$dgvRules.AllowUserToAddRows = $false
$dgvRules.AllowUserToDeleteRows = $false
$dgvRules.AllowUserToResizeRows = $false
$dgvRules.RowHeadersVisible = $false
$dgvRules.SelectionMode = "FullRowSelect"
$dgvRules.MultiSelect = $false
$dgvRules.ColumnHeadersHeightSizeMode = "AutoSize"
$dgvRules.EditMode = "EditOnEnter"

$colSelect = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colSelect.Name = "Select"
$colSelect.HeaderText = "Select"
$colSelect.Width = 55
[void]$dgvRules.Columns.Add($colSelect)

$colLabel = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colLabel.Name = "Rule"
$colLabel.HeaderText = "Rule"
$colLabel.ReadOnly = $true
$colLabel.AutoSizeMode = "Fill"
[void]$dgvRules.Columns.Add($colLabel)

$colActive = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colActive.Name = "Active"
$colActive.HeaderText = "Active?"
$colActive.Width = 60
[void]$dgvRules.Columns.Add($colActive)

foreach ($it in $items) {
    $rowIdx = $dgvRules.Rows.Add($false, $it.Label, $true)
    if ($null -eq $it.RuleId) {
        # Foundation creates no FRM_RULE row - Active toggle doesn't apply to it.
        $activeCell = $dgvRules.Rows[$rowIdx].Cells["Active"]
        $activeCell.Value = $false
        $activeCell.ReadOnly = $true
        $activeCell.Style.BackColor = [System.Drawing.SystemColors]::Control
    }
}

# Checkbox columns don't commit their new value until the cell loses focus/edit -
# commit immediately on click so Select-All/Run/Undo see the click right away.
$dgvRules.Add_CurrentCellDirtyStateChanged({
    if ($dgvRules.IsCurrentCellDirty) {
        $dgvRules.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$grpRules.Controls.Add($dgvRules)

# ---- Backup FRM_RULE ----
$grpBackup = New-Object System.Windows.Forms.GroupBox
$grpBackup.Text = "Backup"
$grpBackup.Location = New-Object System.Drawing.Point(15, 350)
$grpBackup.Size = New-Object System.Drawing.Size(580, 65)
$form.Controls.Add($grpBackup)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save Current FRM_RULE Rows"
$btnSave.Location = New-Object System.Drawing.Point(10, 22)
$btnSave.Size = New-Object System.Drawing.Size(220, 28)
$btnSave.BackColor = [System.Drawing.Color]::LightSkyBlue
$grpBackup.Controls.Add($btnSave)

$lblLastSaved = New-Object System.Windows.Forms.Label
$lblLastSaved.Text = "Not saved yet"
$lblLastSaved.Location = New-Object System.Drawing.Point(240, 28)
$lblLastSaved.Size = New-Object System.Drawing.Size(330, 18)
$lblLastSaved.AutoEllipsis = $true
$grpBackup.Controls.Add($lblLastSaved)

# ---- Maintenance (destructive) ----
$grpMaint = New-Object System.Windows.Forms.GroupBox
$grpMaint.Text = "Maintenance"
$grpMaint.Location = New-Object System.Drawing.Point(15, 425)
$grpMaint.Size = New-Object System.Drawing.Size(580, 100)
$form.Controls.Add($grpMaint)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "Truncate FRM_RULE + FRM_ALERTS"
$btnReset.Location = New-Object System.Drawing.Point(10, 22)
$btnReset.Size = New-Object System.Drawing.Size(230, 28)
$btnReset.BackColor = [System.Drawing.Color]::LightCoral
$grpMaint.Controls.Add($btnReset)

$btnTruncAlerts = New-Object System.Windows.Forms.Button
$btnTruncAlerts.Text = "Truncate FRM_ALERTS Only"
$btnTruncAlerts.Location = New-Object System.Drawing.Point(250, 22)
$btnTruncAlerts.Size = New-Object System.Drawing.Size(200, 28)
$btnTruncAlerts.BackColor = [System.Drawing.Color]::Khaki
$grpMaint.Controls.Add($btnTruncAlerts)

$btnTruncAll = New-Object System.Windows.Forms.Button
$btnTruncAll.Text = "Truncate ALL Rule/Alert Test Data Tables"
$btnTruncAll.Location = New-Object System.Drawing.Point(10, 58)
$btnTruncAll.Size = New-Object System.Drawing.Size(440, 28)
$btnTruncAll.BackColor = [System.Drawing.Color]::IndianRed
$btnTruncAll.ForeColor = [System.Drawing.Color]::White
$grpMaint.Controls.Add($btnTruncAll)

# ---- Saved rule backups (generated INSERT scripts) ----
$grpSaved = New-Object System.Windows.Forms.GroupBox
$grpSaved.Text = "Saved Rule Backups (select one or more)"
$grpSaved.Location = New-Object System.Drawing.Point(15, 530)
$grpSaved.Size = New-Object System.Drawing.Size(580, 190)
$form.Controls.Add($grpSaved)

$lstBackups = New-Object System.Windows.Forms.ListBox
$lstBackups.Location = New-Object System.Drawing.Point(10, 20)
$lstBackups.Size = New-Object System.Drawing.Size(560, 115)
$lstBackups.SelectionMode = "MultiExtended"
$lstBackups.Font = New-Object System.Drawing.Font("Consolas", 9)
$grpSaved.Controls.Add($lstBackups)

$btnRefreshBackups = New-Object System.Windows.Forms.Button
$btnRefreshBackups.Text = "Refresh"
$btnRefreshBackups.Location = New-Object System.Drawing.Point(10, 145)
$btnRefreshBackups.Size = New-Object System.Drawing.Size(80, 28)
$grpSaved.Controls.Add($btnRefreshBackups)

$btnRunBackup = New-Object System.Windows.Forms.Button
$btnRunBackup.Text = "Run Selected"
$btnRunBackup.Location = New-Object System.Drawing.Point(100, 145)
$btnRunBackup.Size = New-Object System.Drawing.Size(115, 28)
$btnRunBackup.BackColor = [System.Drawing.Color]::LightGreen
$grpSaved.Controls.Add($btnRunBackup)

$btnRenameBackup = New-Object System.Windows.Forms.Button
$btnRenameBackup.Text = "Rename Selected"
$btnRenameBackup.Location = New-Object System.Drawing.Point(225, 145)
$btnRenameBackup.Size = New-Object System.Drawing.Size(130, 28)
$grpSaved.Controls.Add($btnRenameBackup)

$btnDeleteBackup = New-Object System.Windows.Forms.Button
$btnDeleteBackup.Text = "Delete Selected"
$btnDeleteBackup.Location = New-Object System.Drawing.Point(365, 145)
$btnDeleteBackup.Size = New-Object System.Drawing.Size(115, 28)
$btnDeleteBackup.BackColor = [System.Drawing.Color]::LightCoral
$grpSaved.Controls.Add($btnDeleteBackup)

# ---- Action buttons ----
$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = "Select All"
$btnAll.Location = New-Object System.Drawing.Point(15, 730)
$btnAll.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnAll)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Clear"
$btnClear.Location = New-Object System.Drawing.Point(125, 730)
$btnClear.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnClear)

$btnUndo = New-Object System.Windows.Forms.Button
$btnUndo.Text = "Undo Selected"
$btnUndo.Location = New-Object System.Drawing.Point(235, 730)
$btnUndo.Size = New-Object System.Drawing.Size(120, 28)
$btnUndo.BackColor = [System.Drawing.Color]::Orange
$form.Controls.Add($btnUndo)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Selected"
$btnRun.Location = New-Object System.Drawing.Point(365, 730)
$btnRun.Size = New-Object System.Drawing.Size(110, 28)
$btnRun.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($btnRun)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(480, 730)
$btnClose.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnClose)

# ---- Output log ----
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Output"
$lblLog.Location = New-Object System.Drawing.Point(15, 765)
$lblLog.Size = New-Object System.Drawing.Size(100, 18)
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, 785)
$txtLog.Size = New-Object System.Drawing.Size(580, 190)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Append-Log($text) {
    $txtLog.AppendText($text + "`r`n")
}

function Run-SqlFile($fileName) {
    $fullPath = Join-Path $scriptDir $fileName
    if (-not (Test-Path $fullPath)) {
        Append-Log "SKIP: $fileName not found at $fullPath"
        return $false
    }

    Append-Log "---- Running $fileName ----"
    $env:PGPASSWORD = $txtPwd.Text

    $psqlArgs = @(
        "-h", $txtHost.Text,
        "-p", $txtPort.Text,
        "-U", $txtUser.Text,
        "-d", $txtDb.Text,
        "-v", "ON_ERROR_STOP=1",
        "-f", $fullPath
    )

    $proc = Start-Process -FilePath "psql" -ArgumentList $psqlArgs -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput "$env:TEMP\frm_psql_out.txt" `
            -RedirectStandardError "$env:TEMP\frm_psql_err.txt"

    $out = Get-Content "$env:TEMP\frm_psql_out.txt" -Raw -ErrorAction SilentlyContinue
    $err = Get-Content "$env:TEMP\frm_psql_err.txt" -Raw -ErrorAction SilentlyContinue
    if ($out) { Append-Log $out.Trim() }
    if ($err) { Append-Log $err.Trim() }

    if ($proc.ExitCode -ne 0) {
        Append-Log "*** FAILED (exit $($proc.ExitCode)): $fileName ***"
        return $false
    }
    Append-Log "OK: $fileName"
    return $true
}

function Run-SqlText($sqlText, $label) {
    # -ArgumentList mis-splits a -c value that itself contains spaces, so write it to a
    # temp .sql file and run it with -f instead - same mechanism Run-SqlFile already uses.
    $tempSql = Join-Path $env:TEMP "frm_ui_adhoc.sql"
    Set-Content -Path $tempSql -Value $sqlText -Encoding ASCII

    Append-Log "---- Running $label ----"
    $env:PGPASSWORD = $txtPwd.Text

    $psqlArgs = @(
        "-h", $txtHost.Text,
        "-p", $txtPort.Text,
        "-U", $txtUser.Text,
        "-d", $txtDb.Text,
        "-v", "ON_ERROR_STOP=1",
        "-f", $tempSql
    )

    $proc = Start-Process -FilePath "psql" -ArgumentList $psqlArgs -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput "$env:TEMP\frm_psql_out.txt" `
            -RedirectStandardError "$env:TEMP\frm_psql_err.txt"

    $out = Get-Content "$env:TEMP\frm_psql_out.txt" -Raw -ErrorAction SilentlyContinue
    $err = Get-Content "$env:TEMP\frm_psql_err.txt" -Raw -ErrorAction SilentlyContinue
    if ($out) { Append-Log $out.Trim() }
    if ($err) { Append-Log $err.Trim() }

    if ($proc.ExitCode -ne 0) {
        Append-Log "*** FAILED (exit $($proc.ExitCode)): $label ***"
        return $false
    }
    Append-Log "OK: $label"
    return $true
}

function Refresh-BackupList {
    $lstBackups.Items.Clear()
    $files = Get-ChildItem -Path $backupDir -Filter "*.sql" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    foreach ($f in $files) { [void]$lstBackups.Items.Add($f.Name) }
}

$btnSave.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $backupDir "FRM_RULE_backup_$stamp.sql"

    Append-Log "---- Generating re-runnable INSERT script for current FRM_RULE rows -> $outFile ----"
    $env:PGPASSWORD = $txtPwd.Text

    # Builds one ready-to-run INSERT INTO "FRM_RULE" (...) VALUES (...) line per row, via
    # format()/%L so every value (including embedded quotes in jsonString) is escaped
    # correctly - no pg_dump dependency, output is plain SQL you can just re-run later.
    $genQuery = @'
SELECT format(
  'INSERT INTO "FRM_RULE" (id,name,code,description,"ruleType","startDate","endDate","jsonString",status,"alertGenerationToClassificationTat","alertActions","ruleSeverity","alertHierarchy_Id","alertHierarchyJson","createdBy_Id","updatedBy_Id","createdAt","updatedAt","isDeleted","versionNo","isScrollPending","scrollId") VALUES (%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L,%L) ON CONFLICT DO NOTHING;',
  id, name, code, description, "ruleType", "startDate", "endDate", "jsonString", status,
  "alertGenerationToClassificationTat", "alertActions", "ruleSeverity", "alertHierarchy_Id",
  "alertHierarchyJson", "createdBy_Id", "updatedBy_Id", "createdAt", "updatedAt", "isDeleted", "versionNo",
  "isScrollPending", "scrollId"
)
FROM "FRM_RULE"
ORDER BY id;
'@

    $tempGenSql = Join-Path $env:TEMP "frm_ui_gen_backup.sql"
    Set-Content -Path $tempGenSql -Value $genQuery -Encoding ASCII

    $psqlArgs = @(
        "-h", $txtHost.Text,
        "-p", $txtPort.Text,
        "-U", $txtUser.Text,
        "-d", $txtDb.Text,
        "-t", "-A",
        "-v", "ON_ERROR_STOP=1",
        "-o", $outFile,
        "-f", $tempGenSql
    )

    $btnSave.Enabled = $false
    $proc = Start-Process -FilePath "psql" -ArgumentList $psqlArgs -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput "$env:TEMP\frm_gen_out.txt" `
            -RedirectStandardError "$env:TEMP\frm_gen_err.txt"

    $out = Get-Content "$env:TEMP\frm_gen_out.txt" -Raw -ErrorAction SilentlyContinue
    $err = Get-Content "$env:TEMP\frm_gen_err.txt" -Raw -ErrorAction SilentlyContinue
    if ($out) { Append-Log $out.Trim() }
    if ($err) { Append-Log $err.Trim() }

    if ($proc.ExitCode -ne 0 -or -not (Test-Path $outFile)) {
        Append-Log "*** FAILED: generate FRM_RULE backup script ***"
        $lblLastSaved.Text = "Last save FAILED"
    } else {
        $rowCount = (Get-Content $outFile | Where-Object { $_.Trim() -ne "" }).Count
        $wrapped = "BEGIN;`r`n`r`n" + (Get-Content $outFile -Raw) + "`r`nCOMMIT;`r`n"
        Set-Content -Path $outFile -Value $wrapped -Encoding ASCII
        Append-Log "OK: saved $rowCount rule INSERT statement(s) to $outFile"
        $lblLastSaved.Text = "Saved: $outFile"
        Refresh-BackupList
    }
    $btnSave.Enabled = $true
})

$btnRefreshBackups.Add_Click({ Refresh-BackupList })

$btnRunBackup.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    if ($lstBackups.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one saved backup.", "Nothing selected", "OK", "Warning")
        return
    }

    $btnRunBackup.Enabled = $false
    foreach ($name in $lstBackups.SelectedItems) {
        $fullPath = Join-Path $backupDir $name
        Append-Log "---- Running backup $name ----"
        $env:PGPASSWORD = $txtPwd.Text
        $psqlArgs = @(
            "-h", $txtHost.Text,
            "-p", $txtPort.Text,
            "-U", $txtUser.Text,
            "-d", $txtDb.Text,
            "-v", "ON_ERROR_STOP=1",
            "-f", $fullPath
        )
        $proc = Start-Process -FilePath "psql" -ArgumentList $psqlArgs -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput "$env:TEMP\frm_psql_out.txt" `
                -RedirectStandardError "$env:TEMP\frm_psql_err.txt"
        $out = Get-Content "$env:TEMP\frm_psql_out.txt" -Raw -ErrorAction SilentlyContinue
        $err = Get-Content "$env:TEMP\frm_psql_err.txt" -Raw -ErrorAction SilentlyContinue
        if ($out) { Append-Log $out.Trim() }
        if ($err) { Append-Log $err.Trim() }
        if ($proc.ExitCode -ne 0) {
            Append-Log "*** FAILED: $name ***"
        } else {
            Append-Log "OK: $name"
        }
    }
    Append-Log "==== Done ===="
    $btnRunBackup.Enabled = $true
})

$btnRenameBackup.Add_Click({
    if ($lstBackups.SelectedItems.Count -ne 1) {
        [System.Windows.Forms.MessageBox]::Show("Select exactly one backup to rename.", "Rename", "OK", "Warning")
        return
    }

    $oldName = $lstBackups.SelectedItems[0]
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($oldName)

    $newBaseName = [Microsoft.VisualBasic.Interaction]::InputBox("New name for '$oldName' (no need to type .sql):", "Rename backup", $baseName)
    if ([string]::IsNullOrWhiteSpace($newBaseName)) {
        Append-Log "Rename cancelled."
        return
    }

    $newName = $newBaseName.Trim()
    if (-not $newName.ToLower().EndsWith(".sql")) { $newName = "$newName.sql" }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    if (($newName.ToCharArray() | Where-Object { $invalidChars -contains $_ }).Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("Name contains characters that aren't allowed in a file name.", "Invalid name", "OK", "Error")
        return
    }

    $oldPath = Join-Path $backupDir $oldName
    $newPath = Join-Path $backupDir $newName

    if ((Test-Path $newPath) -and ($newName -ne $oldName)) {
        [System.Windows.Forms.MessageBox]::Show("A backup named '$newName' already exists.", "Rename", "OK", "Warning")
        return
    }

    try {
        Rename-Item -Path $oldPath -NewName $newName -ErrorAction Stop
        Append-Log "Renamed: $oldName -> $newName"
    } catch {
        Append-Log "*** FAILED to rename $oldName : $($_.Exception.Message) ***"
    }
    Refresh-BackupList
})

$btnDeleteBackup.Add_Click({
    if ($lstBackups.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one saved backup to delete.", "Nothing selected", "OK", "Warning")
        return
    }

    $names = @($lstBackups.SelectedItems)
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Permanently delete these $($names.Count) backup file(s) from disk?`r`n`r`n" + ($names -join "`r`n"),
        "Confirm delete",
        "YesNo",
        "Warning")

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log "Delete cancelled."
        return
    }

    foreach ($name in $names) {
        $fullPath = Join-Path $backupDir $name
        try {
            Remove-Item -Path $fullPath -Force -ErrorAction Stop
            Append-Log "Deleted: $name"
        } catch {
            Append-Log "*** FAILED to delete $name : $($_.Exception.Message) ***"
        }
    }
    Refresh-BackupList
})

$btnTruncAlerts.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will TRUNCATE ... CASCADE on `"FRM_ALERTS`" only (FRM_RULE stays intact) in database '$($txtDb.Text)' - all alerts and alert evidence rows are permanently deleted. Continue?",
        "Confirm destructive reset",
        "YesNo",
        "Warning")

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log "Truncate FRM_ALERTS cancelled."
        return
    }

    $btnTruncAlerts.Enabled = $false
    [void](Run-SqlText 'TRUNCATE TABLE "FRM_ALERTS" CASCADE;' "TRUNCATE FRM_ALERTS CASCADE")
    $btnTruncAlerts.Enabled = $true
})

# Every table any of the 00-05 seed scripts insert into, plus the rule/alert tables
# themselves - the full set touched by this tool's test-data + alert-generation flow.
$allSeedTables = @(
    '"GENERAL_LEDGER"', '"ACCOUNT"', '"CUSTOMER_DETAILS"', '"ACCOUNT_CUSTOMER"',
    '"FRM_ALERT_HIERARCHY"', '"USER"', '"SECURITY_DETAILS"', '"STOCK"', '"SMA_LOG"',
    '"LOAN_ACCOUNT"', '"TRANSACTIONS"', '"FRM_RULE"', '"FRM_RULE_HISTORY"',
    '"FRM_ALERTS"', '"FRM_ALERT_GENERATED_FOR_DATA"'
)

$btnTruncAll.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    $tableListText = ($allSeedTables -join ", ")
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will TRUNCATE ... CASCADE on ALL of the following tables in database '$($txtDb.Text)':`r`n`r`n$tableListText`r`n`r`nEVERY row in each of these tables is permanently deleted - not just rows this tool added. Continue?",
        "Confirm FULL reset",
        "YesNo",
        "Warning")

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log "Full truncate cancelled."
        return
    }

    $btnTruncAll.Enabled = $false
    $sql = "TRUNCATE TABLE " + ($allSeedTables -join ", ") + " CASCADE;"
    [void](Run-SqlText $sql "TRUNCATE ALL rule/alert test data tables")
    $btnTruncAll.Enabled = $true
})

$btnAll.Add_Click({
    foreach ($row in $dgvRules.Rows) { $row.Cells["Select"].Value = $true }
})

$btnClear.Add_Click({
    foreach ($row in $dgvRules.Rows) { $row.Cells["Select"].Value = $false }
})

$btnClose.Add_Click({ $form.Close() })

$btnReset.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will TRUNCATE ... CASCADE on `"FRM_RULE`" and `"FRM_ALERTS`" in database '$($txtDb.Text)' - all rules, rule history, alerts, and alert evidence rows are permanently deleted. Continue?",
        "Confirm destructive reset",
        "YesNo",
        "Warning")

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log "Reset cancelled."
        return
    }

    $btnReset.Enabled = $false
    [void](Run-SqlText 'TRUNCATE TABLE "FRM_RULE", "FRM_ALERTS" CASCADE;' "TRUNCATE FRM_RULE, FRM_ALERTS CASCADE")
    $btnReset.Enabled = $true
})

$btnRun.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    $checkedIndexes = @()
    for ($i = 0; $i -lt $dgvRules.Rows.Count; $i++) {
        if ($dgvRules.Rows[$i].Cells["Select"].Value -eq $true) { $checkedIndexes += $i }
    }

    if ($checkedIndexes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one rule.", "Nothing selected", "OK", "Warning")
        return
    }

    $btnRun.Enabled = $false
    $txtLog.Clear()

    # Foundation (index 0) always runs first if anything is selected, even if not explicitly checked -
    # it's idempotent (ON CONFLICT DO NOTHING), so this just guarantees the FK targets exist.
    if ($checkedIndexes -notcontains 0) {
        Append-Log "(auto) running foundation first, since it's required by every rule"
        [void](Run-SqlFile $items[0].File)
    }

    foreach ($i in ($checkedIndexes | Sort-Object)) {
        $ok = Run-SqlFile $items[$i].File
        # Seed script always inserts the rule with status=1 (ACTIVE). If the Active checkbox for
        # this row is unchecked, flip it to INACTIVE (0) right after - covers both a fresh insert
        # and an already-existing row (ON CONFLICT DO NOTHING would've skipped the insert).
        if ($ok -and $items[$i].RuleId -and $dgvRules.Rows[$i].Cells["Active"].Value -eq $false) {
            [void](Run-SqlText "UPDATE `"FRM_RULE`" SET status = 0 WHERE id = $($items[$i].RuleId);" "set $($items[$i].Label) INACTIVE")
        }
    }

    Append-Log "==== Done ===="
    $btnRun.Enabled = $true
})

$btnUndo.Add_Click({
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("psql not found on PATH. Install PostgreSQL client tools or add psql.exe's folder to PATH.", "Missing psql", "OK", "Error")
        return
    }

    $checkedIndexes = @()
    for ($i = 0; $i -lt $dgvRules.Rows.Count; $i++) {
        if ($dgvRules.Rows[$i].Cells["Select"].Value -eq $true) { $checkedIndexes += $i }
    }

    if ($checkedIndexes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one rule to undo.", "Nothing selected", "OK", "Warning")
        return
    }

    $labelsText = ($checkedIndexes | Sort-Object -Descending | ForEach-Object { $items[$_].Label }) -join "`r`n"
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This deletes the alerts/evidence, the FRM_RULE row, and the seed data created for:`r`n`r`n$labelsText`r`n`r`n" +
        "Note: Inventory and Receivables share SECURITY_DETAILS/STOCK test rows (ids 31-33) - undoing one while the other's alerts still reference them will leave dangling evidence. Continue?",
        "Confirm undo",
        "YesNo",
        "Warning")

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log "Undo cancelled."
        return
    }

    $btnUndo.Enabled = $false
    $txtLog.Clear()

    # Reverse order (highest index first) so a rule's own alerts/evidence are gone before any
    # shared seed row underneath it is touched.
    foreach ($i in ($checkedIndexes | Sort-Object -Descending)) {
        [void](Run-SqlText $items[$i].UndoSql "UNDO $($items[$i].Label)")
    }

    Append-Log "==== Undo done ===="
    $btnUndo.Enabled = $true
})

Refresh-BackupList
[void]$form.ShowDialog()
