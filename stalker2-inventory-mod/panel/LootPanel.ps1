# LootPanel — внешняя панель «Выгодный хабар» поверх S.T.A.L.K.E.R. 2.
# Читает inventory_dump.json (пишет мод LootHelper) и показывает:
#   • НА ВЫБРОС — худшие по ₽/кг (что выкинуть при перегрузе с минимальной потерей денег)
#   • ТОП — лучшие по ₽/кг (что нести/продавать в первую очередь)
# Глобальные клавиши (работают, когда фокус в игре):
#   F11      — ПОЛНЫЙ авто-прогон: сам включает запись (F9), листает весь инвентарь, выключает
#   F10      — автосвайп по УЖЕ включённой записи (ручной режим F9→F10→F9, для сравнения предметов)
#   Ctrl+F10 — калибровка: центр ЛЕВОЙ-ВЕРХНЕЙ ячейки сетки
#   Ctrl+F11 — калибровка: центр ПРАВОЙ-НИЖНЕЙ ячейки сетки
# Требование: игра в режиме «оконный без границ» (borderless), иначе панель не видна.
# Запуск: start-panel.bat (или powershell -STA -ExecutionPolicy Bypass -File LootPanel.ps1)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ============ Пути и конфиг ============
$DumpPath   = 'D:\Games\STALKER2\Stalker2\Binaries\Win64\ue4ss\Mods\LootHelper\inventory_dump.json'
$RecFlag    = 'D:\Games\STALKER2\Stalker2\Binaries\Win64\ue4ss\Mods\LootHelper\recording.flag'
$ConfigPath = Join-Path $PSScriptRoot 'panel-config.json'

$Config = [pscustomobject]@{
    cols = 8; rows = 10          # размер видимой сетки инвентаря (ячейки)
    tlX = 0; tlY = 0             # центр левой-верхней ячейки (F10)
    brX = 0; brY = 0             # центр правой-нижней ячейки (F11)
    delayMs = 120                # пауза курсора на ячейке при свайпе
    scrollClicks = 12            # на сколько «кликов» колеса листать вниз между проходами
    maxPasses = 25               # предохранитель: макс. число проходов по сетке
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
[DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, IntPtr dwExtraInfo);
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);
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
        $lines.Add('В игре: I -> F9 -> F10 -> F9')
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

# ============ Автосвайп (многостраничный, с авто-остановкой) ============
$MOUSEEVENTF_WHEEL = 0x0800
$WHEEL_DELTA = 120

# Свежий ли флаг записи (мод пишет его при F9): свайп без записи бессмыслен.
function Test-Recording {
    if (-not (Test-Path $RecFlag)) { return $false }
    return ((Get-Date) - (Get-Item $RecFlag).LastWriteTime).TotalSeconds -lt 5
}

# Число предметов в дампе (для детекции «новых не появилось → дно»).
# -1 = файл читается в момент записи (нестрашно, просто пропустим сравнение).
function Get-DumpItemCount {
    if (-not (Test-Path $DumpPath)) { return 0 }
    try { return @((Get-Content $DumpPath -Raw -Encoding UTF8 | ConvertFrom-Json).items).Count }
    catch { return -1 }
}

# Колесо мыши: clicks>0 — вверх, clicks<0 — вниз. Курсор должен быть над сеткой.
function Send-Wheel([int]$clicks) {
    [Native.Win32]::mouse_event($MOUSEEVENTF_WHEEL, 0, 0, $WHEEL_DELTA * $clicks, [IntPtr]::Zero)
}

$VK_F9 = 0x78

# Синтетическое нажатие клавиши в активное окно (F11 шлёт F9 моду вместо тебя).
function Send-Key([byte]$vk) {
    [Native.Win32]::keybd_event($vk, 0, 0, [IntPtr]::Zero)       # down
    Start-Sleep -Milliseconds 40
    [Native.Win32]::keybd_event($vk, 0, 2, [IntPtr]::Zero)       # up (KEYEVENTF_KEYUP)
}

