<#
Einfacher Netzwerk-Backup-Assistent (Robocopy)
Easy-Network-Backup-Assistant-Robocopy

Idee von: https://github.com/tekinteknoloji/Easy-Network-Backup-Assistant-Robocopy

Modifiziert und erweitert von Michael Mayer, Landau i.d.Pfalz, Germany
https://github.com/AirForceOneLD
#>


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Überprüfung der Administratorrechte ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# --- Hauptformular ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Einfacher Netzwerk-Backup-Assistent (Robocopy)'
$form.Size = New-Object System.Drawing.Size(650, 830) # Buton için boyutu biraz daha artırdık
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

# --- Schriftarten ---
$fontLabel = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$fontButton = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$fontInput = New-Object System.Drawing.Font('Segoe UI', 10)

# --- Warnbanner für Nicht-Administratoren ---
if (-not $isAdmin) {
    $lblAdminWarning = New-Object System.Windows.Forms.Label
    $lblAdminWarning.Text = '⚠️ WARNUNG: Du befindest dich im Standardbenutzermodus. Zum Hinzufügen einer geplanten Aufgabe sind Administratorrechte erforderlich!'
    $lblAdminWarning.Dock = [System.Windows.Forms.DockStyle]::Top
    $lblAdminWarning.Height = 30
    $lblAdminWarning.BackColor = [System.Drawing.Color]::MistyRose
    $lblAdminWarning.ForeColor = [System.Drawing.Color]::DarkRed
    $lblAdminWarning.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $lblAdminWarning.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($lblAdminWarning)
}

# ================== TOOLTIP (ERKLÄRUNGSSPRECHBLASEN) ==================
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 10000
$toolTip.InitialDelay = 500
$toolTip.ReshowDelay = 200
$toolTip.ShowAlways = $true

# --- Tab-Steuerung – Berechnung der Abstände ---
$yOffset = if (-not $isAdmin) {
    40
} else {
    10
}

# --- Tab Steuerung ---
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, $yOffset)
$tabControl.Size = New-Object System.Drawing.Size(610, 470)
$tabControl.Font = $fontLabel
$form.Controls.Add($tabControl)

# --- Registerkarten ---
$tab1 = New-Object System.Windows.Forms.TabPage
$tab1.Text = 'Grundeinstellungen'
$tab1.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$tabControl.Controls.Add($tab1)

$tab2 = New-Object System.Windows.Forms.TabPage
$tab2.Text = 'Erweiterte Optionen'
$tab2.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$tabControl.Controls.Add($tab2)

# ================== GRUNDEINSTELLUNGEN ==================
$lblQuelle = New-Object System.Windows.Forms.Label
$lblQuelle.Text = 'Zu kopierender Quellordner (PC):'
$lblQuelle.Location = New-Object System.Drawing.Point(20, 20)
$lblQuelle.Size = New-Object System.Drawing.Size(400, 25)
$lblQuelle.Font = $fontLabel
$tab1.Controls.Add($lblQuelle)

$txtQuelle = New-Object System.Windows.Forms.TextBox
$txtQuelle.Location = New-Object System.Drawing.Point(20, 45)
$txtQuelle.Size = New-Object System.Drawing.Size(370, 25)
$txtQuelle.Font = $fontInput
$tab1.Controls.Add($txtQuelle)

$btnQuelleSec = New-Object System.Windows.Forms.Button
$btnQuelleSec.Text = 'Wählen...'
$btnQuelleSec.Location = New-Object System.Drawing.Point(400, 44)
$btnQuelleSec.Size = New-Object System.Drawing.Size(80, 28)
$btnQuelleSec.Font = $fontButton
$btnQuelleSec.BackColor = [System.Drawing.Color]::LightGray
$btnQuelleSec.Add_Click({
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtQuelle.Text = $folderBrowser.SelectedPath
        }
    })
$tab1.Controls.Add($btnQuelleSec)
$toolTip.SetToolTip($btnQuelleSec, 'Wähle den Quellordner aus, den du sichern möchtest.')

$lblZiel = New-Object System.Windows.Forms.Label
$lblZiel.Text = 'Zu sichernder Zielordner (Netzwerk-/NAS-Laufwerk):'
$lblZiel.Location = New-Object System.Drawing.Point(20, 95)
$lblZiel.Size = New-Object System.Drawing.Size(400, 25)
$lblZiel.Font = $fontLabel
$tab1.Controls.Add($lblZiel)

$txtZiel = New-Object System.Windows.Forms.TextBox
$txtZiel.Location = New-Object System.Drawing.Point(20, 120)
$txtZiel.Size = New-Object System.Drawing.Size(370, 25)
$txtZiel.Font = $fontInput
$txtZiel.Text = '\\192.168.178.5\Software'
$tab1.Controls.Add($txtZiel)

$btnZielSec = New-Object System.Windows.Forms.Button
$btnZielSec.Text = 'Wählen...'
$btnZielSec.Location = New-Object System.Drawing.Point(400, 119)
$btnZielSec.Size = New-Object System.Drawing.Size(80, 28)
$btnZielSec.Font = $fontButton
$btnZielSec.BackColor = [System.Drawing.Color]::LightGray
$btnZielSec.Add_Click({
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtZiel.Text = $folderBrowser.SelectedPath
        }
    })
$tab1.Controls.Add($btnZielSec)
$toolTip.SetToolTip($btnZielSec, 'Wähle den Zielordner, in den die Sicherungskopien übertragen werden sollen, als lokalen oder Netzwerkpfad (UNC) aus.')

# Kopiermodus
$grpMod = New-Object System.Windows.Forms.GroupBox
$grpMod.Text = 'Kopiermodus'
$grpMod.Location = New-Object System.Drawing.Point(20, 170)
$grpMod.Size = New-Object System.Drawing.Size(570, 130)
$grpMod.Font = $fontLabel
$tab1.Controls.Add($grpMod)

