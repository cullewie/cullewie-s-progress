# cullewie's progress: the window. It starts the setup (Launcher.ps1 -Ui) as a hidden process and follows its run log
# (C:\ProgramData\Cullewie\Logs: current.txt, steps.log, NN-<step>.log). It never runs a setup step itself.
#   (no switch)          mode screen: All-in, Xbox & Store, Only Store Mode, Vanilla Mode
#   -Resume              logon task after the safe-mode restart: runs Launcher -ResumeFullSetup -Ui and follows it
#   -SafeScript <path>   safe mode: runs the safe-mode script FIRST, then shows its progress (a window that fails to
#                        open can never keep the PC in safe mode)
#   -Done                one-time logon task after the last restart: the "Hazır" screen with Digital Vibrance
#   -Snapshot <folder>   renders the three screens to PNG files and closes (tests)
#   -Auto                starts All-in without the mode screen (IWR.ps1: CULLEWIE_AUTO=all-in)
#   -Vanilla             starts Vanilla Mode without the mode screen (IWR.ps1: CULLEWIE_MODE=vanilla)
# After the last restart -Done first runs the extra setup another tool left (Launcher -AfterSetup), if there is one.
#   -Continue            logon task after a Windows Update restart: starts the full setup again in the saved mode
param([switch]$Resume, [string]$SafeScript = '', [switch]$Done, [string]$Snapshot = '', [switch]$Auto, [switch]$Vanilla, [switch]$Continue)

$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$work = Join-Path $env:ProgramData 'Cullewie\Work'
$statusPath = Join-Path $work 'ui-status.txt'
$doneTask = 'cullewie-done'

