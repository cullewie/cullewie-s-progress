# cullewie's progress: the window. It starts the setup (Launcher.ps1 -Ui) as a hidden process and follows its run log
# (C:\ProgramData\Cullewie\Logs: current.txt, steps.log, NN-<step>.log). It never runs a setup step itself.
#   (no switch)          mode screen: All-in, Xbox & Store, Only Store Mode, Vanilla Mode
#   -Resume              logon task after the safe-mode restart: runs Launcher -ResumeFullSetup -Ui and follows it
#   -SafeScript <path>   safe mode: runs the safe-mode script FIRST, then shows its progress (a window that fails to
#                        open can never keep the PC in safe mode)
#   -Done                one-time logon task after the last restart: the "Hazır" screen with Digital Vibrance
#   -Snapshot <folder>   renders the three screens to PNG files and closes (tests)
param([switch]$Resume, [string]$SafeScript = '', [switch]$Done, [string]$Snapshot = '')

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
function Get-ExpectedSteps([string]$Mode, [string]$Apps, [string]$Gpu) {
    if ($Mode -eq 'vanilla') { return @([pscustomobject]@{ Key = 'Back to Windows defaults (vanilla)'; Label = 'Windows varsayılanlarına dönüş' }) }
    $list = [ordered]@{}
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
    foreach ($k in $results.Keys) { if ($known -notcontains $k) { [pscustomobject]@{ Label = $k; State = $results[$k]; Key = $k } } }
}
function Get-Gpu {
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

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="cullewie's progress" Width="940" Height="630" WindowStartupLocation="CenterScreen"
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
            <Border x:Name="b" Background="#F5C400" CornerRadius="6" Padding="30,11">
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
            <Border x:Name="b" Background="Transparent" Padding="14,6">
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
            <Border x:Name="b" Background="#3A3F44" BorderBrush="#3A3F44" BorderThickness="2" CornerRadius="10" Padding="20,16" Margin="7">
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
            <Border Background="Transparent"><Border Height="4" CornerRadius="2" Background="{TemplateBinding Background}"/></Border>
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
                    <ControlTemplate TargetType="Thumb"><Border Background="#4A4F54" CornerRadius="3" Margin="2"/></ControlTemplate>
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
                        <ControlTemplate TargetType="Thumb"><Border Background="#4A4F54" CornerRadius="3" Margin="2"/></ControlTemplate>
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
      <DockPanel LastChildFill="False">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0" DockPanel.Dock="Left">
          <Border Width="12" Height="12" CornerRadius="3" Background="#F5C400" Margin="0,0,10,0"/>
          <TextBlock Text="cullewie's progress" FontSize="14" FontWeight="SemiBold"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
          <Button x:Name="MinBtn" Style="{StaticResource Flat}" Content="—" Width="46"/>
          <Button x:Name="CloseBtn" Style="{StaticResource Flat}" Content="✕" Width="46"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- screen 1: mode -->
    <Grid x:Name="ModeScreen" Grid.Row="1" Margin="30,22,30,26">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Margin="7,0,7,10">
        <TextBlock Text="Kurulum türünü seç" FontSize="26" FontWeight="SemiBold"/>
        <TextBlock Text="Windows 11'i oyun için hazırlar. Birini seç ve Başlat'a bas; gerisi kendiliğinden ilerler." FontSize="14" Foreground="#A9B0B6" Margin="0,4,0,0"/>
      </StackPanel>
      <UniformGrid Grid.Row="1" Rows="2" Columns="2">
        <RadioButton x:Name="ModeAllIn" Style="{StaticResource Card}" IsChecked="True">
          <StackPanel>
            <TextBlock Text="All-in" Style="{StaticResource CardTitle}"/>
            <TextBlock Style="{StaticResource CardText}" Text="Sürücüyü DDU ile temizleyip en güncel NVIDIA / AMD sürücüsünü kurar, ekranı ve Windows'u oyun için ayarlar. Windows Update, Microsoft Store ve Xbox çalışmaz."/>
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
      <DockPanel Grid.Row="2" Margin="7,12,7,0" LastChildFill="False">
        <TextBlock x:Name="ModeNote" DockPanel.Dock="Left" VerticalAlignment="Center" FontSize="13" Foreground="#A9B0B6"
                   Text="Bilgisayar 3 kez yeniden başlar. Her açılışta bu pencere kaldığı yerden devam eder."/>
        <Button x:Name="StartBtn" DockPanel.Dock="Right" Style="{StaticResource Yellow}" Content="Başlat"/>
      </DockPanel>
    </Grid>

    <!-- screen 2: progress -->
    <Grid x:Name="ProgressScreen" Grid.Row="1" Margin="30,22,30,26" Visibility="Collapsed">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="290"/>
        <ColumnDefinition Width="22"/>
        <ColumnDefinition/>
      </Grid.ColumnDefinitions>
      <Border Background="#3A3F44" CornerRadius="10" Padding="18,16">
        <DockPanel>
          <TextBlock DockPanel.Dock="Top" Text="ADIMLAR" FontSize="11" FontWeight="SemiBold" Foreground="#A9B0B6" Margin="0,0,0,10"/>
          <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Steps"/></ScrollViewer>
        </DockPanel>
      </Border>
      <DockPanel Grid.Column="2">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock x:Name="ModeTitle" Text="" FontSize="13" Foreground="#F5C400" FontWeight="SemiBold"/>
          <TextBlock x:Name="Current" Text="Başlatılıyor…" FontSize="24" FontWeight="SemiBold" Margin="0,2,0,12" TextTrimming="CharacterEllipsis"/>
          <ProgressBar x:Name="Bar" Height="8" Minimum="0" Maximum="100" Value="0" Foreground="#F5C400" Background="#3A3F44" BorderThickness="0"/>
          <DockPanel Margin="0,8,0,0">
            <TextBlock x:Name="Percent" DockPanel.Dock="Right" Text="%0" FontSize="13" Foreground="#A9B0B6"/>
            <TextBlock x:Name="RestartInfo" FontSize="13" Foreground="#A9B0B6" TextWrapping="Wrap" Text=""/>
          </DockPanel>
          <Border x:Name="Banner" Background="#4A2E2B" BorderBrush="#E05A4F" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,12,0,0" Visibility="Collapsed">
            <DockPanel>
              <Button x:Name="OpenLogBtn" DockPanel.Dock="Right" Style="{StaticResource Flat}" Content="Kayıt klasörünü aç" Foreground="#F2F2F2"/>
              <TextBlock x:Name="BannerText" Text="" FontSize="13" TextWrapping="Wrap" VerticalAlignment="Center"/>
            </DockPanel>
          </Border>
        </StackPanel>
        <DockPanel DockPanel.Dock="Bottom" Margin="0,14,0,0" LastChildFill="False">
          <TextBlock x:Name="LogPath" DockPanel.Dock="Left" VerticalAlignment="Center" FontSize="12" Foreground="#80878D" Text=""/>
          <Button x:Name="RestartBtn" DockPanel.Dock="Right" Style="{StaticResource Yellow}" Content="Yeniden başlat" Visibility="Collapsed"/>
        </DockPanel>
        <Expander x:Name="Details" Header="Ayrıntılar" IsExpanded="True" Margin="0,16,0,0" Foreground="#F2F2F2" FontSize="13">
          <Border Background="#232629" CornerRadius="8" Margin="0,8,0,0" Padding="12,10">
            <TextBox x:Name="Log" Background="Transparent" BorderThickness="0" Foreground="#C9CED2" FontFamily="Consolas" FontSize="12"
                     IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
          </Border>
        </Expander>
      </DockPanel>
    </Grid>

    <!-- screen 3: done, the last question -->
    <Grid x:Name="DoneScreen" Grid.Row="1" Margin="30,22,30,26" Visibility="Collapsed">
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="620">
        <Border Width="64" Height="64" CornerRadius="32" Background="#5CB85C" HorizontalAlignment="Center">
          <TextBlock Text="✓" FontFamily="Segoe UI Symbol" FontSize="32" Foreground="#1E1E1E" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <TextBlock Text="Hazır" FontSize="30" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,14,0,4"/>
        <TextBlock x:Name="DoneSub" Text="Kurulum bitti. Son bir ayar kaldı: ekran renklerinin canlılığı." FontSize="14" Foreground="#A9B0B6" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
        <Border x:Name="VibrancePanel" Background="#3A3F44" CornerRadius="10" Padding="22,18" Margin="0,26,0,0">
          <StackPanel>
            <DockPanel>
              <Border DockPanel.Dock="Left" Width="26" Height="26" CornerRadius="6" Background="#F5C400" Margin="0,0,12,0">
                <TextBlock Text="V" FontWeight="Bold" FontSize="14" Foreground="#1E1E1E" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock x:Name="VibranceLabel" DockPanel.Dock="Left" Text="Digital Vibrance" FontSize="15" VerticalAlignment="Center" Width="150"/>
              <TextBlock x:Name="VibranceValue" DockPanel.Dock="Right" Text="%50" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" Width="52" TextAlignment="Right"/>
              <Button x:Name="VibPlus" DockPanel.Dock="Right" Style="{StaticResource Flat}" Content="+" FontSize="16"/>
              <Button x:Name="VibMinus" DockPanel.Dock="Left" Style="{StaticResource Flat}" Content="−" FontSize="16"/>
              <Slider x:Name="Vibrance" Style="{StaticResource YSlider}" Minimum="50" Maximum="100" Value="50" IsSnapToTickEnabled="True" TickFrequency="1" SmallChange="1" LargeChange="10" VerticalAlignment="Center"/>
            </DockPanel>
            <TextBlock x:Name="VibranceHint" Text="50 = Windows varsayılanı · 100 = en canlı" FontSize="12" Foreground="#80878D" Margin="38,8,0,0"/>
          </StackPanel>
        </Border>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,22,0,0">
          <Button x:Name="SkipBtn" Style="{StaticResource Flat}" Content="Atla, dokunma" Margin="0,0,12,0"/>
          <Button x:Name="ApplyBtn" Style="{StaticResource Yellow}" Content="Uygula"/>
        </StackPanel>
        <TextBlock x:Name="DoneNote" Text="" FontSize="13" Foreground="#5CB85C" HorizontalAlignment="Center" Margin="0,14,0,0" TextWrapping="Wrap" TextAlignment="Center"/>
      </StackPanel>
    </Grid>
  </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}