$radioNone = New-Object System.Windows.Forms.RadioButton
$radioNone.Text = 'Nur Dateien im übergeordneten Ordner (Unterordner werden nicht kopiert)'
$radioNone.Location = New-Object System.Drawing.Point(15, 25)
$radioNone.Size = New-Object System.Drawing.Size(500, 20)
$radioNone.Font = $fontInput
$grpMod.Controls.Add($radioNone)
$toolTip.SetToolTip($radioNone, 'Es werden nur die Dateien im von deinem gewählten Hauptordner kopiert. Unterordner werden vollständig ignoriert.')

$radioS = New-Object System.Windows.Forms.RadioButton
$radioS.Text = 'Mit Unterordnern (außer leere Ordner) (/S)'
$radioS.Location = New-Object System.Drawing.Point(15, 50)
$radioS.Size = New-Object System.Drawing.Size(450, 20)
$radioS.Font = $fontInput
$grpMod.Controls.Add($radioS)
$toolTip.SetToolTip($radioS, '/S: Es kopiert Unterordner und die darin enthaltenen Dateien, erstellt jedoch keine vollständig leeren Ordner im Ziel.')

$radioE = New-Object System.Windows.Forms.RadioButton
$radioE.Text = 'mit Unterordnern, einschließlich leerer Ordner (/E)'
$radioE.Location = New-Object System.Drawing.Point(15, 75)
$radioE.Size = New-Object System.Drawing.Size(450, 20)
$radioE.Font = $fontInput
$radioE.Checked = $true
$grpMod.Controls.Add($radioE)
$toolTip.SetToolTip($radioE, '/E: Kopiert ganze Unterordner. Es erstellt die gesamte Ordnerstruktur exakt am Ziel, auch wenn dieses leer ist.')

$radioMIR = New-Object System.Windows.Forms.RadioButton
$radioMIR.Text = 'Spiegelmodus – löscht (/MIR), wenn im Ziel zusätzliche Dateien/Ordner vorhanden sind'
$radioMIR.Location = New-Object System.Drawing.Point(15, 100)
$radioMIR.Size = New-Object System.Drawing.Size(550, 20)
$radioMIR.Font = $fontInput
$grpMod.Controls.Add($radioMIR)
$toolTip.SetToolTip($radioMIR, '/MIR (Mirror): Es synchronisiert Quelle und Ziel exakt. Wenn eine in der Quelle gelöschte Datei im Ziel noch vorhanden ist, wird auch die Datei im Ziel gelöscht! Mit Vorsicht verwenden.')

# Weitere grundlegende Optionen
$chkZ = New-Object System.Windows.Forms.CheckBox
$chkZ.Text = 'Neustartmodus (/Z)'
$chkZ.Location = New-Object System.Drawing.Point(20, 315)
$chkZ.Size = New-Object System.Drawing.Size(230, 20)
$chkZ.Font = $fontInput
$chkZ.Checked = $true
$tab1.Controls.Add($chkZ)
$toolTip.SetToolTip($chkZ, '/Z: Wenn die Internetverbindung unterbrochen wird, wird der Kopiervorgang an der Stelle fortgesetzt, an der er unterbrochen wurde. Das ist bei großen Dateien eine echte Rettung.')

$chkB = New-Object System.Windows.Forms.CheckBox
$chkB.Text = 'Backup-Modus (/B)'
$chkB.Location = New-Object System.Drawing.Point(280, 315)
$chkB.Size = New-Object System.Drawing.Size(200, 20)
$chkB.Font = $fontInput
$tab1.Controls.Add($chkB)
$toolTip.SetToolTip($chkB, '/B: Durch die Arbeit mit Administratorrechten ermöglicht es das Kopieren von Dateien mit Zugriffsbeschränkungen, unabhängig von den Dateiberechtigungen (ACL).')

$chkNP = New-Object System.Windows.Forms.CheckBox
$chkNP.Text = 'Fortschrittsanzeige ausblenden (/NP)'
$chkNP.Location = New-Object System.Drawing.Point(20, 340)
$chkNP.Size = New-Object System.Drawing.Size(250, 20)
$chkNP.Font = $fontInput
#$chkNP.Checked = $true
$tab1.Controls.Add($chkNP)
$toolTip.SetToolTip($chkNP, '/NP: Verhindert, dass der Kopierfortschritt (%0... %100) kontinuierlich auf dem Konsolenbildschirm angezeigt wird. Dies wird empfohlen, um die Größe der Protokolldatei gering zu halten und die Geschwindigkeit zu erhöhen.')

$chkTBD = New-Object System.Windows.Forms.CheckBox
$chkTBD.Text = 'Warte, bis der Teilename definiert ist (/TBD)'
$chkTBD.Location = New-Object System.Drawing.Point(280, 340)
$chkTBD.Size = New-Object System.Drawing.Size(250, 20)
$chkTBD.Font = $fontInput
$chkTBD.Checked = $true
$tab1.Controls.Add($chkTBD)
$toolTip.SetToolTip($chkTBD, '/TBD (Zu definieren): Wenn der Netzwerkfreigabename noch nicht bereit ist, wartet das Programm geduldig, bis der Netzwerkpfad aktiviert ist, anstatt eine Fehlermeldung auszugeben und das Programm zu beenden.')

# Tagesprotokoll
$chkLog = New-Object System.Windows.Forms.CheckBox
$chkLog.Text = 'In Protokolldatei schreiben'
$chkLog.Location = New-Object System.Drawing.Point(20, 375)
$chkLog.Size = New-Object System.Drawing.Size(200, 20)
$chkLog.Font = $fontInput
$tab1.Controls.Add($chkLog)
$toolTip.SetToolTip($chkLog, 'Aktiviere diese Option, um die Ergebnisse, Details und Fehler des Kopiervorgangs in einer Textdatei (.log) zu speichern.')