# safe mode: the script that leaves safe mode runs before anything else in this file
$script:Worker = $null
if ($SafeScript) {
    $safeArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$SafeScript`"")
    $script:Worker = Start-Process -FilePath $ps -ArgumentList $safeArgs -WindowStyle Hidden -PassThru
}

# ---------- run log ----------
function ConvertTo-StepFileName([string]$Step) { $Step -creplace '[^A-Za-z0-9-]', '-' }
# reads a file another process still writes (the transcript of the running step)
function Read-Shared([string]$Path) {
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        try { (New-Object IO.StreamReader($fs, $true)).ReadToEnd() } finally { $fs.Close() }
    }
    catch { '' }
}
function Read-Tail([string]$Path, [int]$Max = 400) {
    $lines = @((Read-Shared $Path) -split "`r?`n")
    ($lines | Select-Object -Last $Max) -join "`r`n"
}
# the run in progress: its folder, its steps.log lines, the step running now (file name form), and ui-status.txt
function Get-RunState([string]$Root, [string]$StatusPath) {
    $state = [pscustomobject]@{ Run = $null; Lines = @(); Running = ''; RunningLog = ''; Status = '' }
    if ($StatusPath -and (Test-Path -LiteralPath $StatusPath)) { $state.Status = (Read-Shared $StatusPath).Trim() }
    $pointer = Join-Path $Root 'current.txt'
    if (-not (Test-Path -LiteralPath $pointer)) { return $state }
    $run = (Read-Shared $pointer).Trim()
    if (-not $run -or -not (Test-Path -LiteralPath $run)) { return $state }
    $state.Run = $run
    $state.Lines = @((Read-Shared (Join-Path $run 'steps.log')) -split "`r?`n" | Where-Object { $_ -match "`t" })
    $files = @(Get-ChildItem -LiteralPath $run -Filter '??-*.log' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count) {
        $last = $files[-1]
        $name = $last.BaseName.Substring(3)
        $started = @($files | Where-Object { $_.BaseName.Substring(3) -eq $name }).Count
        $finished = @($state.Lines | Where-Object { (ConvertTo-StepFileName (($_ -split "`t")[1])) -eq $name }).Count
        if ($started -gt $finished) { $state.Running = $name }
        $state.RunningLog = $last.FullName
    }
    $state
}
# the steps a mode goes through, in order: Key = the step name in steps.log, Label = what the window shows
function Get-ExpectedSteps([string]$Mode, [string]$Apps, [string]$Gpu, [switch]$After) {
    if ($Mode -eq 'vanilla') { return @([pscustomobject]@{ Key = 'Back to Windows defaults (vanilla)'; Label = 'Windows varsayılanlarına dönüş' }) }
    $list = [ordered]@{}
    $list['Windows Update'] = 'Windows güncellemeleri'
    if ($Gpu) { $list['DDU (driver cleanup)'] = 'Hazırlık: sürücü temizliği' }
    $list['Defender Optimize'] = 'Hazırlık: Defender'
    $list['Restart (safe mode)'] = 'Yeniden başlatma (güvenli mod)'
    if ($Gpu) { $list['DDU'] = 'DDU: eski sürücü temizliği' }
    $list['Defender (safe mode)'] = 'Defender (güvenli mod)'
    $list['Restart (after safe mode)'] = 'Yeniden başlatma'
    $list['Internet'] = 'İnternet bağlantısı'
    if ($Gpu -eq 'nvidia') { $list['NVIDIA Driver'] = 'NVIDIA sürücüsü'; $list['NVIDIA Settings (profile, P0, refresh rate)'] = 'NVIDIA ayarları' }
    elseif ($Gpu -eq 'amd') { $list['AMD Driver'] = 'AMD sürücüsü'; $list['AMD Settings (Adrenalin, refresh rate)'] = 'AMD ayarları' }
    else { $list['Highest Refresh Rate'] = 'En yüksek yenileme hızı' }
    $list['Power Plan On'] = 'Güç planı'
    $list['Timer Resolution On'] = 'Timer Resolution'
    $list['Windows Tweaks (apps, widgets, Copilot, settings)'] = 'Windows ayarları'
    if ($Apps -in 'store', 'xbox') { $list['Microsoft Store / Xbox apps'] = 'Store / Xbox uygulamaları' }
    $list['Display: full-screen scaling and vibrance'] = 'Tam ekran ölçekleme'
    $list['Services Off'] = 'Hizmetler'
    $list['Restart (final)'] = 'Son yeniden başlatma'
    # an extra setup script runs after the last restart; its own rows (##step lines) follow this one
    if ($After) { $list['Extra setup'] = 'Ek kurulum' }
    foreach ($k in $list.Keys) { [pscustomobject]@{ Key = $k; Label = $list[$k] } }
}
# one row per expected step (Wait / Run / Pass / Fail), then every other step the log names
function Get-StepRows([object[]]$Expected, [string[]]$Lines, [string]$Running) {
    $results = [ordered]@{}
    foreach ($l in $Lines) {
        $f = $l -split "`t"
        if ($f.Count -lt 3 -or $f[1] -in 'start', 'resume') { continue }
        $results[$f[1]] = if ($f[2] -eq 'FAIL') { 'Fail' } else { 'Pass' }
    }
    foreach ($e in $Expected) {
        $state = if ($results.Contains($e.Key)) { $results[$e.Key] } elseif ($Running -and (ConvertTo-StepFileName $e.Key) -eq $Running) { 'Run' } else { 'Wait' }
        [pscustomobject]@{ Label = $e.Label; State = $state; Key = $e.Key }
    }
    $known = @($Expected | ForEach-Object Key)
    $extraLabels = @{ 'Restart (updates)' = 'Yeniden başlatma (güncellemeler)'; 'Services Off (after the apps)' = 'Hizmetler (uygulamalardan sonra)' }
    foreach ($k in $results.Keys) { if ($known -notcontains $k) { [pscustomobject]@{ Label = $(if ($extraLabels.ContainsKey($k)) { $extraLabels[$k] } else { $k }); State = $results[$k]; Key = $k } } }
}
# the Launcher's messages are English (the console keeps them); the window shows the known ones in Turkish
function ConvertTo-TurkishStatus([string]$Text) {
    if ($Text -match 'waiting for a restart') { return 'Windows, güncellemeleri bitirmek için yeniden başlatma bekliyor. Bilgisayarı bir kez normal şekilde yeniden başlat, sonra kurulumu yeniden çalıştır.' }
    if ($Text -match 'No internet connection') { return 'İnternet bağlantısı yok (5 dakika beklendi). Bağlantıyı kontrol edip kurulumu yeniden çalıştır.' }
    if ($Text -match 'safe boot') { return 'Güvenli mod açılamadı, kurulum durdu. Hiçbir şey değiştirilmedi.' }
    if ($Text -match 'NVIDIA model name') { return 'Ekran kartının modeli kaydedilemedi, kurulum durdu.' }
    if ($Text -match '^DDU did not complete') { return 'DDU sürücü temizliğini bitiremedi; NVIDIA kurulumu durduruldu.' }
    if ($Text -match '^(.+) did not complete\. Full setup stopped') {
        $name = $Matches[1]
        $label = @(Get-ExpectedSteps 'full' 'xbox' 'nvidia') + @(Get-ExpectedSteps 'full' 'off' 'amd') + @(Get-ExpectedSteps 'vanilla' 'off' '') |
            Where-Object Key -eq $name | Select-Object -First 1 -ExpandProperty Label
        return "'$(if ($label) { $label } else { $name })' adımı tamamlanamadı, kurulum durdu. Ayrıntılar kayıtta."
    }
    $Text
}
# ---------- brand (optional) ----------
# Another tool that starts this toolkit may leave C:\ProgramData\Cullewie\Work\brand.json (a folder only administrators
# write): a title, a font, and a logo made of SVG path shapes on a square viewBox; the sizes follow Get-BrandLayout. Only data, never code. Anything
# missing or invalid means no brand: the window keeps its own look.
function Read-Brand([string]$Path) {
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $conv = New-Object Windows.Media.BrushConverter
        $title = [string]$j.title; $font = [string]$j.font
        if (-not $title -or $title.Length -gt 60 -or -not $font -or $font.Length -gt 60) { return $null }
        $weight = if ($j.fontWeight) { [string]$j.fontWeight } else { 'SemiBold' }
        if (-not [Windows.FontWeights].GetProperty($weight)) { return $null }
        $view = if ($j.viewBox) { [double]$j.viewBox } else { 96 }
        if ($view -le 0) { return $null }
        $iconBg = [string]$j.iconBackground
        [void]$conv.ConvertFrom($iconBg)
        $parts = @(foreach ($p in @($j.logo)) {
            [void][Windows.Media.Geometry]::Parse([string]$p.path)
            if ([string]$p.fill -ne 'background') { [void]$conv.ConvertFrom([string]$p.fill) }
            [pscustomobject]@{ Path = [string]$p.path; Fill = [string]$p.fill }
        })
        if ($parts.Count -lt 1 -or $parts.Count -gt 10) { return $null }
        [pscustomobject]@{ Title = $title; Font = $font; FontWeight = $weight; ViewBox = $view; IconBackground = $iconBg; Logo = $parts }
    }
    catch { $null }
}
# where the brand goes in a title bar $BarHeight high: its logo in a rounded square like the taskbar icon, then its title.
# One ratio, the golden ratio phi, from the bar down:
#  square   = bar / phi, centred in the bar (the same margin on every side); corner radius = square * 96/512 and the logo
#             at 3/4 of the square with a 1/8 margin (the favicon proportions)
#  caps     = square / phi; font size = caps / the font's own CapsHeight; the cap band (cap tops to baseline) centred
#  gap      = bar / phi^3 between the square and the title
function Get-BrandLayout($Brand, [double]$BarHeight) {
    $phi = (1 + [math]::Sqrt(5)) / 2
    $tile = $BarHeight / $phi
    $margin = ($BarHeight - $tile) / 2
    $capHeight = $tile / $phi
    $weight = [Windows.FontWeights].GetProperty($Brand.FontWeight).GetValue($null)
    $face = New-Object Windows.Media.Typeface((New-Object Windows.Media.FontFamily $Brand.Font), [Windows.FontStyles]::Normal, $weight, [Windows.FontStretches]::Normal)
    $glyphs = $null
    if (-not $face.TryGetGlyphTypeface([ref]$glyphs)) { throw "Font not installed: $($Brand.Font)" }
    [pscustomobject]@{ Tile = $tile; TileLeft = $margin; TileTop = $margin; Radius = $tile * 96 / 512
                       Scale = $tile * 0.75 / $Brand.ViewBox; LogoLeft = $margin + $tile / 8; LogoTop = $margin + $tile / 8
                       CapHeight = $capHeight; FontSize = $capHeight / $glyphs.CapsHeight; Weight = $weight
                       BaselineY = $BarHeight / 2 + $capHeight / 2; TextLeft = $margin + $tile + $BarHeight / [math]::Pow($phi, 3) }
}function Get-Gpu {
    try {
        $ids = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [string]$_.PNPDeviceID })
        if ($ids -match 'VEN_10DE') { return 'nvidia' }
        if ($ids -match 'VEN_1002') { return 'amd' }
    }
    catch { }
    ''
}

# ---------- window ----------
try {
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
# its own taskbar button, not one grouped under PowerShell (set before the window exists)
try {
    Add-Type -Namespace Cullewie -Name Shell -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);'
    [void][Cullewie.Shell]::SetCurrentProcessExplicitAppUserModelID('Cullewie.Progress')
}
catch { }

