# LootPanel — внешняя панель «Выгодный хабар» поверх S.T.A.L.K.E.R. 2.
# Читает inventory_dump.json (пишет мод LootHelper) и показывает:
#   • НА ВЫБРОС — худшие по ₽/кг (что выкинуть при перегрузе с минимальной потерей денег)
#   • ТОП — лучшие по ₽/кг (что нести/продавать в первую очередь)
# Глобальные клавиши (работают, когда фокус в игре):
#   Ctrl+F9  — автосвайп: курсор сам пробегает по сетке инвентаря (запись F8 должна быть ВКЛ)
#   Ctrl+F10 — калибровка: центр ЛЕВОЙ-ВЕРХНЕЙ ячейки сетки
#   Ctrl+F11 — калибровка: центр ПРАВОЙ-НИЖНЕЙ ячейки сетки
# Требование: игра в режиме «оконный без границ» (borderless), иначе панель не видна.
# Запуск: start-panel.bat (или powershell -STA -ExecutionPolicy Bypass -File LootPanel.ps1)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ============ Пути и конфиг ============
$DumpPath   = 'D:\Games\STALKER2\Stalker2\Binaries\Win64\ue4ss\Mods\LootHelper\inventory_dump.json'
$ConfigPath = Join-Path $PSScriptRoot 'panel-config.json'

$Config = [pscustomobject]@{
    cols = 8; rows = 10          # размер видимой сетки инвентаря (ячейки)
    tlX = 0; tlY = 0             # центр левой-верхней ячейки (F10)
    brX = 0; brY = 0             # центр правой-нижней ячейки (F11)
    delayMs = 120                # пауза курсора на ячейке при свайпе
    winX = 40; winY = 40         # позиция панели
    hideGear = $true             # не предлагать выкидывать оружие/броню
}
if (Test-Path $ConfigPath) {
    try {
        $loaded = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $loaded.PSObject.Properties) {
            if ($null -ne $Config.PSObject.Properties[$p.Name]) { $Config.($p.Name) = $p.Value }
        }
    } catch {}
}
function Save-Config {
    try { $Config | ConvertTo-Json | Out-File $ConfigPath -Encoding utf8 } catch {}
}

# ============ Win32: курсор, окно игры, глобальные хоткеи ============
Add-Type -Namespace Native -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out System.Drawing.Point p);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
[DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
'@ -ReferencedAssemblies System.Drawing

function Get-GameWindow {
    $p = Get-Process 'Stalker2-Win64-Shipping' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $p -and $p.MainWindowHandle -ne 0) { return $p.MainWindowHandle }
    return [IntPtr]::Zero
}

# ============ Данные ============
$script:Items = @()
$script:DumpTime = '—'

function Read-Dump {
    if (-not (Test-Path $DumpPath)) { $script:Items = @(); return }
    try {
        $json = Get-Content $DumpPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $list = @()
        foreach ($it in $json.items) {
            $w = [double]$it.weight
            $dens = if ($w -gt 0) { [double]$it.price / $w } else { [double]::PositiveInfinity }
            $isGear = $false
            if ($null -ne $it.PSObject.Properties['gear']) { $isGear = [bool]$it.gear }
            $list += [pscustomobject]@{
                name = [string]$it.name; price = [double]$it.price; weight = $w
                qty = [int]$it.qty; gear = $isGear; dens = $dens
                totW = $w * [int]$it.qty; totV = [double]$it.price * [int]$it.qty
            }
        }
        $script:Items = $list
        $script:DumpTime = (Get-Item $DumpPath).LastWriteTime.ToString('HH:mm:ss')
    } catch { }
}

function Fmt([double]$n) {
    if ([double]::IsInfinity($n)) { return '∞' }
    if ($n -ge 100) { return [string][math]::Round($n) }
    return ('{0:0.#}' -f $n)
}