$txtLogPath = New-Object System.Windows.Forms.TextBox
$txtLogPath.Location = New-Object System.Drawing.Point(20, 400)
$txtLogPath.Size = New-Object System.Drawing.Size(460, 28)
$txtLogPath.Font = $fontInput
$txtLogPath.Enabled = $false
$txtLogPath.Text = $PSScriptRoot
$tab1.Controls.Add($txtLogPath)

$btnLogSec = New-Object System.Windows.Forms.Button
$btnLogSec.Text = 'Wählen...'
$btnLogSec.Location = New-Object System.Drawing.Point(500, 399)
$btnLogSec.Size = New-Object System.Drawing.Size(80, 28)
$btnLogSec.Font = $fontButton
$btnLogSec.BackColor = [System.Drawing.Color]::LightGray
$btnLogSec.Enabled = $false
$btnLogSec.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.InitialDirectory = $txtLogPath.Text
        $saveDialog.Filter = 'Protokolldateien (*.log)|*.log|Alle Dateien (*.*)|*.*'
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtLogPath.Text = $saveDialog.FileName
        }
    })
$tab1.Controls.Add($btnLogSec)
$toolTip.SetToolTip($btnLogSec, 'Lege den Speicherort und den Dateinamen für die Protokolldatei (.log) fest.')

$chkLog.Add_CheckedChanged({
        $txtLogPath.Enabled = $chkLog.Checked
        $btnLogSec.Enabled = $chkLog.Checked
        Update-PreviewIfReady
    })

# ================== ERWEITERTE EINSTELLUNGEN ==================
$grpRetry = New-Object System.Windows.Forms.GroupBox
$grpRetry.Text = 'Einstellungen erneut ausprobieren'
$grpRetry.Location = New-Object System.Drawing.Point(20, 20)
$grpRetry.Size = New-Object System.Drawing.Size(570, 80)
$grpRetry.Font = $fontLabel
$tab2.Controls.Add($grpRetry)

$lblR = New-Object System.Windows.Forms.Label
$lblR.Text = 'Anzahl der Versuche (/R):'
$lblR.Location = New-Object System.Drawing.Point(15, 30)
$lblR.Size = New-Object System.Drawing.Size(130, 20)
$lblR.Font = $fontInput
$grpRetry.Controls.Add($lblR)

$numR = New-Object System.Windows.Forms.NumericUpDown
$numR.Location = New-Object System.Drawing.Point(150, 28)
$numR.Size = New-Object System.Drawing.Size(60, 25)
$numR.Font = $fontInput
$numR.Minimum = 0
$numR.Maximum = 100
$numR.Value = 5
$grpRetry.Controls.Add($numR)
$toolTip.SetToolTip($numR, '/R (Wiederholen): Gibt an, wie oft der Vorgang wiederholt wird, wenn eine Datei nicht kopiert werden kann. (Empfohlen: 5)')

$lblW = New-Object System.Windows.Forms.Label
$lblW.Text = 'Wartezeit (/W, sn):'
$lblW.Location = New-Object System.Drawing.Point(230, 30)
$lblW.Size = New-Object System.Drawing.Size(130, 20)
$lblW.Font = $fontInput
$grpRetry.Controls.Add($lblW)

$numW = New-Object System.Windows.Forms.NumericUpDown
$numW.Location = New-Object System.Drawing.Point(370, 28)
$numW.Size = New-Object System.Drawing.Size(60, 25)
$numW.Font = $fontInput
$numW.Minimum = 0
$numW.Maximum = 3600
$numW.Value = 5
$grpRetry.Controls.Add($numW)
$toolTip.SetToolTip($numW, '/W (Wait): Legt fest, wie viele Sekunden zwischen den Wiederholungsversuchen gewartet werden soll.')

# Multithreading
$grpMT = New-Object System.Windows.Forms.GroupBox
$grpMT.Text = 'Multithreading'
$grpMT.Location = New-Object System.Drawing.Point(20, 120)
$grpMT.Size = New-Object System.Drawing.Size(570, 60)
$grpMT.Font = $fontLabel
$tab2.Controls.Add($grpMT)

$chkMT = New-Object System.Windows.Forms.CheckBox
$chkMT.Text = '/MT verwenden'
$chkMT.Location = New-Object System.Drawing.Point(15, 22)
$chkMT.Size = New-Object System.Drawing.Size(120, 20)
$chkMT.Font = $fontInput
$grpMT.Controls.Add($chkMT)
$toolTip.SetToolTip($chkMT, '/MT (Multi-Threaded): Kopiert Dateien gleichzeitig unter Verwendung mehrerer Threads. Dies steigert insbesondere im Netzwerk die Geschwindigkeit erheblich.')

$numMT = New-Object System.Windows.Forms.NumericUpDown
$numMT.Location = New-Object System.Drawing.Point(150, 20)
$numMT.Size = New-Object System.Drawing.Size(60, 25)
$numMT.Font = $fontInput
$numMT.Minimum = 1
$numMT.Maximum = 128
$numMT.Value = 8
$numMT.Enabled = $false
$grpMT.Controls.Add($numMT)
$toolTip.SetToolTip($numMT, 'Anzahl der zu verwendenden parallelen Kanäle (zwischen 1 und 128). Sehr hohe Werte können das System überlasten; ideal sind 8 oder 16.')

$chkMT.Add_CheckedChanged({
        $numMT.Enabled = $chkMT.Checked
        Update-PreviewIfReady
    })

# Kopierflags
$grpCopyFlags = New-Object System.Windows.Forms.GroupBox
$grpCopyFlags.Text = 'Flags kopieren (/COPY)'
$grpCopyFlags.Location = New-Object System.Drawing.Point(20, 200)
$grpCopyFlags.Size = New-Object System.Drawing.Size(570, 110)
$grpCopyFlags.Font = $fontLabel
$tab2.Controls.Add($grpCopyFlags)

