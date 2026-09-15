#requires -Version 5.1
[CmdletBinding()]
param([switch]$CatalogOnly, [switch]$SelfTest, [switch]$SmokeTest, [string]$PreviewPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$catalogJson = @'
@@CATALOG@@
'@
$xamlText = @'
@@XAML@@
'@
if ($catalogJson.Trim().StartsWith('@@')) {
    $catalogJson = Get-Content (Join-Path $PSScriptRoot 'catalog.json') -Raw -Encoding UTF8
    $xamlText = Get-Content (Join-Path $PSScriptRoot 'interface.xaml') -Raw -Encoding UTF8
}
$iconData = '@@ICON@@'
if ($iconData.StartsWith('@@')) { $iconData=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'src/firstinstall.ico'))) }
# Windows PowerShell 5.1 emits JSON arrays as one pipeline object; enumerate explicitly.
$catalog = @($catalogJson | ConvertFrom-Json | ForEach-Object { $_ })
$byKey = @{}
foreach ($app in $catalog) { $byKey[$app.Key] = $app }
$profilesJson = @'
@@PROFILES@@
'@
if ($profilesJson.Trim().StartsWith('@@')) { $profilesJson=Get-Content (Join-Path $PSScriptRoot 'profiles.json') -Raw -Encoding UTF8 }
$profiles=@($profilesJson | ConvertFrom-Json | ForEach-Object { $_ })
$profilesByKey=@{}
foreach ($profile in $profiles) { $profilesByKey[$profile.Key]=$profile }
function Get-Plan([string[]]$Keys) {
    $seen = @{}
    $ordered = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in $Keys) {
        if (-not $byKey.ContainsKey($key)) { throw "Unknown application: $key" }
        foreach ($dependency in $byKey[$key].Requires) {
            if (-not $seen.ContainsKey($dependency)) { $ordered.Add($byKey[$dependency]); $seen[$dependency] = $true }
        }
        if (-not $seen.ContainsKey($key)) { $ordered.Add($byKey[$key]); $seen[$key] = $true }
    }
    return $ordered.ToArray()
}
if ($CatalogOnly) { $catalogJson; return }
if ($SelfTest) {
    if ($profiles.Count -ne 8 -or $profilesByKey.Count -ne $profiles.Count) { throw 'Invalid built-in profiles.' }
    foreach ($profile in $profiles) {
        if (-not $profile.Name -or -not $profile.Description -or $profile.Apps.Count -eq 0) { throw 'Incomplete profile.' }
        if (@($profile.Apps | Select-Object -Unique).Count -ne $profile.Apps.Count) { throw 'Duplicate profile app.' }
        Get-Plan @($profile.Apps) | Out-Null
    }
    if ((@(Get-Plan @($profilesByKey['audio'].Apps))).Key -notcontains 'apo') { throw 'Audio profile is missing APO.' }
    foreach ($key in $profilesByKey['opensource'].Apps) { if ($byKey[$key].OpenSource -ne $true) { throw 'Open-source profile includes an unverified license.' } }
    if ($catalog.Count -ne 253 -or $byKey.Count -ne $catalog.Count) { throw 'Invalid catalog.' }
    $packageIds=@($catalog | ForEach-Object { $_.Ids })
    if (@($packageIds | Select-Object -Unique).Count -ne $packageIds.Count) { throw 'Duplicate package IDs.' }
    foreach ($app in $catalog) {
        if (-not $app.Name -or -not $app.Description -or -not $app.Category) { throw 'Missing catalog copy.' }
        if (($app.Ids.Count -gt 0) -eq (-not [string]::IsNullOrEmpty($app.Url))) { throw 'Each app needs exactly one installation method.' }
        foreach ($dependency in $app.Requires) { if (-not $byKey.ContainsKey($dependency)) { throw 'Missing dependency.' } }
    }
    $plan = @(Get-Plan @('peace','apo','ts3','peace'))
    if (($plan.Key -join ',') -ne 'apo,peace,ts3') { throw 'Invalid dependency order.' }
    $rejected = $false
    try { Get-Plan @('untrusted') | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unknown profile ID was accepted.' }
    if ($byKey['ts3'].Ids[0] -ne 'TeamSpeakSystems.TeamSpeakClient') { throw 'Incorrect TeamSpeak client.' }
    'PASS: catalog, dependencies, package IDs, 8 built-in profiles, open-source profile licenses and TeamSpeak 3.'
    return
}
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
$windowCode = @'
@@WINDOW_HELPER@@
'@
if ($windowCode.Trim().StartsWith('@@')) { $windowCode=Get-Content (Join-Path $PSScriptRoot 'src/window-helper.cs') -Raw -Encoding UTF8 }
if (-not ('FirstInstallWindow' -as [type])) { Add-Type -TypeDefinition $windowCode }
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) { throw 'Requires 64-bit Windows.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Open the executable or use powershell.exe -STA -File vexan_installers.ps1.' }
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    # UISettings exposes the actual Windows accent, including automatic wallpaper colors.
    $script:accentSettings=$null
    try {
        [Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime] | Out-Null
        $script:accentSettings=[Windows.UI.ViewManagement.UISettings]::new()
    } catch { }
    function Get-WindowsAccent {
        try {
            if ($null -ne $script:accentSettings) {
                $color=$script:accentSettings.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Accent)
                return [Windows.Media.Color]::FromRgb($color.R,$color.G,$color.B)
            }
        } catch { }
        $color=[Windows.SystemParameters]::WindowGlassColor
        return [Windows.Media.Color]::FromRgb($color.R,$color.G,$color.B)
    }
    function Mix-Accent([Windows.Media.Color]$Color,[Windows.Media.Color]$Other,[double]$Amount) {
        return [Windows.Media.Color]::FromRgb([byte]($Color.R*(1-$Amount)+$Other.R*$Amount),[byte]($Color.G*(1-$Amount)+$Other.G*$Amount),[byte]($Color.B*(1-$Amount)+$Other.B*$Amount))
    }
    function Get-Luminance([Windows.Media.Color]$Color) {
        $values=@($Color.R,$Color.G,$Color.B) | ForEach-Object {
            $v=$_/255.0
            if ($v -le 0.04045) { $v/12.92 } else { [Math]::Pow(($v+0.055)/1.055,2.4) }
        }
        return 0.2126*$values[0]+0.7152*$values[1]+0.0722*$values[2]
    }
    function Set-AccentPalette([Windows.Media.Color]$Color) {
        $white=[Windows.Media.Colors]::White
        $base=[Windows.Media.ColorConverter]::ConvertFromString('#1B1E25')
        $text=$Color
        for ($i=0;$i -lt 20 -and ((Get-Luminance $text)+0.05)/((Get-Luminance $base)+0.05) -lt 4.5;$i++) { $text=Mix-Accent $text $white 0.12 }
        $foreground=if ((Get-Luminance $Color) -gt 0.179) { [Windows.Media.Colors]::Black } else { $white }
        $palette=@{
            AccentBrush=$Color
            AccentTextBrush=$text
            AccentForegroundBrush=$foreground
            AccentMutedBrush=(Mix-Accent $text $base 0.25)
            AccentHoverBrush=(Mix-Accent $text $white 0.15)
            AccentSurfaceBrush=(Mix-Accent $Color $base 0.82)
        }
        foreach ($key in $palette.Keys) {
            $window.Resources[$key]=[Windows.Media.SolidColorBrush]::new($palette[$key])
        }
        $script:lastAccent=$Color.ToString()
    }
    function Update-WindowsAccent {
        $color=Get-WindowsAccent
        if ($color.ToString() -ne $script:lastAccent) { Set-AccentPalette $color }
    }
    $script:lastAccent=''
    Update-WindowsAccent
    # Poll on the WPF dispatcher: WinRT change callbacks otherwise run outside the PS runspace.
    $accentTimer=New-Object Windows.Threading.DispatcherTimer
    $accentTimer.Interval=[TimeSpan]::FromSeconds(1)
    $accentTimer.Add_Tick({ Update-WindowsAccent })
    $window.Add_Closed({ $accentTimer.Stop() })
    $accentTimer.Start()
    $window.Add_SourceInitialized({
        $script:cornerResult=[FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($window).Handle)
    })
    $iconStream=[IO.MemoryStream]::new([Convert]::FromBase64String($iconData))
    $window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create($iconStream,[Windows.Media.Imaging.BitmapCreateOptions]::None,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $iconStream.Dispose()
    $window.Height=[Math]::Min(840,[Windows.SystemParameters]::WorkArea.Height-24)
    $ui = @{}
    foreach ($name in @('Categories','Search','ClearSearch','ResultCount','UserProfiles','ClearSelection','Cards','Empty','LogBox','SelectedCount','SaveSetup','Import','Export','QueuePanel','Status','Progress','Install','Cancel','OpenLogs','Environment','MinimizeWindow','MaximizeWindow','CloseWindow','MaximizeGlyph','LibraryScroll')) { $ui[$name] = $window.FindName($name) }
    $ui.Profiles=$window.FindName('Profiles')
    $ui.MinimizeWindow.Add_Click({ $window.WindowState='Minimized' })
    $ui.MaximizeWindow.Add_Click({
        if ($window.WindowState -eq 'Maximized') { $window.WindowState='Normal' }
        else { $window.WindowState='Maximized' }
    })
    $ui.CloseWindow.Add_Click({ $window.Close() })
    $window.Add_StateChanged({
        $maximized=$window.WindowState -eq 'Maximized'
        $ui.MaximizeWindow.ToolTip=if ($maximized) { 'Restore' } else { 'Maximize' }
        [Windows.Automation.AutomationProperties]::SetName($ui.MaximizeWindow,[string]$ui.MaximizeWindow.ToolTip)
        $ui.MaximizeGlyph.Data=if ($maximized) { 'M 2,0 L 10,0 10,8 M 0,2 L 8,2 8,10 0,10 Z' } else { 'M 0,0 L 10,0 10,10 0,10 Z' }
    })
    $selected = @{}
    $checks = @{}
    $statuses = @{}
    $category = 'All apps'
    $busy = $false
    $syncing = $false
    $job = $null
    $logDir = if ($SmokeTest) { Join-Path $PSScriptRoot 'test-logs' } else { Join-Path $env:LOCALAPPDATA 'FirstInstall\Logs' }
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir ('session-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$PID)
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    $winget = if ($wingetCommand) { $wingetCommand.Source } else { '' }
    $ui.Environment.Text = if ($winget) { 'WinGet ready · {0} apps to explore' -f $catalog.Count } else { 'WinGet is missing. Install App Installer to enable automatic installs.' }
    function Add-Log([string]$Message) {
        $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Message
        $ui.LogBox.AppendText($line + "`r`n")
        $ui.LogBox.ScrollToEnd()
        try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { $ui.Status.Text = 'Could not save the log to disk.' }
    }
    function New-Label([string]$Text, [string]$Color='#F3F5F7', [double]$Size=13) {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $Text; $label.Foreground = $Color; $label.FontSize = $Size
        $label.TextWrapping = 'Wrap'
        return $label
    }
    function Update-Selection {
        $script:syncing = $true
        foreach ($app in $catalog) { $checks[$app.Key].IsChecked = $selected.ContainsKey($app.Key) }
        $script:syncing = $false
        $ui.SelectedCount.Text = '{0} apps selected' -f $selected.Count
        $ui.Install.IsEnabled = ($selected.Count -gt 0 -and -not $busy)
        $ui.SaveSetup.IsEnabled=($selected.Count -gt 0 -and -not $busy)
        $script:removeButtons=@{}
        $ui.QueuePanel.Children.Clear()
        if ($selected.Count -eq 0) {
            $label = New-Label 'Your next setup starts here. Select apps from the library.' '#8793A2'
            $label.Margin = '0,15,0,0'; $ui.QueuePanel.Children.Add($label) | Out-Null
        }
        foreach ($app in @(Get-Plan @($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key }))) {
            $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '0,8,0,9'
            $title = New-Label $app.Name; $title.FontWeight = 'SemiBold'
            $row=New-Object Windows.Controls.Grid
            $row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
            $actionColumn=New-Object Windows.Controls.ColumnDefinition; $actionColumn.Width='Auto'
            $row.ColumnDefinitions.Add($actionColumn)
            $title.Margin='0,0,8,0'; $title.VerticalAlignment='Center'
            $row.Children.Add($title) | Out-Null
            $remove=New-Object Windows.Controls.Button
            $remove.Content='×'; $remove.Tag=$app.Key; $remove.Width=32; $remove.MinHeight=32
            $remove.Padding='0'; $remove.Margin='0'; $remove.FontSize=18
            $remove.Background='Transparent'; $remove.BorderThickness='0'
            $remove.ToolTip='Remove '+$app.Name+' from your setup'
            [Windows.Automation.AutomationProperties]::SetName($remove,'Remove '+$app.Name)
            $remove.IsEnabled=-not $busy
            [Windows.Controls.Grid]::SetColumn($remove,1)
            $remove.Add_Click({ param($sender,$eventArgs) Remove-SelectedApp ([string]$sender.Tag) })
            $script:removeButtons[$app.Key]=$remove
            $row.Children.Add($remove) | Out-Null
            $panel.Children.Add($row) | Out-Null
            $text = if ($statuses.ContainsKey($app.Key)) { $statuses[$app.Key] } elseif ($app.Ids.Count) { 'Automatic · WinGet' } else { 'Guided · official website' }
            $label = New-Label $text '#A0AAB7' 12; $label.Margin = '0,4,0,0'
            $panel.Children.Add($label) | Out-Null
            $ui.QueuePanel.Children.Add($panel) | Out-Null
        }
    }
    function Remove-SelectedApp([string]$Key) {
        if ($script:busy) { return }
        $selected.Remove($Key); $statuses.Remove($Key)
        foreach ($item in $catalog) {
            if ($item.Requires -contains $Key) { $selected.Remove($item.Key); $statuses.Remove($item.Key) }
        }
        Update-Selection
        $ui.Status.Text='Selection updated. Review before installing.'
    }
    function Set-Selection([string[]]$Keys) {
        $selected.Clear(); $statuses.Clear()
        foreach ($app in @(Get-Plan $Keys)) { $selected[$app.Key] = $true }
        Update-Selection
        $ui.Status.Text=if ($selected.Count) { 'Selection updated. Review before installing.' } else { 'Ready when you are.' }
    }
    function Update-Filter {
        $query = $ui.Search.Text.Trim()
        $count = 0
        # Fixed ItemWidth reserves a slot even for a collapsed child in WrapPanel.
        # Keep checkbox instances in $checks, but only attach matching cards.
        $ui.Cards.Children.Clear()
        foreach ($app in $catalog) {
            $match = ($category -eq 'All apps' -or $app.Category -eq $category) -and
                (($app.Name + ' ' + $app.Category + ' ' + $app.Description).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)
            $checks[$app.Key].Visibility = if ($match) { 'Visible' } else { 'Collapsed' }
            if ($match) { $ui.Cards.Children.Add($checks[$app.Key]) | Out-Null; $count++ }
        }
        $ui.ResultCount.Text = "$category · $count apps"
        $ui.Empty.Visibility = if ($count -eq 0) { 'Visible' } else { 'Collapsed' }
        $ui.LibraryScroll.ScrollToTop()
    }
    foreach ($app in $catalog) {
        $check = New-Object Windows.Controls.CheckBox
        $check.Style = $window.Resources['CardCheck']; $check.Tag = $app.Key
        $check.Width = 220; $check.Margin = '0,0,12,12'; $check.MinHeight = 190
        $check.ToolTip = if ($app.Ids.Count) { 'WinGet: ' + ($app.Ids -join ', ') } else { $app.Url }
        [Windows.Automation.AutomationProperties]::SetName($check,$app.Name)
        $content = New-Object Windows.Controls.StackPanel
        $top = New-Label $app.Category '#A0AAB7' 12
        $top.FontWeight = 'SemiBold'; $content.Children.Add($top) | Out-Null
        $name = New-Label $app.Name '#F3F5F7' 16; $name.FontWeight = 'SemiBold'; $name.Margin = '0,12,0,5'
        $content.Children.Add($name) | Out-Null
        $desc = New-Label $app.Description '#A0AAB7' 12; $desc.MinHeight = 33
        $content.Children.Add($desc) | Out-Null
        $mode = if ($app.Ids.Count) { 'AUTOMATIC' } else { 'GUIDED INSTALL ↗' }
        $badge = New-Label $mode '#A0AAB7' 12; $badge.Margin = '0,10,0,0'
        $content.Children.Add($badge) | Out-Null
        if ($app.LicenseLabel) {
            $licenseLabel=New-Label $app.LicenseLabel '#F3F5F7' 12
            $licenseLabel.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'AccentTextBrush')
            $licenseLabel.Margin='0,6,0,0'
            $content.Children.Add($licenseLabel) | Out-Null
        }
        $check.Content = $content
        $check.Add_Click({
            param($sender,$eventArgs)
            if ($script:syncing -or $script:busy) { return }
            $key = [string]$sender.Tag
            if ($sender.IsChecked) {
                foreach ($item in @(Get-Plan @($key))) { $selected[$item.Key] = $true }
            } else {
                $selected.Remove($key)
                foreach ($item in $catalog) { if ($item.Requires -contains $key) { $selected.Remove($item.Key) } }
            }
            Update-Selection
        })
        $checks[$app.Key] = $check; $ui.Cards.Children.Add($check) | Out-Null
    }
    foreach ($cat in @('All apps') + @($catalog.Category | Sort-Object -Unique)) {
        $button = New-Object Windows.Controls.Button
        $button.Content = New-Label $(if ($cat -eq $category) { '› ' + $cat } else { $cat }) '#DCE1E7' 12
        $button.Tag = $cat; $button.Margin = '0,0,0,6'
        $button.Padding = '8,10'; $button.HorizontalContentAlignment = 'Left'
        if ($cat -eq $category) { $button.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') } else { $button.Background='Transparent' }
        $button.BorderThickness = '1'; $button.BorderBrush = 'Transparent'
        $button.Add_Click({
            param($sender,$eventArgs)
            $script:category = [string]$sender.Tag
            foreach ($b in $ui.Categories.Children) { $b.Content.Text = if ($b.Tag -eq $script:category) { '› ' + $b.Tag } else { $b.Tag }; if ($b.Tag -eq $script:category) { $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') } else { $b.Background='Transparent' } }
            Update-Filter
            $ui.LibraryScroll.ScrollToTop()
        })
        $ui.Categories.Children.Add($button) | Out-Null
    }
    $ui.Search.Add_TextChanged({ Update-Filter })
    $ui.ClearSearch.Add_Click({ $ui.Search.Clear(); $ui.Search.Focus() | Out-Null })
    $window.Add_PreviewKeyDown({
        param($sender,$e)
        if ($e.Key -eq 'F' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            $ui.Search.Focus() | Out-Null; $ui.Search.SelectAll(); $e.Handled=$true
        }
    })
    $ui.ClearSelection.Add_Click({ Set-Selection @() })
    function Apply-Profile([string]$Key) {
        if ($script:busy) { return }
        $profile=$profilesByKey[$Key]
        Set-Selection @($profile.Apps)
        $ui.Status.Text=$profile.Name + ' profile applied. Review your apps before installing.'
    }
    $profileMenu=New-Object Windows.Controls.ContextMenu
    $profileMenu.Resources=$window.Resources
    $profileMenu.PlacementTarget=$ui.Profiles
    $profileMenu.Placement='Bottom'
    $profileItems=@{}
    foreach ($profile in $profiles) {
        $plan=@(Get-Plan @($profile.Apps))
        $item=New-Object Windows.Controls.MenuItem
        $item.Tag=$profile.Key
        $header=New-Object Windows.Controls.StackPanel
        $header.MaxWidth=310
        $title=New-Label ($profile.Name + ' · ' + $plan.Count + ' apps') '#F3F5F7' 13
        $title.FontWeight='SemiBold'
        $header.Children.Add($title) | Out-Null
        $description=New-Label $profile.Description '#A0AAB7' 12
        $description.Margin='0,4,0,0'
        $header.Children.Add($description) | Out-Null
        $item.Header=$header
        $item.ToolTip='Replaces your selection with: ' + ($plan.Name -join ', ') + '.'
        [Windows.Automation.AutomationProperties]::SetName($item,$profile.Name + ' profile, ' + $plan.Count + ' apps')
        $item.Add_Click({ param($sender,$eventArgs) Apply-Profile ([string]$sender.Tag) })
        $profileMenu.Items.Add($item) | Out-Null
        $profileItems[$profile.Key]=$item
    }
    $ui.Profiles.Add_Click({ $profileMenu.IsOpen=$true })
    $userProfileMenu=New-Object Windows.Controls.ContextMenu
    $userProfileMenu.Resources=$window.Resources
    $userProfileMenu.PlacementTarget=$ui.UserProfiles
    $userProfileMenu.Placement='Bottom'
    foreach ($action in @(@('Export','Save current selection...'),@('Import','Load saved profile...'))) {
        $item=New-Object Windows.Controls.MenuItem
        $item.Header=$action[1]
        $ui[$action[0]]=$item
        $userProfileMenu.Items.Add($item) | Out-Null
    }
    $ui.UserProfiles.Add_Click({
        $ui.Export.IsEnabled=($selected.Count -gt 0)
        $userProfileMenu.IsOpen=$true
    })
    function Save-UserProfile([string]$Path) {
        if ($selected.Count -eq 0) { throw 'Select at least one app before saving a profile.' }
        @{Version=1; Apps=@($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key })} | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    }
    function Load-UserProfile([string]$Path) {
        if ((Get-Item -LiteralPath $Path -ErrorAction Stop).Length -gt 65536) { throw 'The profile file is too large.' }
        $savedProfile=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($savedProfile.Version -ne 1 -or $null -eq $savedProfile.Apps) { throw 'Invalid profile.' }
        $plan=@(Get-Plan @($savedProfile.Apps))
        Set-Selection @($plan | ForEach-Object { $_.Key })
        $ui.Status.Text='User profile loaded. Review your apps before installing.'
    }
    $ui.OpenLogs.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $logDir) })
    $saveProfileAction={
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter = 'First Install profile (*.json)|*.json'; $dialog.FileName = 'my-setup.json'
        if ($dialog.ShowDialog($window)) {
            try {
                Save-UserProfile $dialog.FileName
                Add-Log 'Profile saved.'
            } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'Could not save profile') | Out-Null }
        }
    }
    $ui.Export.Add_Click($saveProfileAction)
    $ui.SaveSetup.Add_Click($saveProfileAction)
    $ui.Import.Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog; $dialog.Filter = 'First Install profile (*.json)|*.json'
        if ($dialog.ShowDialog($window)) {
            try {
                Load-UserProfile $dialog.FileName
                Add-Log 'Profile imported.'
            } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'Could not import profile') | Out-Null }
        }
    })
    function Confirm-Plan($Plan) {
        $dialog = New-Object Windows.Window
        $dialog.WindowStyle='SingleBorderWindow'
        $dialog.Add_SourceInitialized({ [FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($dialog).Handle) | Out-Null })
        $dialogChrome=New-Object Windows.Shell.WindowChrome
        $dialogChrome.CaptionHeight=48; $dialogChrome.ResizeBorderThickness='6'
        $dialogChrome.GlassFrameThickness='0'; $dialogChrome.UseAeroCaptionButtons=$false
        [Windows.Shell.WindowChrome]::SetWindowChrome($dialog,$dialogChrome)
        $dialog.Icon=$window.Icon; $dialog.Title='Review installation'; $dialog.Width=580; $dialog.Height=570; $dialog.Owner=$window
        $dialog.WindowStartupLocation='CenterOwner'; $dialog.Background='#171A20'; $dialog.Foreground='#F3F5F7'
        $dialog.MinWidth=540; $dialog.MinHeight=540; $dialog.FontSize=13
        $dialog.FontFamily='Segoe UI'; $dialog.Resources=$window.Resources
        $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='24'; $dialog.Content=$dock
        $title=New-Label 'Ready to install?' '#F3F5F7' 23; $title.Margin='0,0,0,18'
        [Windows.Controls.DockPanel]::SetDock($title,'Top'); $dock.Children.Add($title) | Out-Null
        $bottom=New-Object Windows.Controls.StackPanel
        [Windows.Controls.DockPanel]::SetDock($bottom,'Bottom'); $dock.Children.Add($bottom) | Out-Null
        $info=New-Label 'Guided apps open their official websites for manual installation. For Peace, install Equalizer APO first, choose your audio device and follow any restart instructions before setting up Peace.' '#A0AAB7' 12
        $info.Margin='0,16,0,16'; $bottom.Children.Add($info) | Out-Null
        $agree=New-Object Windows.Controls.CheckBox; $agree.Content='I accept the app licenses and WinGet source terms.'; $agree.Foreground='#F3F5F7'; $agree.Margin='0,0,0,16'
        $bottom.Children.Add($agree) | Out-Null
        $go=New-Object Windows.Controls.Button; $go.Content='Start installation'; $go.IsEnabled=$false; $go.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentBrush'); $go.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'AccentForegroundBrush')
        $agree.Add_Checked({ $go.IsEnabled=$true }); $agree.Add_Unchecked({ $go.IsEnabled=$false })
        $go.Add_Click({ $dialog.DialogResult=$true }); $bottom.Children.Add($go) | Out-Null
        $back=New-Object Windows.Controls.Button; $back.Content='Back'; $back.IsCancel=$true; $back.Margin='0,8,8,0'
        $back.Add_Click({ $dialog.DialogResult=$false }); $bottom.Children.Add($back) | Out-Null
        $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'
        $list=New-Object Windows.Controls.StackPanel; $scroll.Content=$list
        foreach ($app in $Plan) {
            $mode=if ($app.Ids.Count) { 'Automatic' } else { 'Guided' }
            $label=New-Label ($app.Name + '  ·  ' + $mode) '#D7DFE8' 14; $label.Margin='0,5'
            $list.Children.Add($label) | Out-Null
        }
        $dock.Children.Add($scroll) | Out-Null
        if ($SmokeTest) {
            $dialog.Add_ContentRendered({
                if ($agree.IsChecked -or $go.IsEnabled) { throw 'Installation must require explicit consent.' }
                if ([Windows.Shell.WindowChrome]::GetWindowChrome($dialog).GlassFrameThickness.Top -ne 0) { throw 'Review dialog chrome mismatch.' }
                $dialog.DialogResult=$false
            })
        }
        return $dialog.ShowDialog() -eq $true
    }
    $worker = {
        param($Plan,$Winget,$Events,$Control,$LogDir)
        $ErrorActionPreference='Stop'
        function Emit($Type,$Key,$Text) { $Events.Enqueue(@{Type=$Type;Key=$Key;Text=$Text}) }
        try {
            foreach ($app in $Plan) {
                if ($Control.Stop) { break }
                Emit 'status' $app.Key 'Preparing…'
                if ($app.Url) {
                    Emit 'url' $app.Key $app.Url
                    Emit 'status' $app.Key 'Manual install pending · official website'
                    Emit 'progress' $app.Key ''
                    continue
                }
                $failed=$false; $restart=$false; $allExisting=$true
                foreach ($id in $app.Ids) {
                    Emit 'status' $app.Key ('Installing ' + $id + '…')
                    $out=Join-Path $LogDir (([guid]::NewGuid().ToString('N'))+'.out.log')
                    $err=$out+'.err.log'
                    try {
                        # All arguments come from the embedded catalogue, never from imported profiles.
                        $arguments=@('install','--id',$id,'--exact','--source','winget','--no-upgrade','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
                        $process=Start-Process -FilePath $Winget -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
                        $null=$process.Handle
                        $process.WaitForExit()
                        $code=$process.ExitCode
                        $process.Dispose()
                        foreach ($path in @($out,$err)) {
                            if (Test-Path -LiteralPath $path) { Emit 'log' $app.Key (Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue) }
                        }
                        $hex='{0:X8}' -f ([long]$code -band 4294967295)
                        if ($code -eq 0) { $allExisting=$false }
                        elseif ($hex -eq '8A15002B') { }
                        elseif ($code -eq 3010) { $restart=$true; $allExisting=$false }
                        else { $failed=$true; Emit 'log' $app.Key ("$id : code $code / 0x$hex") }
                    } catch { $failed=$true; Emit 'log' $app.Key $_.Exception.Message }
                }
                $state=if ($failed) { 'Failed · see logs' } elseif ($restart) { 'Completed · restart required' } elseif ($allExisting) { 'Already installed / no upgrade' } else { 'Completed' }
                Emit 'status' $app.Key $state
                Emit 'progress' $app.Key ''
            }
        } catch { Emit 'error' '' $_.Exception.Message }
        finally { Emit 'done' '' '' }
    }
    function Set-Busy([bool]$Value) {
        $script:busy=$Value
        foreach ($name in @('UserProfiles','Profiles','ClearSelection','Import')) { $ui[$name].IsEnabled = -not $Value }
        if ($Value) { $profileMenu.IsOpen=$false; $userProfileMenu.IsOpen=$false }
        foreach ($check in $checks.Values) { $check.IsEnabled = -not $Value }
        $ui.Cancel.Visibility=if ($Value) { 'Visible' } else { 'Collapsed' }
        $ui.Cancel.IsEnabled=$Value
        Update-Selection
    }
    $ui.Install.Add_Click({
        if ($script:busy) { return }
        $plan=@(Get-Plan @($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key }))
        if (-not $plan.Count -or -not (Confirm-Plan $plan)) { return }
        if (-not $winget -and @($plan | Where-Object { $_.Ids.Count -gt 0 }).Count) {
            [Windows.MessageBox]::Show($window,'Install or update App Installer in the Microsoft Store, then reopen First Install.','WinGet missing') | Out-Null
            Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
            return
        }
        $script:events=New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $script:control=[hashtable]::Synchronized(@{Stop=$false})
        $script:total=$plan.Count; $script:completed=0
        $statuses.Clear(); foreach ($app in $plan) { $statuses[$app.Key]='Queued' }
        $ui.Progress.Value=0; $ui.Status.Text='Installation in progress…'
        Set-Busy $true
        try {
            $script:job=[PowerShell]::Create()
            $null=$script:job.AddScript($worker.ToString()).AddArgument($plan).AddArgument($winget).AddArgument($script:events).AddArgument($script:control).AddArgument($logDir)
            $script:async=$script:job.BeginInvoke()
            Add-Log ('Queue started: ' + ($plan.Name -join ', '))
        } catch {
            Add-Log $_.Exception.Message
            if ($script:job) { $script:job.Dispose(); $script:job=$null }
            Set-Busy $false
            $ui.Status.Text='Could not start. See the logs for details.'
        }
    })
    $ui.Cancel.Add_Click({
        if ($script:busy) { $script:control.Stop=$true; $ui.Cancel.IsEnabled=$false; $ui.Status.Text='Stopping after the current app.'; Add-Log 'Stop requested. Waiting for the current installer.' }
    })
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if (-not $script:job) { return }
        $event=$null
        while ($script:events.TryDequeue([ref]$event)) {
            switch ($event.Type) {
                'status' { $statuses[$event.Key]=$event.Text; Add-Log ($byKey[$event.Key].Name + ': ' + $event.Text); Update-Selection }
                'log' { if ($event.Text) { Add-Log $event.Text } }
                'error' { Add-Log $event.Text; $ui.Status.Text='Something went wrong. See the logs for details.' }
                'url' {
                    try { Start-Process $event.Text }
                    catch { Add-Log ('Could not open: ' + $event.Text) }
                }
                'progress' { $script:completed++; $ui.Progress.Value=100*$script:completed/$script:total; $ui.Status.Text="$script:completed of $script:total processed" }
            }
        }
        if ($script:async.IsCompleted -and $script:events.IsEmpty) {
            try { $script:job.EndInvoke($script:async) | Out-Null; foreach ($err in $script:job.Streams.Error) { Add-Log $err.ToString() } }
            catch { Add-Log $_.Exception.Message }
            $script:job.Dispose(); $script:job=$null
            foreach ($key in @($statuses.Keys)) { if ($statuses[$key] -eq 'Queued') { $statuses[$key]='Not started' } elseif ($statuses[$key] -like 'Installing*' -or $statuses[$key] -like 'Preparing*') { $statuses[$key]='Failed · operation interrupted' } }
            $failed=@($statuses.Values | Where-Object { $_ -like 'Failed*' }).Count
            $manual=@($statuses.Values | Where-Object { $_ -like 'Manual*' }).Count
            $ui.Status.Text="Queue finished · $failed failed · $manual manual installs pending."
            if ($script:control.Stop) { $ui.Status.Text='Queue stopped after the current app. Review the results.' }
            Set-Busy $false
        }
    })
    function Update-CardLayout {
        $available=$ui.LibraryScroll.ViewportWidth
        if ($available -le 0 -or [double]::IsInfinity($available)) { return }
        # Use the measured viewport, never the size of the children being resized.
        # One spare DIP per slot avoids an extra wrap at fractional display scaling.
        $columns=[Math]::Max(1,[Math]::Min(5,[Math]::Floor(($available+12)/232)))
        $slot=[Math]::Floor($available/$columns)-1
        $ui.Cards.ItemWidth=$slot
        foreach ($check in $checks.Values) { $check.Width=[Math]::Max(100,$slot-12) }
    }
    $ui.LibraryScroll.Add_ScrollChanged({
        param($sender,$scrollEvent)
        if ($scrollEvent.ViewportWidthChange -ne 0) { Update-CardLayout }
    })
    $window.Add_Loaded({ Update-CardLayout })
    $window.Add_Closing({
        param($sender,$eventArgs)
        if ($script:busy) {
            $eventArgs.Cancel=$true
            $script:control.Stop=$true
            $ui.Status.Text='Wait for the current installer to finish, then close this window.'
            $ui.Cancel.IsEnabled=$false
        }
    })
    Update-Selection; Update-Filter
    if ($SmokeTest) {
        Set-Selection @('peace','ts3')
        if ($selected.Count -ne 3) { throw 'Selection did not add the dependency.' }
        $ui.Search.Text='TeamSpeak'
        if ($checks['ts3'].Visibility -ne 'Visible' -or $checks['apo'].Visibility -ne 'Collapsed') { throw 'Invalid search results.' }
        $ui.ClearSearch.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($ui.Search.Text -ne '' -or $selected.Count -ne 3) { throw 'Clearing search changed the selection.' }
        Apply-Profile 'gaming'
        if ($selected.Count -ne 6 -or -not $selected.ContainsKey('ts3') -or -not $selected.ContainsKey('extra_playnite')) { throw 'Invalid Gaming profile.' }
        foreach ($sample in @('#0078D4','#D13438','#001020','#FFFF99')) {
            Set-AccentPalette ([Windows.Media.ColorConverter]::ConvertFromString($sample))
            if ($ui.Install.Background.Color.ToString() -ne ('#FF'+$sample.Substring(1))) { throw 'Accent did not update the primary button.' }
            $lum=Get-Luminance $ui.Install.Background.Color
            $fgLum=Get-Luminance $ui.Install.Foreground.Color
            if (([Math]::Max($lum,$fgLum)+0.05)/([Math]::Min($lum,$fgLum)+0.05) -lt 4.5) { throw 'Insufficient accent button contrast.' }
        }
        Update-WindowsAccent
        if ($ui.Install.Background.Color -ne (Get-WindowsAccent)) { throw 'Windows accent mismatch.' }
        Set-Selection @('affinity','peace','extra_vlc')
        $ui.Search.Text='LocalSend'
        $script:removeButtons['affinity'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.ContainsKey('affinity') -or $checks['affinity'].IsChecked -or $ui.Search.Text -ne 'LocalSend') { throw 'Setup removal did not preserve the filtered view.' }
        $script:removeButtons['apo'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.ContainsKey('peace') -or $selected.ContainsKey('apo') -or $selected.Count -ne 1) { throw 'Setup removal left a broken dependency.' }
        Set-Busy $true
        if ($ui.SaveSetup.IsEnabled -or $script:removeButtons['extra_vlc'].IsEnabled) { throw 'Setup actions enabled while installing.' }
        Set-Busy $false
        Set-Selection @()
        if ($ui.SaveSetup.IsEnabled) { throw 'Empty setup can be saved.' }
        $ui.Search.Text=''
        $testProfile=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()+'.json')
        try {
            Set-Selection @('peace','ts3')
            Save-UserProfile $testProfile
            Set-Selection @('extra_vlc')
            Load-UserProfile $testProfile
            if ($selected.Count -ne 3 -or -not $selected.ContainsKey('peace') -or -not $selected.ContainsKey('apo') -or -not $selected.ContainsKey('ts3')) { throw 'User profile round trip failed.' }
            '{"Version":1,"Apps":["unknown-app"]}' | Set-Content -LiteralPath $testProfile
            $rejected=$false
            try { Load-UserProfile $testProfile } catch { $rejected=$true }
            if (-not $rejected -or $selected.Count -ne 3) { throw 'Invalid user profile changed selection.' }
        } finally { Remove-Item -LiteralPath $testProfile -ErrorAction SilentlyContinue }
        if ($window.FindName('Creator') -or $window.FindName('Gaming')) { throw 'Old profile shortcuts remain.' }
        if ($userProfileMenu.Items.Count -ne 2) { throw 'Missing user profile actions.' }
        foreach ($profile in $profiles) {
            $profileItems[$profile.Key].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
            $expectedPlan=@(Get-Plan @($profile.Apps))
            if ($selected.Count -ne $expectedPlan.Count) { throw 'Profile did not replace the selection.' }
            foreach ($entry in $expectedPlan) { if (-not $selected.ContainsKey($entry.Key)) { throw 'Profile selection is incomplete.' } }
            if ($script:busy -or $script:job) { throw 'Applying a profile started an installation.' }
        }
        $ui.ClearSelection.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.Count -ne 0 -or $ui.Install.IsEnabled) { throw 'Clearing selection did not disable installation.' }
        $checks['peace'].IsChecked=$true
        $checks['peace'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.Count -ne 2 -or -not $selected.ContainsKey('apo')) { throw 'Selecting Peace did not add APO.' }
        $checks['apo'].IsChecked=$false
        $checks['apo'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.Count -ne 0) { throw 'Removing APO did not remove Peace.' }
        $ui.Search.Text='LocalSend'
        if ($checks['extra_localsend'].Visibility -ne 'Visible' -or $checks['ts3'].Visibility -ne 'Collapsed') { throw 'New app search failed.' }
        $ui.Search.Clear()
        foreach ($button in $ui.Categories.Children) {
            if ($button.Tag -eq 'Security') { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
        }
        if ($checks['extra_keepassxc'].Visibility -ne 'Visible' -or $checks['extra_vlc'].Visibility -ne 'Collapsed') { throw 'New category filter failed.' }
        foreach ($button in $ui.Categories.Children) {
            if ($button.Tag -eq 'All apps') { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
        }
        $window.Add_ContentRendered({
            function Wait-WindowMessages {
                $frame=New-Object Windows.Threading.DispatcherFrame
                $pulse=New-Object Windows.Threading.DispatcherTimer
                $pulse.Interval=[TimeSpan]::FromMilliseconds(100)
                $pulse.Add_Tick({ $pulse.Stop(); $frame.Continue=$false })
                $pulse.Start()
                [Windows.Threading.Dispatcher]::PushFrame($frame)
            }
            $chrome=[Windows.Shell.WindowChrome]::GetWindowChrome($window)
            if ($chrome.CaptionHeight -ne 38 -or $chrome.GlassFrameThickness.Top -ne 0) { throw 'Dark window chrome not applied.' }
            $windowsBuild=[int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
            if ($windowsBuild -ge 22000 -and $script:cornerResult -ne 0) { throw "Windows 11 rounded-corner request failed: $script:cornerResult" }
            if ($script:cornerResult -eq 0 -and [FirstInstallWindow]::ReadCornerPreference([Windows.Interop.WindowInteropHelper]::new($window).Handle) -ne 2) { throw 'Native rounded-corner preference not applied.' }
            $originalWidth=$window.Width
            foreach ($testWidth in @(980,1060,1240,1500)) {
                $window.Width=$testWidth
                Wait-WindowMessages
                $window.UpdateLayout()
                Update-CardLayout
                $window.UpdateLayout()
                $visible=@($ui.Cards.Children | Where-Object { $_.Visibility -eq 'Visible' })
                $first=$visible[0].TranslatePoint([Windows.Point]::new(0,0),$ui.Cards)
                $second=$visible[1].TranslatePoint([Windows.Point]::new(0,0),$ui.Cards)
                if ([Math]::Abs($first.Y-$second.Y) -gt 1 -or $second.X -le $first.X) { throw "Grid collapsed to a list at width $testWidth." }
                if ($visible[1].ActualWidth -lt 200) { throw "Cards are too narrow at width $testWidth." }
                if ($PreviewPath -and $testWidth -eq 980) {
                    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                    $bitmap.Render($window)
                    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                    $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'narrow.png'))
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                }
            }
            $window.Width=$originalWidth
            Wait-WindowMessages
            $window.UpdateLayout()
            # Filtering must compact the actual grid, not just hide its contents.
            Set-Selection @('peace','extra_vlc')
            foreach ($categoryButton in $ui.Categories.Children) {
                $categoryButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $window.UpdateLayout()
                Update-CardLayout
                $window.UpdateLayout()
                $expected=@($catalog | Where-Object { $categoryButton.Tag -eq 'All apps' -or $_.Category -eq $categoryButton.Tag })
                if ($ui.Cards.Children.Count -ne $expected.Count) { throw "Hidden cards still occupy grid slots in $($categoryButton.Tag)." }
                if ($expected.Count) {
                    $position=$ui.Cards.Children[0].TranslatePoint([Windows.Point]::new(0,0),$ui.Cards)
                    if ([Math]::Abs($position.X) -gt 1 -or [Math]::Abs($position.Y) -gt 1) { throw 'Filtered grid does not start at the first cell.' }
                    for ($i=0;$i -lt $expected.Count;$i++) {
                        if ($ui.Cards.Children[$i].Tag -ne $expected[$i].Key) { throw 'Filtering changed catalog order.' }
                    }
                }
            }
            foreach ($categoryButton in $ui.Categories.Children) {
                if ($categoryButton.Tag -eq 'All apps') { $categoryButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
            }
            $ui.Search.Text='LocalSend'
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne 1 -or $ui.Cards.Children[0].Tag -ne 'extra_localsend') { throw 'Search results did not compact.' }
            $ui.Search.Text='__no_matching_apps__'
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne 0 -or $ui.Empty.Visibility -ne 'Visible') { throw 'Empty search left grid slots behind.' }
            $ui.Search.Clear()
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne $catalog.Count -or $selected.Count -ne 3 -or -not $checks['peace'].IsChecked -or -not $checks['apo'].IsChecked -or -not $checks['extra_vlc'].IsChecked) { throw 'Filtering lost selected apps or dependencies.' }
            Set-Selection @()
            $ui.LibraryScroll.UpdateLayout()
            $bar=$ui.LibraryScroll.Template.FindName('PART_VerticalScrollBar',$ui.LibraryScroll)
            $bar.ApplyTemplate() | Out-Null
            $track=$bar.Template.FindName('PART_Track',$bar)
            if ($null -eq $track -or $bar.ActualWidth -ne 12) { throw 'Minimal scrollbar template not applied.' }
            if ($track.Thumb.ActualHeight -lt 48) { throw "Scrollbar thumb is too short: $($track.Thumb.ActualHeight)." }
            $track.Thumb.ApplyTemplate() | Out-Null
            $handle=$track.Thumb.Template.FindName('Handle',$track.Thumb)
            if ($null -eq $handle -or $handle.Background.Color -ne $window.Resources['AccentMutedBrush'].Color) { throw 'Scrollbar palette mismatch.' }
            [Windows.Controls.Primitives.ScrollBar]::PageDownCommand.Execute($null,$bar)
            $ui.LibraryScroll.UpdateLayout()
            if ($ui.LibraryScroll.VerticalOffset -le 0) { throw 'Scrollbar page-down failed.' }
            $previousOffset=$ui.LibraryScroll.VerticalOffset
            $track.Thumb.RaiseEvent([Windows.Controls.Primitives.DragDeltaEventArgs]::new(0,12))
            $ui.LibraryScroll.UpdateLayout()
            if ($ui.LibraryScroll.VerticalOffset -le $previousOffset) { throw 'Scrollbar drag failed.' }
            $ui.LibraryScroll.ScrollToBottom()
            $ui.LibraryScroll.UpdateLayout()
            if ([Math]::Abs($ui.LibraryScroll.VerticalOffset-$ui.LibraryScroll.ScrollableHeight) -gt 1) { throw 'The last applications cannot be reached.' }
            $ui.LibraryScroll.ScrollToTop()
            $ui.LibraryScroll.UpdateLayout()
            $ui.Profiles.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if (-not $profileMenu.IsOpen -or $profileMenu.Items.Count -ne 8 -or $profileMenu.Background.Color.ToString() -ne '#FF171A20') { throw 'Profile menu did not open with the app theme.' }
            if ($PreviewPath) {
                $menuImage=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($profileMenu.ActualWidth),[int][Math]::Ceiling($profileMenu.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $menuImage.Render($profileMenu)
                $menuEncoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $menuEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($menuImage))
                $menuStream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'profiles.png'))
                try { $menuEncoder.Save($menuStream) } finally { $menuStream.Dispose() }
            }
            $profileMenu.IsOpen=$false
            $ui.UserProfiles.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $window.UpdateLayout()
            if (-not $userProfileMenu.IsOpen -or $userProfileMenu.Background.Color.ToString() -ne '#FF171A20') { throw 'User profiles menu failed to open with the app theme.' }
            $userProfileMenu.IsOpen=$false
            Wait-WindowMessages
            $window.Activate() | Out-Null
            $ui.MaximizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if ($window.WindowState -ne 'Maximized' -or $ui.MaximizeWindow.ToolTip -ne 'Restore') { throw "Maximize button failed: state=$($window.WindowState), tooltip=$($ui.MaximizeWindow.ToolTip)." }
            $ui.MaximizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if ($window.WindowState -ne 'Normal') { throw 'Restore button failed.' }
            $ui.MinimizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if ($window.WindowState -ne 'Minimized') { throw 'Minimize button failed.' }
            $window.WindowState='Normal'
            Wait-WindowMessages
            if (Confirm-Plan @(Get-Plan @('peace','extra_vlc'))) { throw 'Review test must cancel.' }
            $window.UpdateLayout()
            if ($PreviewPath) {
                $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window)
                $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream=[IO.File]::Create($PreviewPath)
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            $ui.CloseWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        })
        $window.ShowDialog() | Out-Null
        'PASS: 253 apps, packed category/search grids, preserved selection, setup remove buttons and save availability, Windows accent updates and contrast, user profile save/load and invalid-file rejection, 8 profiles, themed profile menu, grid widths, 48-DIP thumb, scrolling to the last app and window controls.'
        return
    }
    $timer.Start()
    $window.ShowDialog() | Out-Null
    $timer.Stop()
} catch {
    if ($SmokeTest) { throw }
    [Windows.MessageBox]::Show($_.Exception.ToString(),'First Install — error','OK','Error') | Out-Null
    exit 1
}