# Ждём, пока запись перейдёт в нужное состояние ($want = $true/$false).
function Wait-Rec([bool]$want, [int]$tries = 20) {
    for ($i = 0; $i -lt $tries; $i++) {
        Start-Sleep -Milliseconds 100
        if ((Test-Recording) -eq $want) { return $true }
    }
    return $false
}

# Один проход курсором по видимой сетке (наводит тултип на каждую ячейку).
function Step-SweepGrid {
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
}

# Калибровка выставлена? (иначе некуда водить курсор).
function Test-Calibrated {
    if ($Config.tlX -eq 0 -and $Config.tlY -eq 0) { $script:StatusExtra = 'нет калибровки: Ctrl+F10/F11'; Update-View; return $false }
    if ($Config.brX -le $Config.tlX) { $script:StatusExtra = 'калибровка кривая: Ctrl+F10/F11 заново'; Update-View; return $false }
    return $true
}

# Ядро автосвайпа: скролл в верх → проходы по сетке с листанием вниз → авто-стоп.
# Предполагает, что запись УЖЕ включена и игра в фокусе. Используется и F10, и F11.
function Run-PagedSweep {
    $hwnd = Get-GameWindow
    if ($hwnd -ne [IntPtr]::Zero) { [Native.Win32]::SetForegroundWindow($hwnd) | Out-Null; Start-Sleep -Milliseconds 200 }

    # Центр сетки — точка, над которой крутим колесо.
    $gx = [int](($Config.tlX + $Config.brX) / 2)
    $gy = [int](($Config.tlY + $Config.brY) / 2)

    # 1) Прокрутка в самый верх (с запасом — лишние клики вверх безвредны).
    [Native.Win32]::SetCursorPos($gx, $gy) | Out-Null
    for ($i = 0; $i -lt 30; $i++) { Send-Wheel 1; Start-Sleep -Milliseconds 12 }
    Start-Sleep -Milliseconds 200

    # 2) Проход → прокрутка вниз → проход, пока появляются новые предметы.
    #    Перекрытие рядов безвредно (мод дедуплицирует); стоп, когда новых нет.
    $prev = -1
    $pass = 0
    $maxPasses = [math]::Max(1, [int]$Config.maxPasses)
    while ($pass -lt $maxPasses) {
        $pass++
        Step-SweepGrid
        Start-Sleep -Milliseconds 350           # дать моду дописать последний тултип
        $count = Get-DumpItemCount
        $script:StatusExtra = "проход $pass · предметов: $count"
        Update-View
        if ($count -ge 0) {
            if ($count -eq $prev) { break }     # ничего нового → уперлись в дно
            $prev = $count
        }
        # Листаем вниз на следующую «страницу» (внахлёст).
        [Native.Win32]::SetCursorPos($gx, $gy) | Out-Null
        for ($i = 0; $i -lt [math]::Max(1, [int]$Config.scrollClicks); $i++) { Send-Wheel -1; Start-Sleep -Milliseconds 12 }
        Start-Sleep -Milliseconds 200
    }
    return $prev
}

# F10 — свайп по УЖЕ включённой записи (ручной режим: F9 вкл → F10 → F9 выкл).
function Invoke-Sweep {
    if (-not (Test-Calibrated)) { return }
    if (-not (Test-Recording)) { $script:StatusExtra = 'включи запись сначала: F9'; Update-View; return }
    $n = Run-PagedSweep
    $script:StatusExtra = "свайп готов, предметов $n"
    Update-View
}