$xaml = @'
<!-- Every size is the golden ratio phi: the window is 940 x 940/phi; spacing and corners come from 46/phi^n (46, 28.43, 17.57, 10.86, 6.71, 4.15, 2.56); font sizes from cap heights in sqrt(phi) steps (31.93, 25.1, 19.73, 15.51, 12.2); the progress columns split 1 : phi. -->
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="cullewie's progress" Width="940" Height="580.95" WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanMinimize" Background="#2F3337"
        FontFamily="Segoe UI" Foreground="#F2F2F2" SnapsToDevicePixels="True">
  <Window.Resources>
    <Style x:Key="Yellow" TargetType="Button">
      <Setter Property="Foreground" Value="#1E1E1E"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#F5C400" CornerRadius="6.71" Padding="28.43,10.86">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#FFD633"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="#D9AD00"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Background" Value="#4A4F54"/>
                <Setter Property="Foreground" Value="#8C9399"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Flat" TargetType="Button">
      <Setter Property="Foreground" Value="#A9B0B6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" Padding="10.86,6.71">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#3A3F44"/>
                <Setter Property="Foreground" Value="#F2F2F2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Card" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="GroupName" Value="mode"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="#3A3F44" BorderBrush="#3A3F44" BorderThickness="2" CornerRadius="10.86" Padding="17.57,17.57" Margin="6.71">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#7A6A1E"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#F5C400"/>
                <Setter TargetName="b" Property="Background" Value="#41464B"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="FillPart" TargetType="RepeatButton">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Border Background="Transparent"><Border Height="4" CornerRadius="2.56" Background="{TemplateBinding Background}"/></Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="YSlider" TargetType="Slider">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Track x:Name="PART_Track" Height="24">
              <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Style="{StaticResource FillPart}" Background="#F5C400"/></Track.DecreaseRepeatButton>
              <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Style="{StaticResource FillPart}" Background="#4A4F54"/></Track.IncreaseRepeatButton>
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Ellipse Width="18" Height="18" Fill="#F5C400" Stroke="#1E1E1E" StrokeThickness="2"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border Background="#4A4F54" CornerRadius="2.56" Margin="2.56"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Vertical"><Setter Property="Width" Value="10"/></Trigger>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Height" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track">
                  <Track.Thumb>
                    <Thumb>
                      <Thumb.Template>
                        <ControlTemplate TargetType="Thumb"><Border Background="#4A4F54" CornerRadius="2.56" Margin="2.56"/></ControlTemplate>
                      </Thumb.Template>
                    </Thumb>
                  </Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="19"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
    <Style x:Key="CardText" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="#B4BBC1"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="LineHeight" Value="19"/>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#24272A" BorderThickness="1">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="46"/>
      <RowDefinition/>
    </Grid.RowDefinitions>

    <Border x:Name="TitleBar" Background="#272A2E">
      <Grid>
      <DockPanel LastChildFill="False">
        <StackPanel x:Name="TitleLeft" Orientation="Horizontal" VerticalAlignment="Center" Margin="17.57,0,0,0" DockPanel.Dock="Left">
          <Border x:Name="TitleMark" Width="12" Height="12" CornerRadius="2.56" Background="#F5C400" Margin="0,0,10.86,0"/>
          <TextBlock x:Name="TitleText" Text="cullewie's progress" FontSize="15.51" FontWeight="SemiBold"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
          <Button x:Name="MinBtn" Style="{StaticResource Flat}" Content="—" Width="46"/>
          <Button x:Name="CloseBtn" Style="{StaticResource Flat}" Content="✕" Width="46"/>
        </StackPanel>
      </DockPanel>
      <!-- a brand (brand.json) is drawn here instead of TitleLeft, at computed positions -->
      <Canvas x:Name="BrandCanvas" IsHitTestVisible="False" Visibility="Collapsed"/>
      </Grid>
    </Border>

    <!-- screen 1: mode -->
    <Grid x:Name="ModeScreen" Grid.Row="1" Margin="28.43,17.57,28.43,28.43">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Margin="6.71,0,6.71,10.86">
        <TextBlock Text="Kurulum türünü seç" FontSize="25.1" FontWeight="SemiBold"/>
        <TextBlock Text="Windows 11'i oyun için hazırlar. Birini seç ve Başlat'a bas; gerisi kendiliğinden ilerler." FontSize="15.51" Foreground="#A9B0B6" Margin="0,4.15,0,0"/>
      </StackPanel>
      <UniformGrid Grid.Row="1" Rows="2" Columns="2">
        <RadioButton x:Name="ModeAllIn" Style="{StaticResource Card}" IsChecked="True">
          <StackPanel>
            <TextBlock Text="All-in" Style="{StaticResource CardTitle}"/>
            <TextBlock Style="{StaticResource CardText}" Text="Sürücüyü DDU ile temizleyip en güncel NVIDIA / AMD sürücüsünü kurar, ekranı ve Windows'u oyun için ayarlar. Microsoft Store ve winget kaldırılır. Windows Update ve Xbox çalışmaz."/>
          </StackPanel>
        </RadioButton>
        <RadioButton x:Name="ModeXbox" Style="{StaticResource Card}">
          <StackPanel>
            <TextBlock Text="Xbox &amp; Store" Style="{StaticResource CardTitle}"/>
            <TextBlock Style="{StaticResource CardText}" Text="All-in ile aynı; Microsoft Store, Xbox uygulaması ve Game Pass çalışmaya devam eder. Windows Update yalnızca güvenlik güncellemelerini alır."/>
          </StackPanel>
        </RadioButton>
        <RadioButton x:Name="ModeStore" Style="{StaticResource Card}">
          <StackPanel>
            <TextBlock Text="Only Store Mode" Style="{StaticResource CardTitle}"/>
            <TextBlock Style="{StaticResource CardText}" Text="All-in ile aynı; yalnızca Microsoft Store çalışmaya devam eder. Xbox kapalı kalır."/>
          </StackPanel>
        </RadioButton>
        <RadioButton x:Name="ModeVanilla" Style="{StaticResource Card}">
          <StackPanel>
            <TextBlock Text="Vanilla Mode" Style="{StaticResource CardTitle}"/>
            <TextBlock Style="{StaticResource CardText}" Text="Yapılan Windows değişikliklerini geri alır: hizmetler, ayarlar, görünüm ve kaldırılan uygulamalar. Ekran kartı sürücüsü kalır."/>
          </StackPanel>
        </RadioButton>
      </UniformGrid>
      <DockPanel Grid.Row="2" Margin="6.71,10.86,6.71,0" LastChildFill="False">
        <TextBlock x:Name="ModeNote" DockPanel.Dock="Left" VerticalAlignment="Center" FontSize="12.2" Foreground="#A9B0B6"
                   Text="Bilgisayar 3 kez yeniden başlar. Her açılışta bu pencere kaldığı yerden devam eder."/>
        <Button x:Name="StartBtn" DockPanel.Dock="Right" Style="{StaticResource Yellow}" Content="Başlat"/>
      </DockPanel>
    </Grid>

    <!-- screen 2: progress -->
    <Grid x:Name="ProgressScreen" Grid.Row="1" Margin="28.43,17.57,28.43,28.43" Visibility="Collapsed">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="330.62"/>
        <ColumnDefinition Width="17.57"/>
        <ColumnDefinition/>
      </Grid.ColumnDefinitions>
      <Border Background="#3A3F44" CornerRadius="10.86" Padding="17.57,17.57">
        <DockPanel>
          <TextBlock DockPanel.Dock="Top" Text="ADIMLAR" FontSize="12.2" FontWeight="SemiBold" Foreground="#A9B0B6" Margin="0,0,0,10.86"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Steps"/></ScrollViewer>
        </DockPanel>
      </Border>
      <DockPanel Grid.Column="2">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock x:Name="ModeTitle" Text="" FontSize="12.2" Foreground="#F5C400" FontWeight="SemiBold"/>
          <TextBlock x:Name="Current" Text="Başlatılıyor…" FontSize="25.1" FontWeight="SemiBold" Margin="0,2.56,0,10.86" TextTrimming="CharacterEllipsis"/>
          <ProgressBar x:Name="Bar" Height="6.71" Minimum="0" Maximum="100" Value="0" Foreground="#F5C400" Background="#3A3F44" BorderThickness="0"/>
          <DockPanel Margin="0,6.71,0,0">
            <TextBlock x:Name="Percent" DockPanel.Dock="Right" Text="%0" FontSize="12.2" Foreground="#A9B0B6"/>
            <TextBlock x:Name="RestartInfo" FontSize="12.2" Foreground="#A9B0B6" TextWrapping="Wrap" Text=""/>
          </DockPanel>
          <Border x:Name="Banner" Background="#4A2E2B" BorderBrush="#E05A4F" BorderThickness="1" CornerRadius="6.71" Padding="10.86,10.86" Margin="0,10.86,0,0" Visibility="Collapsed">
            <DockPanel>
              <Button x:Name="OpenLogBtn" DockPanel.Dock="Right" Style="{StaticResource Flat}" Content="Kayıt klasörünü aç" Foreground="#F2F2F2"/>
              <TextBlock x:Name="BannerText" Text="" FontSize="12.2" TextWrapping="Wrap" VerticalAlignment="Center"/>
            </DockPanel>
          </Border>
        </StackPanel>
        <DockPanel DockPanel.Dock="Bottom" Margin="0,10.86,0,0" LastChildFill="False">
          <TextBlock x:Name="LogPath" DockPanel.Dock="Left" VerticalAlignment="Center" FontSize="12.2" Foreground="#80878D" Text=""/>
          <Button x:Name="RestartBtn" DockPanel.Dock="Right" Style="{StaticResource Yellow}" Content="Şimdi yeniden başlat" Visibility="Collapsed"/>
        </DockPanel>
        <Expander x:Name="Details" Header="Ayrıntılar" IsExpanded="True" Margin="0,17.57,0,0" Foreground="#F2F2F2" FontSize="12.2">
          <Border Background="#232629" CornerRadius="6.71" Margin="0,6.71,0,0" Padding="10.86,10.86">
            <TextBox x:Name="Log" Background="Transparent" BorderThickness="0" Foreground="#C9CED2" FontFamily="Consolas" FontSize="12.2"
                     IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
          </Border>
        </Expander>
      </DockPanel>
    </Grid>

    <!-- screen 3: done, the last question -->
    <Grid x:Name="DoneScreen" Grid.Row="1" Margin="28.43,17.57,28.43,28.43" Visibility="Collapsed">
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="545.81">
        <Border Width="46" Height="46" CornerRadius="28.43" Background="#5CB85C" HorizontalAlignment="Center">
          <TextBlock Text="✓" FontFamily="Segoe UI Symbol" FontSize="31.93" Foreground="#1E1E1E" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <TextBlock Text="Hazır" FontSize="31.93" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,10.86,0,4.15"/>
        <TextBlock x:Name="DoneSub" Text="Kurulum bitti. Son bir ayar kaldı: ekran renklerinin canlılığı." FontSize="15.51" Foreground="#A9B0B6" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
        <Border x:Name="VibrancePanel" Background="#3A3F44" CornerRadius="10.86" Padding="17.57,17.57" Margin="0,28.43,0,0">
          <StackPanel>
            <DockPanel>
              <Border DockPanel.Dock="Left" Width="28.43" Height="28.43" CornerRadius="6.71" Background="#F5C400" Margin="0,0,10.86,0">
                <TextBlock Text="V" FontWeight="Bold" FontSize="15.51" Foreground="#1E1E1E" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock x:Name="VibranceLabel" DockPanel.Dock="Left" Text="Digital Vibrance" FontSize="15.51" VerticalAlignment="Center" Width="150"/>
              <TextBlock x:Name="VibranceValue" DockPanel.Dock="Right" Text="%50" FontSize="15.51" FontWeight="SemiBold" VerticalAlignment="Center" Width="52" TextAlignment="Right"/>
              <Button x:Name="VibPlus" DockPanel.Dock="Right" Style="{StaticResource Flat}" Content="+" FontSize="15.51"/>
              <Button x:Name="VibMinus" DockPanel.Dock="Left" Style="{StaticResource Flat}" Content="−" FontSize="15.51"/>
              <Slider x:Name="Vibrance" Style="{StaticResource YSlider}" Minimum="50" Maximum="100" Value="50" IsSnapToTickEnabled="True" TickFrequency="1" SmallChange="1" LargeChange="10" VerticalAlignment="Center"/>
            </DockPanel>
            <TextBlock x:Name="VibranceHint" Text="50 = Windows varsayılanı · 100 = en canlı" FontSize="12.2" Foreground="#80878D" Margin="46,6.71,0,0"/>
          </StackPanel>
        </Border>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,17.57,0,0">
          <Button x:Name="SkipBtn" Style="{StaticResource Flat}" Content="Atla, dokunma" Margin="0,0,10.86,0"/>
          <Button x:Name="ApplyBtn" Style="{StaticResource Yellow}" Content="Uygula"/>
        </StackPanel>
        <TextBlock x:Name="DoneNote" Text="" FontSize="12.2" Foreground="#5CB85C" HorizontalAlignment="Center" Margin="0,10.86,0,0" TextWrapping="Wrap" TextAlignment="Center"/>
      </StackPanel>
    </Grid>
  </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($n in 'TitleLeft','TitleMark','TitleText','BrandCanvas','TitleBar','MinBtn','CloseBtn','ModeScreen','ProgressScreen','DoneScreen','ModeAllIn','ModeXbox','ModeStore','ModeVanilla','ModeNote',
               'StartBtn','Steps','ModeTitle','Current','Bar','Percent','RestartInfo','Banner','BannerText','OpenLogBtn','LogPath','RestartBtn','Log',
               'DoneSub','VibrancePanel','VibranceLabel','VibranceValue','VibPlus','VibMinus','Vibrance','VibranceHint','SkipBtn','ApplyBtn','DoneNote') { $ui[$n] = $win.FindName($n) }