function Build-Text {
    $mode = $script:Mode
    $lines = New-Object System.Collections.Generic.List[string]
    $pool = $script:Items
    if ($pool.Count -eq 0) {
        $lines.Add('Дампа пока нет.')
        $lines.Add('В игре: I -> F8 -> Ctrl+F9 -> F8')
        return ($lines -join "`n")
    }
    if ($mode -eq 'drop') {
        $cand = @($pool | Where-Object { -not ($Config.hideGear -and $_.gear) } | Sort-Object dens)
        $lines.Add('=== НА ВЫБРОС (хуже ₽/кг — выше) ===')
        $i = 0
        foreach ($it in $cand) {
            $i++; if ($i -gt 10) { break }
            $q = ''; if ($it.qty -gt 1) { $q = ' x' + $it.qty }
            $lines.Add(('{0,2}. {1,-28} {2,6} ₽/кг  −{3:0.##} кг  −₽{4:0}' -f $i, ($it.name + $q), (Fmt $it.dens), $it.totW, $it.totV))
        }
        $n = [math]::Min(5, $cand.Count)
        if ($n -gt 0) {
            $top = @($cand | Select-Object -First $n)
            $sw = ($top | Measure-Object totW -Sum).Sum
            $sv = ($top | Measure-Object totV -Sum).Sum
            $lines.Add(('— выкинь первые {0} -> освободишь {1:0.##} кг, потеряешь ₽{2:0}' -f $n, $sw, $sv))
        }
    } else {
        $cand = @($pool | Sort-Object dens -Descending)
        $lines.Add('=== ТОП по ₽/кг (нести/продавать) ===')
        $i = 0
        foreach ($it in $cand) {
            $i++; if ($i -gt 10) { break }
            $q = ''; if ($it.qty -gt 1) { $q = ' x' + $it.qty }
            $lines.Add(('{0,2}. {1,-28} {2,6} ₽/кг' -f $i, ($it.name + $q), (Fmt $it.dens)))
        }
        $tw = ($pool | Measure-Object totW -Sum).Sum
        $tv = ($pool | Measure-Object totV -Sum).Sum
        $lines.Add(('— всего: {0} поз · ₽{1:0} · {2:0.#} кг' -f $pool.Count, $tv, $tw))
    }
    return ($lines -join "`n")
}

# ============ Автосвайп ============
function Invoke-Sweep {
    if ($Config.tlX -eq 0 -and $Config.tlY -eq 0) { $script:StatusExtra = 'нет калибровки: Ctrl+F10/F11'; Update-View; return }
    if ($Config.brX -le $Config.tlX) { $script:StatusExtra = 'калибровка кривая: Ctrl+F10/F11 заново'; Update-View; return }
    $hwnd = Get-GameWindow
    if ($hwnd -ne [IntPtr]::Zero) { [Native.Win32]::SetForegroundWindow($hwnd) | Out-Null; Start-Sleep -Milliseconds 200 }
    $cols = [math]::Max(1, [int]$Config.cols); $rows = [math]::Max(1, [int]$Config.rows)
    $dx = 0; $dy = 0
    if ($cols -gt 1) { $dx = ($Config.brX - $Config.tlX) / ($cols - 1) }
    if ($rows -gt 1) { $dy = ($Config.brY - $Config.tlY) / ($rows - 1) }
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $x = [int]($Config.tlX + $c * $dx); $y = [int]($Config.tlY + $r * $dy)
            [Native.Win32]::SetCursorPos($x, $y) | Out-Null
            Start-Sleep -Milliseconds ([int]$Config.delayMs)
        }
    }
    $script:StatusExtra = 'свайп готов'
    Update-View
}

# ============ Окно ============
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Выгодный хабар" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="True"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize">
  <Border CornerRadius="8" Background="#E61A1C14" BorderBrush="#66D9C784" BorderThickness="1" Padding="10">
    <StackPanel>
      <DockPanel Margin="0,0,0,6">
        <TextBlock Name="Title" Text="☢ ВЫГОДНЫЙ ХАБАР" Foreground="#D9C784" FontFamily="Consolas" FontSize="14" FontWeight="Bold"/>
        <TextBlock Name="BtnClose" Text=" ✕ " Foreground="#888" FontFamily="Consolas" FontSize="14" HorizontalAlignment="Right" Cursor="Hand" DockPanel.Dock="Right"/>
        <TextBlock Name="BtnMode" Text=" [выброс] " Foreground="#A8B47A" FontFamily="Consolas" FontSize="13" HorizontalAlignment="Right" DockPanel.Dock="Right" Cursor="Hand"/>
      </DockPanel>
      <TextBlock Name="Body" Foreground="#CFCBB8" FontFamily="Consolas" FontSize="13" Text="..." />
      <CheckBox Name="ChkGear" Foreground="#8F9A6C" FontFamily="Consolas" FontSize="12" Margin="0,7,0,0" Content="не предлагать выкидывать оружие/броню"/>
      <TextBlock Name="Status" Foreground="#6E7758" FontFamily="Consolas" FontSize="11" Margin="0,6,0,0" Text=""/>
    </StackPanel>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$Body   = $Window.FindName('Body')