# F11 — полный авто-прогон: сам жмёт F9 (старт с чистого листа) → свайп → F9 (стоп).
# F9 слушает мод, поэтому шлём игре синтетическое нажатие. Всегда даёт свежий снимок.
function Invoke-FullAuto {
    if (-not (Test-Calibrated)) { return }
    $hwnd = Get-GameWindow
    if ($hwnd -eq [IntPtr]::Zero) { $script:StatusExtra = 'игра не найдена — она запущена?'; Update-View; return }
    [Native.Win32]::SetForegroundWindow($hwnd) | Out-Null; Start-Sleep -Milliseconds 250

    # Была запись? Останавливаем, чтобы следующий старт дал чистый снимок.
    if (Test-Recording) {
        Send-Key $VK_F9
        if (-not (Wait-Rec $false)) { $script:StatusExtra = 'не смог остановить прошлую запись (F9?)'; Update-View; return }
    }
    # Старт (мод очистит список).
    $script:StatusExtra = 'авто: включаю запись…'; Update-View
    Send-Key $VK_F9
    if (-not (Wait-Rec $true)) { $script:StatusExtra = 'запись не включилась — F9 занят в игре? (перебинди quickload)'; Update-View; return }

    $n = Run-PagedSweep

    # Стоп.
    $hwnd = Get-GameWindow
    if ($hwnd -ne [IntPtr]::Zero) { [Native.Win32]::SetForegroundWindow($hwnd) | Out-Null; Start-Sleep -Milliseconds 150 }
    Send-Key $VK_F9
    Wait-Rec $false 10 | Out-Null
    $script:StatusExtra = "авто-прогон готов, предметов $n"
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
        <TextBlock Name="RecDot" Text="○ rec" Foreground="#555" FontFamily="Consolas" FontSize="13" FontWeight="Bold" HorizontalAlignment="Right" DockPanel.Dock="Right" Margin="0,0,6,0"/>
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
$RecDot = $Window.FindName('RecDot')
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
    $Status.Text = ('дамп: {0} · {1} · F11 авто / F10 свайп{2}' -f $script:DumpTime, $cal, $extra)
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
    # REC-индикатор: флаг свежее 5 секунд = запись идёт (мигаем как камкордер).
    $rec = $false
    if (Test-Path $RecFlag) {
        $age = (Get-Date) - (Get-Item $RecFlag).LastWriteTime
        if ($age.TotalSeconds -lt 5) { $rec = $true }
    }
    $script:Blink = -not $script:Blink
    if ($rec) {
        $RecDot.Text = '[#] REC'
        if ($script:Blink) { $RecDot.Foreground = '#FF5040' } else { $RecDot.Foreground = '#7A2A22' }
    } else {
        $RecDot.Text = '[ ] rec'
        $RecDot.Foreground = '#555555'
    }
})
$timer.Start()

# Глобальные хоткеи: F10 свайп, F10/F11 калибровка.
$Window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
    $script:Hwnd = $helper.Handle
    [Native.Win32]::RegisterHotKey($script:Hwnd, 1, 0, 0x79) | Out-Null # F10 (свайп по включённой записи)
    [Native.Win32]::RegisterHotKey($script:Hwnd, 2, 2, 0x79) | Out-Null # Ctrl+F10 (калибровка ЛВ)
    [Native.Win32]::RegisterHotKey($script:Hwnd, 3, 2, 0x7A) | Out-Null # Ctrl+F11 (калибровка ПН)
    [Native.Win32]::RegisterHotKey($script:Hwnd, 4, 0, 0x7A) | Out-Null # F11 (полный авто-прогон)
    $source = [System.Windows.Interop.HwndSource]::FromHwnd($script:Hwnd)
    $source.AddHook({
        param($hwnd, $msg, $wParam, $lParam, $handled)
        if ($msg -eq 0x0312) { # WM_HOTKEY
            switch ([int]$wParam) {
                1 { Invoke-Sweep }
                4 { Invoke-FullAuto }
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
        [Native.Win32]::UnregisterHotKey($script:Hwnd, 4) | Out-Null
    }
})

Update-View
$null = $Window.ShowDialog()