$conv = [Windows.Media.BrushConverter]::new()
$brush = @{ Wait = $conv.ConvertFrom('#6E757B'); Run = $conv.ConvertFrom('#F5C400'); Pass = $conv.ConvertFrom('#5CB85C'); Fail = $conv.ConvertFrom('#E05A4F'); Text = $conv.ConvertFrom('#F2F2F2'); Dim = $conv.ConvertFrom('#A9B0B6') }
$glyph = @{ Wait = '○'; Run = '●'; Pass = '✓'; Fail = '✕' }

$brandFile = Join-Path $work 'brand.json'
$script:Brand = Read-Brand $brandFile
# the icon (title bar, taskbar, Alt+Tab), drawn here, no file needed: the yellow square on anthracite, or the brand's logo
# on its background square (favicon proportions: logo 3/4 of the square, 1/8 margin, corner radius 96/512)
try {
    $iconVisual = New-Object Windows.Media.DrawingVisual
    $dc = $iconVisual.RenderOpen()
    if ($script:Brand) {
        $iconBg = [Windows.Media.Brush]$conv.ConvertFrom($script:Brand.IconBackground)
        $dc.DrawRoundedRectangle($iconBg, $null, (New-Object Windows.Rect 0, 0, 64, 64), (64 * 96 / 512), (64 * 96 / 512))
        foreach ($part in $script:Brand.Logo) {
            $geo = [Windows.Media.Geometry]::Parse($part.Path).Clone()
            $tg = New-Object Windows.Media.TransformGroup
            $tg.Children.Add((New-Object Windows.Media.ScaleTransform (64 * 0.75 / $script:Brand.ViewBox), (64 * 0.75 / $script:Brand.ViewBox)))
            $tg.Children.Add((New-Object Windows.Media.TranslateTransform (64 / 8), (64 / 8)))
            $geo.Transform = $tg
            $dc.DrawGeometry($(if ($part.Fill -eq 'background') { $iconBg } else { [Windows.Media.Brush]$conv.ConvertFrom($part.Fill) }), $null, $geo)
        }
    }
    else {
        $dc.DrawRoundedRectangle([Windows.Media.Brush]$conv.ConvertFrom('#2F3337'), $null, (New-Object Windows.Rect 0, 0, 64, 64), 14, 14)
        $dc.DrawRoundedRectangle([Windows.Media.Brush]$conv.ConvertFrom('#F5C400'), $null, (New-Object Windows.Rect 16, 16, 32, 32), 7, 7)
    }
    $dc.Close()
    $iconBitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap(64, 64, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $iconBitmap.Render($iconVisual)
    $win.Icon = $iconBitmap
}
catch { }
# the progress also shows on the taskbar button: green while it runs, red when a step fails
$win.TaskbarItemInfo = New-Object Windows.Shell.TaskbarItemInfo
# the brand in the title bar, drawn at the positions Get-BrandLayout computes (the title as shapes from its exact baseline)
function Set-Brand($Brand) {
    $L = Get-BrandLayout $Brand 46
    $tileBrush = [Windows.Media.Brush]$conv.ConvertFrom($Brand.IconBackground)
    $square = New-Object Windows.Shapes.Rectangle
    $square.Width = $L.Tile; $square.Height = $L.Tile; $square.RadiusX = $L.Radius; $square.RadiusY = $L.Radius; $square.Fill = $tileBrush
    [Windows.Controls.Canvas]::SetLeft($square, $L.TileLeft); [Windows.Controls.Canvas]::SetTop($square, $L.TileTop)
    [void]$ui.BrandCanvas.Children.Add($square)
    foreach ($part in $Brand.Logo) {
        $shape = New-Object Windows.Shapes.Path
        $shape.Data = [Windows.Media.Geometry]::Parse($part.Path)
        $shape.Fill = if ($part.Fill -eq 'background') { $tileBrush } else { [Windows.Media.Brush]$conv.ConvertFrom($part.Fill) }
        $tg = New-Object Windows.Media.TransformGroup
        $tg.Children.Add((New-Object Windows.Media.ScaleTransform $L.Scale, $L.Scale))
        $tg.Children.Add((New-Object Windows.Media.TranslateTransform $L.LogoLeft, $L.LogoTop))
        $shape.RenderTransform = $tg
        [void]$ui.BrandCanvas.Children.Add($shape)
    }
    $face = New-Object Windows.Media.Typeface((New-Object Windows.Media.FontFamily $Brand.Font), [Windows.FontStyles]::Normal, $L.Weight, [Windows.FontStretches]::Normal)
    $ft = New-Object Windows.Media.FormattedText($Brand.Title, [Globalization.CultureInfo]::CurrentUICulture, [Windows.FlowDirection]::LeftToRight, $face, $L.FontSize, $brush.Text)
    $text = New-Object Windows.Shapes.Path
    $text.Data = $ft.BuildGeometry((New-Object Windows.Point $L.TextLeft, ($L.BaselineY - $ft.Baseline)))
    $text.Fill = $brush.Text
    [void]$ui.BrandCanvas.Children.Add($text)
    $ui.TitleLeft.Visibility = 'Collapsed'; $ui.BrandCanvas.Visibility = 'Visible'
    $win.Title = $Brand.Title
}if ($script:Brand) { try { Set-Brand $script:Brand } catch { $ui.TitleLeft.Visibility = 'Visible'; $ui.BrandCanvas.Visibility = 'Collapsed' } }

$script:Mode = 'full'; $script:Apps = 'off'; $script:Gpu = Get-Gpu
# an extra setup script waits for the end (another tool left it): its row shows from the start
$afterFile = Join-Path $work 'after-setup.ps1'
$script:AfterExpected = Test-Path -LiteralPath $afterFile
$script:AfterSetupRun = $false
$script:Expected = @(); $script:StartedAt = [datetime]::MinValue; $script:LastLogLen = -1; $script:Finished = $false
$script:LogRoot = Join-Path $env:ProgramData 'Cullewie\Logs'
$modeNames = @{ 'full-off' = 'All-in'; 'full-store' = 'Only Store Mode'; 'full-xbox' = 'Xbox & Store'; 'vanilla' = 'Vanilla Mode' }

function Show-Screen([string]$Name) { foreach ($s in 'ModeScreen', 'ProgressScreen', 'DoneScreen') { $ui[$s].Visibility = if ($s -eq $Name) { 'Visible' } else { 'Collapsed' } } }
function Set-Rows($Rows) {
    $ui.Steps.Children.Clear()
    foreach ($r in $Rows) {
        $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = '0,5,0,5'
        $g = New-Object Windows.Controls.TextBlock; $g.Width = 24; $g.FontSize = 14; $g.FontFamily = 'Segoe UI Symbol'; $g.Text = $glyph[$r.State]; $g.Foreground = $brush[$r.State]
        $l = New-Object Windows.Controls.TextBlock; $l.Text = $r.Label; $l.FontSize = 14; $l.TextTrimming = 'CharacterEllipsis'
        $l.Foreground = if ($r.State -eq 'Wait') { $brush.Dim } else { $brush.Text }
        if ($r.State -eq 'Run') { $l.FontWeight = 'SemiBold' }
        [void]$dp.Children.Add($g); [void]$dp.Children.Add($l); [void]$ui.Steps.Children.Add($dp)
    }
}
function Show-Banner([string]$Text) { $ui.BannerText.Text = $Text; $ui.Banner.Visibility = 'Visible'; $win.TaskbarItemInfo.ProgressState = 'Error' }
# the run name (folder suffix) tells the mode and the Store/Xbox level after a restart
function Set-ModeFromRun([string]$Run) {
    $leaf = Split-Path $Run -Leaf
    if ($leaf -match '-vanilla$') { $script:Mode = 'vanilla'; $script:Apps = 'off' }
    elseif ($leaf -match '-full-(off|store|xbox)$') { $script:Mode = 'full'; $script:Apps = $Matches[1] }
    $script:Expected = @(Get-ExpectedSteps $script:Mode $script:Apps $script:Gpu -After:$script:AfterExpected)
    $ui.ModeTitle.Text = $modeNames["$($script:Mode)$(if ($script:Mode -eq 'full') { '-' + $script:Apps })"]
}
function Update-Progress {
    $state = Get-RunState -Root $script:LogRoot -StatusPath $statusPath
    $workerDone = (-not $script:Worker) -or $script:Worker.HasExited
    $run = $state.Run
    if ($run -and $script:StartedAt -ne [datetime]::MinValue -and (Get-Item -LiteralPath $run).CreationTime -lt $script:StartedAt.AddSeconds(-5)) { $run = $null }
    if (-not $run) {
        if ($workerDone -and $script:Worker) {
            $ui.Current.Text = 'Kurulum başlamadı'
            Show-Banner $(if ($state.Status) { ConvertTo-TurkishStatus $state.Status } else { 'Kurulum hiç başlamadı. Pencereyi kapatıp yeniden dene.' })
            $script:Timer.Stop()
        }
        return
    }
    if (-not $script:Expected.Count) { Set-ModeFromRun $run }
    $ui.LogPath.Text = 'Kayıt: ' + $run
    $rows = @(Get-StepRows -Expected $script:Expected -Lines $state.Lines -Running $state.Running)
    Set-Rows $rows
    $done = @($rows | Where-Object { $_.State -in 'Pass', 'Fail' }).Count
    $pct = if ($rows.Count) { [int](100 * $done / $rows.Count) } else { 0 }
    $ui.Bar.Value = $pct; $ui.Percent.Text = "%$pct"
    if ($win.TaskbarItemInfo.ProgressState -ne 'Error') { $win.TaskbarItemInfo.ProgressState = 'Normal' }
    $win.TaskbarItemInfo.ProgressValue = $pct / 100
    $running = $rows | Where-Object State -eq 'Run' | Select-Object -First 1
    if ($running) { $ui.Current.Text = $running.Label }
    # an update restart is extra (only when Windows has updates waiting); the 3 counted are the setup's own
    $restarts = @($state.Lines | Where-Object { $n = ($_ -split "`t")[1]; $n -like 'Restart*' -and $n -ne 'Restart (updates)' }).Count
    if ($script:Mode -eq 'full') { $ui.RestartInfo.Text = "Yeniden başlatma $restarts / 3 · bilgisayar açılınca bu pencere kendiliğinden açılır." }
    $fails = @($rows | Where-Object State -eq 'Fail')
    if ($fails.Count) { Show-Banner ("Hata veren adım: " + (($fails | ForEach-Object Label) -join ', ') + '. Kurulum devam edebiliyorsa devam ediyor; ayrıntılar kayıtta.') }
    if ($state.RunningLog) {
        $len = (Get-Item -LiteralPath $state.RunningLog -ErrorAction SilentlyContinue).Length
        if ($len -ne $script:LastLogLen) {
            $script:LastLogLen = $len
            $ui.Log.Text = Read-Tail $state.RunningLog 400
            $ui.Log.CaretIndex = $ui.Log.Text.Length; $ui.Log.ScrollToEnd()
        }
    }
    $last = if (@($state.Lines).Count) { (@($state.Lines)[-1] -split "`t")[1] } else { '' }
    if ($last -like 'Restart*') { $ui.Current.Text = if ($last -eq 'Restart (final)') { 'Bitti · bilgisayar yeniden başlıyor…' } else { 'Bilgisayar yeniden başlıyor…' } }
    if ($workerDone -and $script:Worker -and -not $script:Finished) {
        $script:Finished = $true
        # the extra setup after the last restart is over: the Done screen (vibrance, cleanup, restart) comes now
        if ($script:AfterSetupRun) { $script:Timer.Stop(); try { Write-TestStep 'Ready' 'INFO' } catch { }; Show-Done; return }
        if ($script:Mode -eq 'vanilla' -and -not $fails.Count -and $last -notlike 'Setup stopped*') {
            $ui.Current.Text = 'Kurulum bitti'; $ui.Bar.Value = 100; $ui.Percent.Text = '%100'
            $ui.RestartInfo.Text = 'Bilgisayar 30 saniye içinde kendiliğinden yeniden başlar. Uygulamalar oturum açınca kurulur.'
            $ui.RestartBtn.Visibility = 'Visible'
        }
        elseif ($last -notlike 'Restart*') {
            $ui.Current.Text = 'Kurulum durdu'
            Show-Banner $(if ($state.Status) { ConvertTo-TurkishStatus $state.Status } else { 'Kurulum bir hatayla durdu. Ayrıntılar kayıtta.' })
        }
    }
}
function Start-Worker([string[]]$Arguments) {
    $launcher = Join-Path $PSScriptRoot 'Launcher.ps1'
    Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
    $script:Worker = Start-Process -FilePath $ps -ArgumentList (@('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$launcher`"") + $Arguments) -WindowStyle Hidden -PassThru
}
function Show-Done {
    Show-Screen 'DoneScreen'
    $win.TaskbarItemInfo.ProgressState = 'None'
    if ($script:Gpu -eq 'amd') {
        $ui.VibranceLabel.Text = 'Color Saturation'; $ui.Vibrance.Minimum = 100; $ui.Vibrance.Maximum = 200; $ui.Vibrance.Value = 100
        $ui.VibranceHint.Text = '100 = Windows varsayılanı · 200 = en canlı'
    }
    elseif ($script:Gpu -ne 'nvidia') {
        $ui.VibrancePanel.Visibility = 'Collapsed'; $ui.SkipBtn.Visibility = 'Collapsed'; $ui.ApplyBtn.Content = 'Kapat'
        $ui.DoneSub.Text = 'Kurulum bitti. Bilgisayar kullanıma hazır.'
    }
    $ui.VibranceValue.Text = '%' + [int]$ui.Vibrance.Value
}

$ui.ModeVanilla.Add_Checked({ $ui.ModeNote.Text = 'Bitince bilgisayar bir kez kendiliğinden yeniden başlar; uygulamalar oturum açınca kurulur.' })
foreach ($rb in 'ModeAllIn', 'ModeXbox', 'ModeStore') { $ui[$rb].Add_Checked({ $ui.ModeNote.Text = 'Önce bekleyen Windows güncellemeleri kurulur (gerekirse ek yeniden başlatma). Sonra bilgisayar 3 kez yeniden başlar. Her açılışta bu pencere kaldığı yerden devam eder.' }) }
$ui.StartBtn.Add_Click({
    if ($ui.ModeVanilla.IsChecked) { $script:Mode = 'vanilla'; $script:Apps = 'off' }
    else { $script:Mode = 'full'; $script:Apps = if ($ui.ModeXbox.IsChecked) { 'xbox' } elseif ($ui.ModeStore.IsChecked) { 'store' } else { 'off' } }
    $script:Expected = @(Get-ExpectedSteps $script:Mode $script:Apps $script:Gpu -After:$script:AfterExpected)
    $ui.ModeTitle.Text = $modeNames["$($script:Mode)$(if ($script:Mode -eq 'full') { '-' + $script:Apps })"]
    Set-Rows @(Get-StepRows -Expected $script:Expected -Lines @() -Running '')
    $ui.RestartInfo.Text = if ($script:Mode -eq 'full') { 'Yeniden başlatma 0 / 3 · bilgisayar açılınca bu pencere kendiliğinden açılır.' } else { '' }
    Show-Screen 'ProgressScreen'
    $script:StartedAt = Get-Date
    Start-Worker @('-Mode', $script:Mode, '-Apps', $script:Apps, '-Ui')
    $script:Timer.Start()
})
$ui.OpenLogBtn.Add_Click({ $s = Get-RunState -Root $script:LogRoot -StatusPath ''; Start-Process explorer.exe $(if ($s.Run) { $s.Run } else { $script:LogRoot }) })
$ui.RestartBtn.Add_Click({ shutdown -r -t 5 })
$ui.Vibrance.Add_ValueChanged({ $ui.VibranceValue.Text = '%' + [int]$ui.Vibrance.Value })
$ui.VibMinus.Add_Click({ $ui.Vibrance.Value = [math]::Max($ui.Vibrance.Minimum, $ui.Vibrance.Value - 1) })
$ui.VibPlus.Add_Click({ $ui.Vibrance.Value = [math]::Min($ui.Vibrance.Maximum, $ui.Vibrance.Value + 1) })
# the end: disk cleanup once, then Cleanup.ps1 restarts Windows itself (closing this window does not stop it)
function Start-Cleanup([string]$Before = '') {
    if ($script:CleanupStarted) { return }
    $script:CleanupStarted = $true
    # the brand was for this run only
    Remove-Item -LiteralPath $brandFile -Force -ErrorAction SilentlyContinue
    $ui.ApplyBtn.IsEnabled = $false; $ui.SkipBtn.IsEnabled = $false
    $ui.DoneNote.Foreground = $brush.Dim; $ui.DoneNote.Text = ($Before + 'Disk temizleniyor… Birkaç dakika sürebilir, bitince bilgisayar yeniden başlar.').Trim()
    $script:CleanupResult = Join-Path $env:TEMP ('cullewie-cleanup-' + [guid]::NewGuid().ToString('N') + '.txt')
    $cleanup = Join-Path $PSScriptRoot 'Scripts\Windows\Cleanup.ps1'
    $script:Cleaner = Start-Process -FilePath $ps -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cleanup`"", '-ResultPath', "`"$($script:CleanupResult)`"", '-Restart') -WindowStyle Hidden -PassThru
    $script:CleanupBefore = $Before
    $script:CleanupTimer.Start()
}
$script:CleanupTimer = New-Object Windows.Threading.DispatcherTimer
$script:CleanupTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:CleanupTimer.Add_Tick({
    if (-not $script:Cleaner.HasExited) { return }
    $script:CleanupTimer.Stop()
    $freed = 0L
    try { $freed = [int64](((Get-Content -LiteralPath $script:CleanupResult -Raw) -replace '^freed=', '').Trim()) } catch { }
    $text = if ($freed -ge 1GB) { ([double]$freed / 1GB).ToString('0.0', [Globalization.CultureInfo]'tr-TR') + ' GB' } else { [string][int][math]::Round([math]::Max(0, $freed) / 1MB) + ' MB' }
    $ui.DoneNote.Foreground = $brush.Pass
    $ui.DoneNote.Text = ($script:CleanupBefore + "Disk temizlendi: $text yer açıldı. Bilgisayar 10 saniye içinde yeniden başlıyor.").Trim()
})
# (never for -Snapshot: it shows the Done screen and closes the window, and once restarted the PC from a test)
$win.Add_Closing({ if (-not $Snapshot -and $ui.DoneScreen.Visibility -eq 'Visible') { Start-Cleanup } })
$ui.SkipBtn.Add_Click({ Start-Cleanup 'Renk ayarına dokunulmadı. ' })
$ui.ApplyBtn.Add_Click({
    if ($ui.VibrancePanel.Visibility -ne 'Visible') { Start-Cleanup; return }
    $ui.ApplyBtn.IsEnabled = $false; $ui.SkipBtn.IsEnabled = $false
    $ui.DoneNote.Foreground = $brush.Dim; $ui.DoneNote.Text = 'Uygulanıyor…'
    $display = Join-Path $PSScriptRoot 'Scripts\GPU\Display-Options.ps1'
    $script:Applier = Start-Process -FilePath $ps -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$display`"", '-Scaling', 'no', '-Level', [string][int]$ui.Vibrance.Value) -WindowStyle Hidden -PassThru
    $script:ApplyTimer.Start()
})
$script:ApplyTimer = New-Object Windows.Threading.DispatcherTimer
$script:ApplyTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:ApplyTimer.Add_Tick({
    if (-not $script:Applier.HasExited) { return }
    $script:ApplyTimer.Stop()
    if ($script:Applier.ExitCode -eq 0) { Start-Cleanup "$($ui.VibranceLabel.Text) $($ui.VibranceValue.Text) olarak ayarlandı. " }
    else { $ui.DoneNote.Foreground = $brush.Fail; $ui.DoneNote.Text = "Ayarlanamadı (çıkış kodu $($script:Applier.ExitCode)). Ekran kartı panelinden elle ayarlayabilirsin."; $ui.ApplyBtn.IsEnabled = $true }
})
$ui.CloseBtn.Add_Click({ $win.Close() })
$ui.MinBtn.Add_Click({ $win.WindowState = 'Minimized' })
$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })
# at sign-in other windows (a terminal, the desktop) open on top of it: bring it to the front once
$win.Add_ContentRendered({ $win.Topmost = $true; $win.Activate(); $win.Topmost = $false })
$script:Timer = New-Object Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromMilliseconds(800)
$script:Timer.Add_Tick({ try { Update-Progress } catch { } })

if ($Snapshot) {
    New-Item -ItemType Directory -Force -Path $Snapshot | Out-Null
    $win.WindowStartupLocation = 'Manual'; $win.Left = -4000; $win.Top = 0; $win.ShowActivated = $false
    $win.Show()
    function Save-Shot([string]$Name) {
        $win.UpdateLayout()
        $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$win.ActualWidth, [int]$win.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($win)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path $Snapshot $Name)); $enc.Save($fs); $fs.Close()
    }
    Save-Shot '1-mode.png'
    $script:Gpu = 'nvidia'; $script:Expected = @(Get-ExpectedSteps 'full' 'off' 'nvidia'); $ui.ModeTitle.Text = 'All-in'
    $t = "`t"; $demo = @("x${t}DDU (driver cleanup)${t}PASS", "x${t}Defender Optimize${t}PASS", "x${t}Restart (safe mode)${t}INFO", "x${t}DDU${t}FAIL")
    Set-Rows @(Get-StepRows -Expected $script:Expected -Lines $demo -Running 'Defender--safe-mode-')
    $ui.Current.Text = 'Defender (güvenli mod)'; $ui.Bar.Value = 25; $ui.Percent.Text = '%25'
    $ui.RestartInfo.Text = 'Yeniden başlatma 1 / 3 · bilgisayar açılınca bu pencere kendiliğinden açılır.'
    Show-Banner 'Hata veren adım: DDU: eski sürücü temizliği. Kurulum devam edebiliyorsa devam ediyor; ayrıntılar kayıtta.'
    $ui.Log.Text = "Defender settings applied`r`n"; $ui.LogPath.Text = 'Kayıt: C:\ProgramData\Cullewie\Logs\20261123-120000-full-off'
    Show-Screen 'ProgressScreen'; Save-Shot '2-progress.png'
    Show-Done; Save-Shot '3-done.png'
    $win.Close()
    return
}

if ($Done) {
    # one time only: remove the task first, record this boot for the test log, then ask the last question
    Unregister-ScheduledTask -TaskName $doneTask -Confirm:$false -ErrorAction SilentlyContinue
    try { . (Join-Path $PSScriptRoot 'Scripts\TestLog.ps1'); Save-BootEvents } catch { }
    if (Test-Path -LiteralPath $afterFile) {
        # extra setup first, shown like the other steps; Update-Progress opens the Done screen when it ends
        $script:AfterSetupRun = $true; $script:AfterExpected = $true
        Start-Worker @('-AfterSetup', '-Ui')
        Show-Screen 'ProgressScreen'
        $ui.Current.Text = 'Ek kurulum…'
        $script:Timer.Start()
    }
    else {
        try { Write-TestStep 'Ready' 'INFO' } catch { }
        Show-Done
    }
}
elseif ($Auto) {
    # started for All-in by another tool: no mode screen, the same start as pressing Başlat with All-in picked
    $ui.ModeAllIn.IsChecked = $true
    $win.Add_ContentRendered({ $ui.StartBtn.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
}
elseif ($Vanilla) {
    # started with CULLEWIE_MODE=vanilla: no mode screen, the same start as pressing Başlat with Vanilla Mode picked
    $ui.ModeVanilla.IsChecked = $true
    $win.Add_ContentRendered({ $ui.StartBtn.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
}
elseif ($Continue) {
    # after a Windows Update restart: the same start as pressing Başlat, in the mode saved before the restart
    # (apps.flag: store / xbox; no file = All-in). The Launcher removes its logon task itself.
    $flag = Join-Path $work 'apps.flag'
    $saved = if (Test-Path -LiteralPath $flag) { ([string](Get-Content -LiteralPath $flag -Raw)).Trim().ToLowerInvariant() } else { 'off' }
    $ui[$(switch ($saved) { 'xbox' { 'ModeXbox' } 'store' { 'ModeStore' } default { 'ModeAllIn' } })].IsChecked = $true
    $win.Add_ContentRendered({ $ui.StartBtn.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
}
elseif ($Resume -or $SafeScript) {
    if ($Resume) { Start-Worker @('-ResumeFullSetup', '-Ui') }
    Show-Screen 'ProgressScreen'
    $ui.Current.Text = 'Devam ediliyor…'
    $script:Timer.Start()
}
[void]$win.ShowDialog()
}
catch {
    # no window (for example in safe mode): the work still runs to the end
    if ($script:Worker) { try { $script:Worker.WaitForExit() } catch { } }
}