$chkD = New-Object System.Windows.Forms.CheckBox
$chkD.Text = 'Daten (D)'
$chkD.Location = New-Object System.Drawing.Point(15, 25)
$chkD.Size = New-Object System.Drawing.Size(90, 20)
$chkD.Font = $fontInput
$chkD.Checked = $true
$grpCopyFlags.Controls.Add($chkD)
$toolTip.SetToolTip($chkD, 'Kopiert den tatsächlichen Inhalt (Daten) der Datei. (Erforderlich)')

$chkA = New-Object System.Windows.Forms.CheckBox
$chkA.Text = 'Attribut (A)'
$chkA.Location = New-Object System.Drawing.Point(110, 25)
$chkA.Size = New-Object System.Drawing.Size(110, 20)
$chkA.Font = $fontInput
$chkA.Checked = $true
$grpCopyFlags.Controls.Add($chkA)
$toolTip.SetToolTip($chkA, 'Kopiert die Dateiattribute (nur lesbar, verborgen usw.).')

$chkT = New-Object System.Windows.Forms.CheckBox
$chkT.Text = 'Zeitstempel (T)'
$chkT.Location = New-Object System.Drawing.Point(225, 25)
$chkT.Size = New-Object System.Drawing.Size(130, 20)
$chkT.Font = $fontInput
$chkT.Checked = $true
$grpCopyFlags.Controls.Add($chkT)
$toolTip.SetToolTip($chkT, 'Die Erstellungs-, Änderungs- und letzten Zugriffsdaten bleiben unverändert erhalten.')

$chkS = New-Object System.Windows.Forms.CheckBox
$chkS.Text = 'Sicherheit (S)'
$chkS.Location = New-Object System.Drawing.Point(365, 25)
$chkS.Size = New-Object System.Drawing.Size(120, 20)
$chkS.Font = $fontInput
$grpCopyFlags.Controls.Add($chkS)
$toolTip.SetToolTip($chkS, 'Kopiert NTFS-Zugriffsberechtigungen (ACL – Access Control List).')

$chkO = New-Object System.Windows.Forms.CheckBox
$chkO.Text = 'Besitzer (O)'
$chkO.Location = New-Object System.Drawing.Point(15, 50)
$chkO.Size = New-Object System.Drawing.Size(110, 20)
$chkO.Font = $fontInput
$grpCopyFlags.Controls.Add($chkO)
$toolTip.SetToolTip($chkO, 'Kopiert die Datei unter Beibehaltung der Eigentümerangaben.')

$chkU = New-Object System.Windows.Forms.CheckBox
$chkU.Text = 'Kontrolle (U)'
$chkU.Location = New-Object System.Drawing.Point(125, 50)
$chkU.Size = New-Object System.Drawing.Size(100, 20)
$chkU.Font = $fontInput
$grpCopyFlags.Controls.Add($chkU)
$toolTip.SetToolTip($chkU, 'Kopiert die Daten zur Dateiprüfung (Auditing).')

$chkDCOPYT = New-Object System.Windows.Forms.CheckBox
$chkDCOPYT.Text = '/DCOPY:T (Zeitstempel der Ordner kopieren)'
$chkDCOPYT.Location = New-Object System.Drawing.Point(15, 78)
$chkDCOPYT.Size = New-Object System.Drawing.Size(300, 20)
$chkDCOPYT.Font = $fontInput
$chkDCOPYT.Checked = $true
$grpCopyFlags.Controls.Add($chkDCOPYT)
$toolTip.SetToolTip($chkDCOPYT, '/DCOPY:T: Die Erstellungs- und Änderungsdaten der kopierten Ordner bleiben ebenfalls erhalten.')

# Ausnahmen
$grpExclude = New-Object System.Windows.Forms.GroupBox
$grpExclude.Text = 'Ausnahmen'
$grpExclude.Location = New-Object System.Drawing.Point(20, 330)
$grpExclude.Size = New-Object System.Drawing.Size(570, 110)
$grpExclude.Font = $fontLabel
$tab2.Controls.Add($grpExclude)

$lblExcDir = New-Object System.Windows.Forms.Label
$lblExcDir.Text = 'Ausgeschl. Ordner (mit Leerzeichen trennen):'
$lblExcDir.Location = New-Object System.Drawing.Point(8, 25)
$lblExcDir.Size = New-Object System.Drawing.Size(280, 20)
$lblExcDir.Font = $fontInput
$grpExclude.Controls.Add($lblExcDir)

$txtExcludeDirs = New-Object System.Windows.Forms.TextBox
$txtExcludeDirs.Location = New-Object System.Drawing.Point(10, 45)
$txtExcludeDirs.Size = New-Object System.Drawing.Size(250, 25)
$txtExcludeDirs.Font = $fontInput
$grpExclude.Controls.Add($txtExcludeDirs)
$toolTip.SetToolTip($txtExcludeDirs, '/XD: Namen von Ordnern, die nicht gesichert werden sollen (z.B.: Temp Cache)')

$lblExcFile = New-Object System.Windows.Forms.Label
$lblExcFile.Text = 'Ausgeschl. Dateien (mit Leerzeichen trennen):'
$lblExcFile.Location = New-Object System.Drawing.Point(285, 25)
$lblExcFile.Size = New-Object System.Drawing.Size(280, 20)
$lblExcFile.Font = $fontInput
$grpExclude.Controls.Add($lblExcFile)

$txtExcludeFiles = New-Object System.Windows.Forms.TextBox
$txtExcludeFiles.Location = New-Object System.Drawing.Point(290, 45)
$txtExcludeFiles.Size = New-Object System.Drawing.Size(250, 25)
$txtExcludeFiles.Font = $fontInput
$grpExclude.Controls.Add($txtExcludeFiles)
$toolTip.SetToolTip($txtExcludeFiles, '/XF: Dateien oder Erweiterungen, die nicht gesichert werden sollen (z.B.: *.tmp *.lnk)')