foreach ($n in 'TitleBar','MinBtn','CloseBtn','ModeScreen','ProgressScreen','DoneScreen','ModeAllIn','ModeXbox','ModeStore','ModeVanilla','ModeNote',
               'StartBtn','Steps','ModeTitle','Current','Bar','Percent','RestartInfo','Banner','BannerText','OpenLogBtn','LogPath','RestartBtn','Log',
               'DoneSub','VibrancePanel','VibranceLabel','VibranceValue','VibPlus','VibMinus','Vibrance','VibranceHint','SkipBtn','ApplyBtn','DoneNote') { $ui[$n] = $win.FindName($n) }
$conv = [Windows.Media.BrushConverter]::new()
$brush = @{ Wait = $conv.ConvertFrom('#6E757B'); Run = $conv.ConvertFrom('#F5C400'); Pass = $conv.ConvertFrom('#5CB85C'); Fail = $conv.ConvertFrom('#E05A4F'); Text = $conv.ConvertFrom('#F2F2F2'); Dim = $conv.ConvertFrom('#A9B0B6') }
$glyph = @{ Wait = '○'; Run = '●'; Pass = '✓'; Fail = '✕' }

$script:Mode = 'full'; $script:Apps = 'off'; $script:Gpu = Get-Gpu
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
function Show-Banner([string]$Text) { $ui.BannerText.Text = $Text; $ui.Banner.Visibility = 'Visible' }
# the run name (folder suffix) tells the mode and the Store/Xbox level after a restart
function Set-ModeFromRun([string]$Run) {
    $leaf = Split-Path $Run -Leaf
    if ($leaf -match '-vanilla$') { $script:Mode = 'vanilla'; $script:Apps = 'off' }
    elseif ($leaf -match '-full-(off|store|xbox)$') { $script:Mode = 'full'; $script:Apps = $Matches[1] }
    $script:Expected = @(Get-ExpectedSteps $script:Mode $script:Apps $script:Gpu)
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
            Show-Banner $(if ($state.Status) { $state.Status } else { 'Kurulum hiç başlamadı. Pencereyi kapatıp yeniden dene.' })
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
    $running = $rows | Where-Object State -eq 'Run' | Select-Object -First 1
    if ($running) { $ui.Current.Text = $running.Label }
    $restarts = @($state.Lines | Where-Object { ($_ -split "`t")[1] -like 'Restart*' }).Count
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
        if ($script:Mode -eq 'vanilla' -and -not $fails.Count -and $last -notlike 'Setup stopped*') {
            $ui.Current.Text = 'Kurulum bitti'; $ui.Bar.Value = 100; $ui.Percent.Text = '%100'
            $ui.RestartInfo.Text = 'Değişikliklerin tamamlanması için bilgisayarı yeniden başlat.'
            $ui.RestartBtn.Visibility = 'Visible'
        }
        elseif ($last -notlike 'Restart*') {
            $ui.Current.Text = 'Kurulum durdu'
            Show-Banner $(if ($state.Status) { $state.Status } else { 'Kurulum bir hatayla durdu. Ayrıntılar kayıtta.' })
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

$ui.ModeVanilla.Add_Checked({ $ui.ModeNote.Text = 'Yeniden başlatma yok. Bittiğinde bilgisayarı yeniden başlatman istenir.' })
foreach ($rb in 'ModeAllIn', 'ModeXbox', 'ModeStore') { $ui[$rb].Add_Checked({ $ui.ModeNote.Text = 'Bilgisayar 3 kez yeniden başlar. Her açılışta bu pencere kaldığı yerden devam eder.' }) }
$ui.StartBtn.Add_Click({
    if ($ui.ModeVanilla.IsChecked) { $script:Mode = 'vanilla'; $script:Apps = 'off' }
    else { $script:Mode = 'full'; $script:Apps = if ($ui.ModeXbox.IsChecked) { 'xbox' } elseif ($ui.ModeStore.IsChecked) { 'store' } else { 'off' } }
    $script:Expected = @(Get-ExpectedSteps $script:Mode $script:Apps $script:Gpu)
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
$ui.SkipBtn.Add_Click({ $ui.DoneNote.Foreground = $brush.Dim; $ui.DoneNote.Text = 'Renk ayarına dokunulmadı. Pencereyi kapatabilirsin.'; $ui.ApplyBtn.IsEnabled = $false; $ui.SkipBtn.IsEnabled = $false })
$ui.ApplyBtn.Add_Click({
    if ($ui.VibrancePanel.Visibility -ne 'Visible') { $win.Close(); return }
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
    if ($script:Applier.ExitCode -eq 0) { $ui.DoneNote.Foreground = $brush.Pass; $ui.DoneNote.Text = "$($ui.VibranceLabel.Text) $($ui.VibranceValue.Text) olarak ayarlandı. Pencereyi kapatabilirsin." }
    else { $ui.DoneNote.Foreground = $brush.Fail; $ui.DoneNote.Text = "Ayarlanamadı (çıkış kodu $($script:Applier.ExitCode)). Ekran kartı panelinden elle ayarlayabilirsin."; $ui.ApplyBtn.IsEnabled = $true }
})
$ui.CloseBtn.Add_Click({ $win.Close() })
$ui.MinBtn.Add_Click({ $win.WindowState = 'Minimized' })
$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })
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
    try { . (Join-Path $PSScriptRoot 'Scripts\TestLog.ps1'); Save-BootEvents; Write-TestStep 'Ready' 'INFO' } catch { }
    Show-Done
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