$Status = $Window.FindName('Status')
$BtnMode = $Window.FindName('BtnMode')
$BtnClose = $Window.FindName('BtnClose')
$ChkGear = $Window.FindName('ChkGear')

$Window.Left = [double]$Config.winX
$Window.Top  = [double]$Config.winY
$ChkGear.IsChecked = [bool]$Config.hideGear
$script:Mode = 'drop'
$script:StatusExtra = ''

function Update-View {
    Read-Dump
    $Body.Text = Build-Text
    $cal = 'нет калибровки (Ctrl+F10/F11!)'
    if ($Config.tlX -ne 0 -or $Config.tlY -ne 0) { $cal = 'калибровка ок' }
    $extra = ''
    if ($script:StatusExtra -ne '') { $extra = ' · ' + $script:StatusExtra }
    $Status.Text = ('дамп: {0} · {1} · Ctrl+F9 свайп{2}' -f $script:DumpTime, $cal, $extra)
    if ($script:Mode -eq 'drop') { $BtnMode.Text = ' [выброс] ' } else { $BtnMode.Text = ' [топ] ' }
}

$Window.Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })
$BtnClose.Add_MouseLeftButtonDown({ $Window.Close() })
$BtnMode.Add_MouseLeftButtonDown({
    if ($script:Mode -eq 'drop') { $script:Mode = 'top' } else { $script:Mode = 'drop' }
    Update-View
})
$ChkGear.Add_Click({
    $Config.hideGear = [bool]$ChkGear.IsChecked
    Save-Config
    Update-View
})

# Пересчёт при изменении дампа: следим за временем файла раз в секунду.
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$script:LastWrite = ''
$timer.Add_Tick({
    $t = ''
    if (Test-Path $DumpPath) { $t = (Get-Item $DumpPath).LastWriteTime.Ticks.ToString() }
    if ($t -ne $script:LastWrite) {
        $script:LastWrite = $t
        Update-View
    }
})
$timer.Start()

# Глобальные хоткеи: Ctrl+F9 свайп, F10/F11 калибровка.
$Window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
    $script:Hwnd = $helper.Handle
    [Native.Win32]::RegisterHotKey($script:Hwnd, 1, 2, 0x78) | Out-Null # Ctrl+F9
    [Native.Win32]::RegisterHotKey($script:Hwnd, 2, 2, 0x79) | Out-Null # Ctrl+F10
    [Native.Win32]::RegisterHotKey($script:Hwnd, 3, 2, 0x7A) | Out-Null # Ctrl+F11
    $source = [System.Windows.Interop.HwndSource]::FromHwnd($script:Hwnd)
    $source.AddHook({
        param($hwnd, $msg, $wParam, $lParam, $handled)
        if ($msg -eq 0x0312) { # WM_HOTKEY
            switch ([int]$wParam) {
                1 { Invoke-Sweep }
                2 {
                    $p = New-Object System.Drawing.Point
                    [Native.Win32]::GetCursorPos([ref]$p) | Out-Null
                    $Config.tlX = $p.X; $Config.tlY = $p.Y
                    Save-Config
                    $script:StatusExtra = ('ЛВ-ячейка: {0},{1}' -f $p.X, $p.Y)
                    Update-View
                }
                3 {
                    $p = New-Object System.Drawing.Point
                    [Native.Win32]::GetCursorPos([ref]$p) | Out-Null
                    $Config.brX = $p.X; $Config.brY = $p.Y
                    Save-Config
                    $script:StatusExtra = ('ПН-ячейка: {0},{1}' -f $p.X, $p.Y)
                    Update-View
                }
            }
        }
        return [IntPtr]::Zero
    })
})

$Window.Add_Closing({
    $Config.winX = [int]$Window.Left
    $Config.winY = [int]$Window.Top
    Save-Config
    if ($script:Hwnd) {
        [Native.Win32]::UnregisterHotKey($script:Hwnd, 1) | Out-Null
        [Native.Win32]::UnregisterHotKey($script:Hwnd, 2) | Out-Null
        [Native.Win32]::UnregisterHotKey($script:Hwnd, 3) | Out-Null
    }
})

Update-View
$null = $Window.ShowDialog()