# ================== Befehlsvorschau ==================
$lblCode = New-Object System.Windows.Forms.Label
$lblCode.Text = 'Erstellter Robocopy Befehl:'
$lblCode.Location = New-Object System.Drawing.Point(20, 520)
$lblCode.Size = New-Object System.Drawing.Size(570, 25)
$lblCode.Font = $fontLabel
$form.Controls.Add($lblCode)

$txtCodeAnalysis = New-Object System.Windows.Forms.TextBox
$txtCodeAnalysis.Multiline = $true
$txtCodeAnalysis.ReadOnly = $true
$txtCodeAnalysis.Location = New-Object System.Drawing.Point(20, 545)
$txtCodeAnalysis.Size = New-Object System.Drawing.Size(600, 80)
$txtCodeAnalysis.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$txtCodeAnalysis.BackColor = [System.Drawing.Color]::Black
$txtCodeAnalysis.ForeColor = [System.Drawing.Color]::LimeGreen
$txtCodeAnalysis.Text = 'Bitte wähle oben die Ordner aus...'
$form.Controls.Add($txtCodeAnalysis)

# ================== BACKUP SCHALTFLÄCHE ==================
$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = 'JETZT BACKUP STARTEN'
$btnBackup.Location = New-Object System.Drawing.Point(20, 645)
$btnBackup.Size = New-Object System.Drawing.Size(250, 45) # Boyutları yan yana butonlar için yarıya düşürdük
$btnBackup.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$btnBackup.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
$btnBackup.ForeColor = [System.Drawing.Color]::White
$btnBackup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBackup.Cursor = [System.Windows.Forms.Cursors]::Hand
$toolTip.SetToolTip($btnBackup, 'Startet das Backup')
$btnBackup.Add_Click({
        if (-not $txtQuelle.Text -or -not $txtZiel.Text) {
            [System.Windows.Forms.MessageBox]::Show('Bitte wähle sowohl den Quell- als auch den Zielordner aus!', 'Fehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $btnBackup.Enabled = $false
        $btnBackup.Text = 'Wird kopiert...'
        $btnBackup.BackColor = [System.Drawing.Color]::Orange

        $action = {
            param($cmdArgs)
            $argsOnly = $cmdArgs -replace '^robocopy\s+', ''
            Start-Process cmd.exe -ArgumentList "/c robocopy $argsOnly" -NoNewWindow -Wait
        }

        $robocopyCmd = Get-RobocopyArgs
        if ($robocopyCmd) {
            $ps = [PowerShell]::Create().AddScript($action).AddArgument($robocopyCmd)
            $asyncResult = $ps.BeginInvoke()

            while (-not $asyncResult.IsCompleted) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 100
            }

            try {
                $ps.EndInvoke($asyncResult)
                [System.Windows.Forms.MessageBox]::Show('Der Sicherungsvorgang wurde erfolgreich abgeschlossen!', 'Erfolgreich', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Es ist ein Fehler aufgetreten:`n$($_.Exception.Message)", 'Fehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            } finally {
                $ps.Dispose()
                $btnBackup.Enabled = $true
                $btnBackup.Text = 'JETZT BACKUP STARTEN'
                $btnBackup.BackColor = [System.Drawing.Color]::FromArgb(46, 204, 113)
            }
        }
    })
$form.Controls.Add($btnBackup)

# ================== Schaltfläche Aufgabe hinzufügen ==================
$btnAddTask = New-Object System.Windows.Forms.Button
$btnAddTask.Text = 'ZUM AUFGABENPLANER HINZUFÜGEN'
$btnAddTask.Location = New-Object System.Drawing.Point(368, 645)
$btnAddTask.Size = New-Object System.Drawing.Size(250, 45)
$btnAddTask.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$btnAddTask.BackColor = [System.Drawing.Color]::FromArgb(52, 152, 219)
$btnAddTask.ForeColor = [System.Drawing.Color]::White
$btnAddTask.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAddTask.Cursor = [System.Windows.Forms.Cursors]::Hand
$toolTip.SetToolTip($btnAddTask, 'Fügt den von dir angegebenen Robocopy-Befehl so in den Windows-Aufgabenplaner ein, dass er täglich automatisch ausgeführt wird.')

$btnAddTask.Add_Click({
        if (-not $isAdmin) {
            [System.Windows.Forms.MessageBox]::Show("Um eine geplante Aufgabe zu erstellen, muss dieses Skript im Modus 'Als Administrator ausführen' starten!", 'Berechtigungsfehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        if (-not $txtQuelle.Text -or -not $txtZiel.Text) {
            [System.Windows.Forms.MessageBox]::Show('Bitte lege vor dem Erstellen einer Aufgabe die Quell- und Zielpfade fest!', 'Fehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Fragen wir den Benutzer, zu welchen Zeiten er täglich arbeiten wird.
        $saatInput = [Microsoft.VisualBasic.Interaction]::InputBox('Um wie viel Uhr soll die Aufgabe jeden Tag ausgeführt werden? (z. B. 23:00 Uhr oder 03:30 Uhr)', 'Auftragszeit festlegen', '23:00')
        if (-not $saatInput) {
            return
        } # İBei Abbruch beenden.

        # Überprüfung des Zeitformats
        if (-not ($saatInput -match '^\d{2}:\d{2}$')) {
            [System.Windows.Forms.MessageBox]::Show('Ungültiges Zeitformat! Bitte geben Sie die Zeit im Format HH:MM ein. Beispiel: 23:00', 'Formatfehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        try {
            # Schritt 1: Vorbereiten des Ordners und der .bat-Datei
            $folderPath = "$PSScriptRoot\BAT"
            if (-not (Test-Path $folderPath)) {
                New-Item -ItemType Directory -Force -Path $folderPath | Out-Null
            }

            # Einen eindeutigen Task- und Dateinamen generieren (um Verwechslungen zwischen Quelle und Ziel zu vermeiden).
            $cleanQuelle = ($txtQuelle.Text -replace '[^a-zA-Z0-9]', '_').Trim('_')
            $batFileName = "Reserveaufgabe_$cleanQuelle.bat"
            $batFullRoad = Join-Path $folderPath $batFileName
            $JobTitle = "Auto_Parts_$cleanQuelle"

            # Robocopy-Code in eine .bat-Datei schreiben unter Verwendung der UTF-8- (ohne BOM) oder der Standard-ANSI-Codierung.
            $robocopyCmd = Get-RobocopyArgs
            $batContent = "@echo off`r`necho Sicherung gestartet: %date% %time%`r`n$robocopyCmd`r`necho Sicherung abgeschlossen: %date% %time%"
            [System.IO.File]::WriteAllText($batFullRoad, $batContent, [System.Text.Encoding]::Default)

            # Schritt 2: Hinzufügen einer Aufgabe zum Windows-Taskplaner
            $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$batFullRoad`""
            $trigger = New-ScheduledTaskTrigger -Daily -At $saatInput
            $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

            # Falls bereits eine Aufgabe existiert, löschen wir sie zunächst, um einen Konflikt zu vermeiden.
            if (Get-ScheduledTask -TaskName $JobTitle -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $JobTitle -Confirm:$false | Out-Null
            }

            # Aufgabe speichern
            Register-ScheduledTask -TaskName $JobTitle -Action $action -Trigger $trigger -Principal $principal | Out-Null

            [System.Windows.Forms.MessageBox]::Show("Geplante Aufgabe erfolgreich erstellt!`n`nAufgabenname: $JobTitle`nErinnerung: Jeden Tag um $saatInput Uhr`nAuszuführende Datei: $batFullRoad`n`nDer Dienst läuft auf Systemebene (SYSTEM) im Hintergrund, ohne dass dies bemerkt wird.", 'Aufgabe hinzugefügt', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Beim Hinzufügen der Aufgabe ist ein Fehler aufgetreten:`n$($_.Exception.Message)", 'Fehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
$form.Controls.Add($btnAddTask)


# Add a modern Exit Button
$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = 'Beenden'
$exitBtn.Location = New-Object System.Drawing.Point(20, 730)
$exitBtn.Size = New-Object System.Drawing.Size(250, 45)
$exitBtn.BackColor = 'Red' #[System.Drawing.Color]::FromArgb(0, 123, 255) # Blue color
$exitBtn.ForeColor = 'White' #[System.Drawing.Color]::White
$exitBtn.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$exitBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$exitBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$toolTip.SetToolTip($exitBtn, 'Beendet die Anwendung')
$form.Controls.Add($exitBtn)
$exitBtn.Add_Click({
        $form.Close()
        $form.Dispose()
    })


# Label Aktuelles Datum und Zeit
$timelabel = New-Object System.Windows.Forms.Label
$timelabel.AutoSize = $true
$timelabel.Location = New-Object System.Drawing.Point(368, 740)
$timelabel.BackColor = 'Yellow'
$timelabel.ForeColor = 'Black'
$timelabel.Font = New-Object System.Drawing.Font('Segoe UI', 14)
$form.Controls.Add($timelabel)

# Timer inialisieren
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000 # Aktualisierung jede Sekunde
$timer.Add_Tick({
        $timelabel.Text = Get-Date -Format 'dddd, dd.MM.yyyy HH:mm:ss'
    })
# Timer Starten
$timer.Start()


# ================== FUNKTION, DIE DEN ROBOKOPY-BEFEHL ERSTELLT ==================
function Get-RobocopyArgs {
    $source = $txtQuelle.Text.Trim().Trim('"')
    $dest = $txtZiel.Text.Trim().Trim('"')
    if (-not $source -or -not $dest) {
        return ''
    }

    $argsList = @()
    $argsList += "`"$source`""
    $argsList += "`"$dest`""

    if ($radioE.Checked) {
        $argsList += '/E'
    } elseif ($radioS.Checked) {
        $argsList += '/S'
    } elseif ($radioMIR.Checked) {
        $argsList += '/MIR'
    }

    if ($chkZ.Checked) {
        $argsList += '/Z'
    }
    if ($chkB.Checked) {
        $argsList += '/B'
    }
    if ($chkNP.Checked) {
        $argsList += '/NP'
    }
    if ($chkTBD.Checked) {
        $argsList += '/TBD'
    }

    $argsList += "/R:$($numR.Value)"
    $argsList += "/W:$($numW.Value)"

    if ($chkMT.Checked) {
        $argsList += "/MT:$($numMT.Value)"
    }

    $copyFlags = ''
    if ($chkD.Checked) {
        $copyFlags += 'D'
    }
    if ($chkA.Checked) {
        $copyFlags += 'A'
    }
    if ($chkT.Checked) {
        $copyFlags += 'T'
    }
    if ($chkS.Checked) {
        $copyFlags += 'S'
    }
    if ($chkO.Checked) {
        $copyFlags += 'O'
    }
    if ($chkU.Checked) {
        $copyFlags += 'U'
    }
    if ($copyFlags -ne '') {
        $argsList += "/COPY:$copyFlags"
    }

    if ($chkDCOPYT.Checked) {
        $argsList += '/DCOPY:T'
    }

    if ($chkLog.Checked -and $txtLogPath.Text.Trim() -ne '') {
        $logPath = $txtLogPath.Text.Trim().Trim('"')
        $argsList += "/LOG:`"$logPath`""
    }

    $excludeDirs = $txtExcludeDirs.Text.Trim()
    if ($excludeDirs) {
        $dirs = $excludeDirs -split '\s+' | ForEach-Object { $_.Trim('"').Trim() }
        foreach ($d in $dirs) {
            if ($d) {
                $argsList += "/XD `"$d`""
            }
        }
    }
    $excludeFiles = $txtExcludeFiles.Text.Trim()
    if ($excludeFiles) {
        $files = $excludeFiles -split '\s+' | ForEach-Object { $_.Trim('"').Trim() }
        foreach ($f in $files) {
            if ($f) {
                $argsList += "/XF `"$f`""
            }
        }
    }

    return 'robocopy ' + ($argsList -join ' ')
}

function Update-PreviewIfReady {
    if ($null -ne $txtCodeAnalysis) {
        $cmd = Get-RobocopyArgs
        if ($cmd) {
            $txtCodeAnalysis.Text = $cmd
        } else {
            $txtCodeAnalysis.Text = 'Bitte wähle den Quell- und den Zielordner aus.'
        }
    }
}

# ================== LINKS ZU DEN EREIGNISSEN ==================
$txtQuelle.Add_TextChanged({ Update-PreviewIfReady })
$txtZiel.Add_TextChanged({ Update-PreviewIfReady })
$txtLogPath.Add_TextChanged({ Update-PreviewIfReady })
$txtExcludeDirs.Add_TextChanged({ Update-PreviewIfReady })
$txtExcludeFiles.Add_TextChanged({ Update-PreviewIfReady })

$radioNone, $radioS, $radioE, $radioMIR | ForEach-Object {
    $_.Add_CheckedChanged({ Update-PreviewIfReady })
}
$chkZ, $chkB, $chkNP, $chkTBD, $chkD, $chkA, $chkT, $chkS, $chkO, $chkU, $chkDCOPYT, $chkMT | ForEach-Object {
    $_.Add_CheckedChanged({ Update-PreviewIfReady })
}
$numR, $numW, $numMT | ForEach-Object {
    $_.Add_ValueChanged({ Update-PreviewIfReady })
}

$form.Add_Shown({
        Update-PreviewIfReady
    })

try {
    $form.ShowDialog() | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show("Skriptfehler: $($_.Exception.Message)", 'Kritischer Fehler', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)

}




# SIG # Begin signature block
# MIIGqwYJKoZIhvcNAQcCoIIGnDCCBpgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUmVLoisZ9sBsGR5hkPZvyPTT2
# G5ugggRDMIIEPzCCAiegAwIBAgIQE+RTnONk7ZdJzvz0auYGQzANBgkqhkiG9w0B
# AQ0FADAdMRswGQYDVQQDDBJQb3dlclNoZWxsIFJvb3QgQ0EwIBcNMjMwMzMwMTQ0
# OTMxWhgPMjA2MzAzMzAxNDU5MjZaMC8xLTArBgNVBAMMJE1pY2hhZWwgTWF5ZXIg
# KFBvd2Vyc2hlbGwgRGV2ZWxvcGVyKTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBALaag3wQJUviV4+SNvSBFv3EMu22cMSNxjdyVRRL3Y9s7g73ZoVc7Iwk
# bPkQqgr5HUaBOVWLA00wIEewS5LPqVl1zo2lkCQCz9ZgbTAbGJB/CI3h4N+xixYv
# AMpJ8VWlCJ6y7T9xY66b2xSsfoGZyjxWs/D/w5XCHcyheXPG/WoGLV5x/Ne0umTl
# Kgm02sRCWmO3OfUUK6m/jWoQKOCRMTij8ARQ4WYnoaTZSnh6son7Uexfx7RvSzIs
# lZmY+9Fev6jDmVEtDRGOnyzRmJ59yWlcxUS5K7VJXNIIgM6EceyRGMx2fGWCcQAB
# uUHEIH0eDSBqBNyqPvg7771yiMe3tX0CAwEAAaNnMGUwDgYDVR0PAQH/BAQDAgeA
# MBMGA1UdJQQMMAoGCCsGAQUFBwMDMB8GA1UdIwQYMBaAFIYSf6MflVuEn8+pkozG
# BgYpy7tmMB0GA1UdDgQWBBSxUU1kuybSN37fV+31KbyPUZ7KQjANBgkqhkiG9w0B
# AQ0FAAOCAgEAo+ApQ7zSu0N4oL4QdYbR7pDph4Iq7uJ1+FjqvRdHYTBg5gHDZbU5
# d4F/WJtgFhOsC/FGYIAY9B20J1seuoN0rKcqcLLiKPYTWGQGgiWSjfnax/+/Kc+X
# oH1awy8DRbJc1+BrRI5ft6X7rVZeB9RMkxUz19qai0s3ZUlN63K7qjSUW7AtcSGN
# 6acrwRch8BDW/fxKeJb0FUWv7mQRustneXGwjX8evJYTnCaVeKsn333KD2sO9Frb
# hyiJxpos3+CrqCEqeMKNa+YlosCwphfYPWUCne6BTCParSVdZR5ZqatEE54yj1JA
# o2tqEClLwGMk4vWzj7WaVCERgb6QNKnxsWvP65hrjukJwWHR4imvfHSwbEJBLlCJ
# h0gc6jJKNF/EZWwM3TxVA6d37FtBpSIQZBYlAgwR4ucPPb2JQBrViFzKRZAJ0i5A
# rTBaOL9DpKizBdTvt6a2yJTHrDyqhjsw+VjLFq9GoBIE4wsTqYY8tbUBdZyBwdrz
# YZqnSX1M6kEjEBOsABJWi0BJiY1fKhYdUDPg1FfGtXtz1ZC7rTbRYcgCjC+WzRvW
# 8TtKh/9/gCHd+1AZtxDAcuI5fb39W2N5gHpJQz9GMMRgxIvoTmB3nS+P+ZulDvY3
# VW9D8et+WMtpcwgT3if4C59xiuTXPq3+mOWJwTuCGVA+vgtXMZEmk6MxggHSMIIB
# zgIBATAxMB0xGzAZBgNVBAMMElBvd2VyU2hlbGwgUm9vdCBDQQIQE+RTnONk7ZdJ
# zvz0auYGQzAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUnpeQUsIFBJXYGHsT1FvHGMjz+xgwDQYJ
# KoZIhvcNAQEBBQAEggEAd/aeIKuEmyNc612VAliDCPwOpwyFzOo5kGfgSrqwzQAu
# P8l7STHSRDMazDN0RyzlCrsowmmt8aiUX3plb9q+HhabCgjMQlZ9fdasDt8U8R/6
# OkO6akDvscCTCZXfZAOJlTTFeI/hhG7PSbsO+HX4PKjJhUfNj+/JhTrIjzEFRHjx
# ZouRQAzLud28KRbnGxGkLHPJQ+cb5D8vD+3NxYw/ICkxKdKr1BXFo6u6wG/hwuza
# ZgO9S+k/pf0V7vcrVmFd9Dc1FOUC8+jv1fCNtG5FwXhGJSwCyD7v1T+1tUe2/bAb
# VSopFqU0va0jqLLKXW/QiDtbSrNmH7/N1mFQeYKR+w==
# SIG # End signature block
# pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJ
# pMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aa
# dMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXD
# j/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB
# 4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ
# 33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amy
# HeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC
# 0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823I
# DzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYD
# VR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcN
# AQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxpp
# VCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6
# mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPH
# h6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCN
# NWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg6
# 2fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwgga0MIIEnKADAgECAhANx6xXBf8h
# mS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0z
# ODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGP
# NRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1I
# pYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5A
# vftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDRe
# b6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBUR
# Jg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/ao
# fEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQ
# skBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJ
# lIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev
# +7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6B
# aaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IB
# XTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQ
# VvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEE
# AjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9
# vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwb
# SI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTL
# xLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD
# 8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVk
# o43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRa
# Ps+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8
# cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRz
# W6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KC
# LPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau
# 1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPS
# xyZsq8WhbaM2tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0
# aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1w
# aW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2
# MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAg
# UmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# ANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdw
# bHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9
# RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrU
# cCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iU
# SROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw
# 2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe4
# 6YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seA
# O+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSH
# lq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6
# EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDch
# Ic2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAM
# BgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNV
# HSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUF
# BzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6
# Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFt
# cGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5o
# dHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3Rh
# bXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwB
# BAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezR
# CESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0
# k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFO
# tj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLW
# U0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2n
# HkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIF
# eRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqR
# hoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7
# roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47Cdx
# VRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/r
# ptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL
# 6vdCvHlshtjdNXOCIUjsarfNZzGCBPwwggT4AgEBMDEwHTEbMBkGA1UEAwwSUG93
# ZXJTaGVsbCBSb290IENBAhAT5FOc42Ttl0nO/PRq5gZDMAkGBSsOAwIaBQCgeDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEW
# BBSel5BSwgUEldgYexPUW8cYyPP7GDANBgkqhkiG9w0BAQEFAASCAQB39p4gq4Sb
# I1zrXZUCWIMI/A6nDIXM6jmQZ+BKurDNAC4/yXtJMdJEMxrMM3RHLOUKuyjCaa3x
# qJRfemVv2r4eFpsKCMxCVn191qwO3xTxH/o6Q7pqQO+xwJMJld9kA4mVNMV4j+GE
# bs9Juw74dfg8qMmFR82P78mFOsiPMQVEePFmi5FADMu53bwpFucbEaQsc8lD5xvk
# Py8P7c3FjD8gKTEp0qvUFcWjq7rAb+HC7NpmA71L6T+l/RXu9ytWYV30NzUU5QLz
# 6O/V8I20bkXBeEYlLALIPu/VP7W1R7b9sBtVKikWpTS9rSOosspdb9CIO1tKs2Yf
# v83WYVB5gpH7oYIDJjCCAyIGCSqGSIb3DQEJBjGCAxMwggMPAgEBMH0waTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdp
# Q2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1
# IENBMQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3
# DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI2MDcxNzEyMzAwOVow
# LwYJKoZIhvcNAQkEMSIEINO9vBjbGepg9TKsBDklrFbT6R7OoPTBDEAeuliJqHzx
# MA0GCSqGSIb3DQEBAQUABIICACXdSXgzxV8I98zygB0PVEIcYO15xpjXuvkG0NJA
# kbeVkydpTPi+2zs8Tme5jYVaxU9tgKwet5nYgAlJIQm4SiSsHPyacB8Tmy2oAmZM
# 8tRVOnKsOhozbftYD/JZDfXQ4cdUJ79lIeDDLsTj7Zmn32poAHbyl09+iXt8am7O
# XhI0CqR7augrDout5All2b9yJL4CTTxKXNvWwl6DtjRrKiBRfd3SqwifGMDFtoX5
# eGljNJrr9FsRX6iOs5qGT38Puj28PK+IHN+r/BjJjnkw0pysZg2bXVuExXoHABMy
# 5plwY1xo0/duH++Lrpu/LbtQswZL/a1OSIBqVOE9wbZlNdgqR1NMpGnQMugMkiVE
# 00LZr2HhyEhUfs5bycPDBofEPcJ9C9pBQoq7/B/4bxuZXrSp8JBWXCbHWMss4HJo
# GL5fXj6p1hM26XjyOs/7khRr0TqGfBtxjhIIq5Y/kMEQIAMecH6pgdLR068BVrtW
# mlH1IE1WN8Lo5XMdQfq92KuPEZY9g332TzQmX+rsjcMGUy2VJkw9TxbBUJwLJulT
# k4oLwTn9UHbtQ77uDdVayDzoAt3UQuBz62OHvih9hJNByVKF2vYydwADDi7uYojy
# 5JTd9HVQEZzjhCybykogCDHb97vD3l35uHbqbg/jtNkhE5TqO7BQuL+uPmJNDFaZ
# J10e
# SIG # End signature block
