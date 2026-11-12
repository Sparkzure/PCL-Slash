' 增加显式只读 PCL2 迁入入口与进度提示。
' 从 PageSetupSystem 移入启动器设置，原实现来源保持不变。
Public Class PageSetupLauncher

    Public Sub New()
        InitializeComponent()
        TextLauncherUpdateCustomSource.ValidateRules.Add(New ValidateFunc(AddressOf ValidateLauncherUpdateCustomSource))
    End Sub

    Private Sub PageSetupLauncher_Loaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded

        '重复加载部分
        PanBack.ScrollToHome()

        '非重复加载部分
        Static IsLoaded As Boolean = False
        If IsLoaded Then Return
        IsLoaded = True

        AniControlEnabled += 1
        Reload()
        AniControlEnabled -= 1

    End Sub
    Public Sub Reload()
        SettingService.RefreshSettings(Me)
        RefreshLauncherUpdateSourceUi()
    End Sub
    Public Sub Reset()
        Try
            SettingService.ResetSettings(Me)
            Logger.Info("已初始化启动器页设置")
            Hint("已初始化启动器页设置！", HintType.Green, False)
        Catch ex As Exception
            Logger.Error(ex, "初始化启动器页设置失败", LogBehavior.Alert)
        End Try
        Reload()
    End Sub

    '手动更新
    Private Sub ComboLauncherUpdateSource_SelectionChanged() Handles ComboLauncherUpdateSource.SelectionChanged
        RefreshLauncherUpdateSourceUi()
    End Sub
    Private Sub RefreshLauncherUpdateSourceUi()
        If PanLauncherUpdateCustomSource Is Nothing Then Return
        PanLauncherUpdateCustomSource.Visibility = If(ComboLauncherUpdateSource.SelectedIndex = 2, Visibility.Visible, Visibility.Collapsed)
    End Sub

    Private Sub BtnSystemUpdate_Click(sender As Object, e As EventArgs) Handles BtnSystemUpdate.Click
        ShowLauncherUpdateDialog()
    End Sub
    ''' <summary>
    ''' 启动器是否已经是最新版？
    ''' 若返回 Nothing，则代表尚未获取有效的 Release 信息。
    ''' </summary>
    Public Shared Function IsLauncherNewest() As Boolean?
        Return IsLauncherLatestRelease()
    End Function

#Region "导出 / 导入设置"

    '普通配置 ZIP 导入导出，排除加密数据。
    Private Async Sub BtnSystemSettingExp_Click(sender As Object, e As MouseButtonEventArgs) Handles BtnSystemSettingExp.Click
        If Pcl2Migration.IsRunning OrElse LauncherSettingsArchive.IsRunning Then Return
        If Not CanTransferSettings("导出") Then Return
        If MyMsgBox(LauncherSettingsArchive.ScopeDescription & vbCrLf & vbCrLf &
                    "将导出为一个 ZIP 压缩包。自定义主页、变量及启动参数可能包含个人信息，分享前请自行检查。",
                    "导出启动器配置", "选择保存位置", "取消") <> 1 Then Return
        Try
            Dim Target = Dialogs.SaveFile("保存启动器配置", $"PCL-Slash-设置-{Date.Now:yyyyMMdd-HHmmss}.zip", filter:={("zip", "PCL-Slash 配置压缩包")})
            If String.IsNullOrEmpty(Target) Then Return
            If Not CanTransferSettings("导出") Then Return
            LauncherSettingsArchive.IsRunning = True
            SetMigrationUiBusy(True)
            BtnSystemSettingExp.Text = "正在导出…"
            Await Task.Run(Sub() LauncherSettingsArchive.ExportArchive(Target))
            MyMsgBox("启动器配置已导出。" & vbCrLf & Target & vbCrLf & vbCrLf & "账号及其他加密配置未包含在压缩包内。", "导出完成")
        Catch ex As Exception
            Logger.Error(ex, "导出启动器配置失败", LogBehavior.Alert)
        Finally
            LauncherSettingsArchive.IsRunning = False
            SetMigrationUiBusy(False)
            BtnSystemSettingExp.Text = "导出设置"
        End Try
    End Sub
    Private Async Sub BtnSystemSettingImp_Click(sender As Object, e As MouseButtonEventArgs) Handles BtnSystemSettingImp.Click
        If Pcl2Migration.IsRunning OrElse LauncherSettingsArchive.IsRunning Then Return
        If Not CanTransferSettings() Then Return
        If MyMsgBox(LauncherSettingsArchive.ScopeDescription & vbCrLf & vbCrLf &
                    "仅支持本启动器导出的配置 ZIP 压缩包。导入将覆盖包内对应的普通设置和同名资源，不删除其他资源，保留本机账号及其他加密配置。" & vbCrLf &
                    "自定义主页和启动命令可能执行操作，请仅导入可信来源的配置。完成后将关闭启动器，重新打开后生效。",
                    "导入启动器配置", "选择配置压缩包", "取消", IsWarn:=True) <> 1 Then Return
        Dim Package As LauncherSettingsArchive.ImportPackage = Nothing
        Dim Completed As Boolean = False
        Try
            Dim Source = Dialogs.SelectFile("选择启动器配置压缩包", False, filter:={({"zip"}, "PCL-Slash 配置压缩包")}).FirstOrDefault()
            If String.IsNullOrEmpty(Source) Then Return
            LauncherSettingsArchive.IsRunning = True
            SetMigrationUiBusy(True)
            BtnSystemSettingImp.Text = "正在检查…"
            Package = Await Task.Run(Function() LauncherSettingsArchive.PrepareImport(Source))
            Dim Skipped = If(Package.SkippedCount > 0, vbCrLf & $"已忽略 {Package.SkippedCount} 项加密、账号、实例或不受支持的配置。", "")
            If MyMsgBox($"已校验配置压缩包，将导入 {Package.SettingCount} 项普通配置、{Package.AssetCount} 个启动器资源文件和 {Package.InstanceCount} 个游戏实例。" & Skipped & vbCrLf & vbCrLf &
                        "包内对应的普通设置和同名启动器资源将被覆盖；游戏实例恢复到新的独立目录，不覆盖现有实例。账号、其他加密配置和本机 Java 选择保持不变。是否开始导入？",
                        "确认导入", "导入并关闭启动器", "取消", IsWarn:=True) <> 1 Then Return
            If Not CanTransferSettings() Then Return
            BtnSystemSettingImp.Text = "正在导入…"
            Dim WasMusicPaused = MusicState <> MusicStates.Play
            Await Task.Run(
                Sub()
                    Try
                        MusicSuspendForSettingsImport()
                        Package.Apply()
                    Catch
                        MusicResumeAfterSettingsImport(WasMusicPaused)
                        Throw
                    End Try
                End Sub)
            Completed = True
            FrmMain.IsSizeSaveable = False
        Catch ex As Exception
            Logger.Error(ex, "导入启动器配置失败", LogBehavior.Alert)
        Finally
            Package?.Dispose()
            If Not Completed Then
                LauncherSettingsArchive.IsRunning = False
                SetMigrationUiBusy(False)
                BtnSystemSettingImp.Text = "导入设置"
            End If
        End Try
        If Completed Then
            MyMsgBox("普通配置、启动器资源及游戏实例已导入，本机账号、其他加密配置和 Java 选择已保留。请重新打开启动器使设置生效。" & vbCrLf &
                     "导入的实例保存在 PCL\Instances 下，游戏运行资源需联网补全；Mod Loader 实例首次启动先安装组件，完成后再次点击启动。", "导入完成", "关闭启动器", ForceWait:=True)
            LauncherSettingsArchive.IsRunning = False
            FrmMain.EndProgram(False)
        End If
    End Sub

    Private Shared Function CanTransferSettings(Optional ActionText As String = "导入") As Boolean
        If HasDownloadingTask() OrElse HasRunningMinecraft OrElse McInstanceLock.IsAnyLocked Then
            Hint($"请先关闭 Minecraft 并等待其他任务完成，再{ActionText}启动器配置。", HintType.Red)
            Return False
        End If
        Return True
    End Function

    Private Async Sub BtnSystemPcl2Migration_Click(sender As Object, e As MouseButtonEventArgs) Handles BtnSystemPcl2Migration.Click
        If Pcl2Migration.IsRunning OrElse LauncherSettingsArchive.IsRunning Then Return
        If HasDownloadingTask() OrElse HasRunningMinecraft OrElse McInstanceLock.IsAnyLocked Then
            Hint("请先关闭游戏并等待其他任务完成，再迁入 PCL2。", HintType.Red)
            Return
        End If
        If MyMsgBox("迁入前请确认：" & vbCrLf &
                    "• PCL-Slash 不得与 PCL2 位于同一目录，两个目录也不能互相包含。" & vbCrLf &
                    "• PCL2 及其启动的游戏已经关闭，迁入期间不要重新打开。" & vbCrLf &
                    "• PCL-Slash 所在磁盘有足够空间容纳游戏副本和设置缓存。" & vbCrLf & vbCrLf &
                    "迁入仅对 PCL2 进行只读复制：先将相关设置复制到缓存，再转换并覆盖 PCL-Slash 的对应设置。游戏将复制到 PCL-Slash 下的独立目录，不会与 PCL2 共用实例。" & vbCrLf &
                    "主题解锁状态会一并迁入，必要时需填写原 PCL2 的识别码。迁入缓存保存在 PCL-Slash 的 PCL\Cache\PCL2Migration 下，不备份 PCL-Slash 原有设置。" & vbCrLf &
                    "加密登录信息不迁入，需要重新登录；已移除的功能不会恢复。迁入完成后将关闭 PCL-Slash，请重新打开以生效。",
                    "从 PCL2 迁入", "选择 PCL2 目录", "取消", IsWarn:=True) <> 1 Then Return
        Dim Source = Dialogs.SelectFolder("选择 PCL2 启动器所在目录", False).FirstOrDefault()
        If String.IsNullOrEmpty(Source) Then Return
        Dim RegistryPath = "Software\PCL"
        Dim Migration As Pcl2Migration = Nothing
        Dim Completed As Boolean = False
        Try
            Using Regular = Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Software\PCL", False),
                  OpenSource = Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Software\PCLDebug", False)
                If Regular Is Nothing AndAlso OpenSource IsNot Nothing Then
                    RegistryPath = "Software\PCLDebug"
                ElseIf Regular IsNot Nothing AndAlso OpenSource IsNot Nothing Then
                    Select Case MyMsgBox("检测到 PCL2 正式版和开源版两套注册表设置。请选择本次迁入使用的设置。", "选择 PCL2 设置", "正式版", "开源版", "取消")
                        Case 1
                        Case 2 : RegistryPath = "Software\PCLDebug"
                        Case Else : Return
                    End Select
                End If
            End Using
            Pcl2Migration.IsRunning = True
            SetMigrationUiBusy(True)
            BtnSystemPcl2Migration.Text = "正在检查…"
            Migration = New Pcl2Migration(Source, Paths.Base, RegistryPath)
            Dim ThemeIdentity As String = Nothing
            Do
                Dim NeedsThemeIdentity As Boolean = False
                Try
                    Await Task.Run(Sub() Migration.Prepare(ThemeIdentity))
                Catch ex As Pcl2Migration.ThemeUnlockMigrationException
                    NeedsThemeIdentity = True
                End Try
                If Not NeedsThemeIdentity Then Exit Do
                SetMigrationUiBusy(False)
                ThemeIdentity = MyMsgBoxInput("读取 PCL2 主题解锁状态",
                    "无法解密主题解锁记录，请填写原 PCL2 中显示的识别码。可在原 PCL2 的「设置 → 其他 → 启动器」中复制；请关闭 PCL2 后再继续。填写错误时可重新输入，取消将停止迁入。" & vbCrLf &
                    "该值仅用于本次主题转换，不会保存为 PCL-Slash 的识别码。",
                    ValidateRules:=New ObjectModel.Collection(Of Validate) From {New ValidateNullOrWhiteSpace}, LogResult:=False)
                If ThemeIdentity Is Nothing Then Return
                SetMigrationUiBusy(True)
            Loop
            SetMigrationUiBusy(False)
            If MyMsgBox($"将复制 {Migration.GameFolderCount} 个游戏目录，共约 {Math.Ceiling(Migration.CopyBytes / 1024 / 1024)} MB，并覆盖对应的 PCL-Slash 设置。" & vbCrLf &
                        "PCL-Slash 现有游戏实例会保留，迁入副本保存在 PCL2-Migrated 下。" & vbCrLf &
                        "对应设置将直接覆盖，不创建 PCL-Slash 原设置备份。迁入缓存：" & vbCrLf & Migration.CacheDirectory,
                        "确认迁入", "开始复制", "取消", IsWarn:=True) <> 1 Then Return
            '确认弹窗期间可能启动了其他任务，再检查一次。
            If HasDownloadingTask() OrElse HasRunningMinecraft OrElse McInstanceLock.IsAnyLocked Then Throw New InvalidOperationException("请先结束其他任务后重试迁入。")
            SetMigrationUiBusy(True)
            Dim Progress As New Progress(Of KeyValuePair(Of Double, String))(
                Sub(Value)
                    BtnSystemPcl2Migration.Text = $"迁入中 {Math.Floor(Value.Key * 100)}%"
                    BtnSystemPcl2Migration.ToolTip = Value.Value
                End Sub)
            Dim Reporter As IProgress(Of KeyValuePair(Of Double, String)) = Progress
            Dim LastReport = Stopwatch.StartNew()
            Await Task.Run(Sub() Migration.Execute(
                Sub(Value, Text)
                    If Value < 1 AndAlso LastReport.ElapsedMilliseconds < 150 Then Return
                    LastReport.Restart()
                    Reporter.Report(New KeyValuePair(Of Double, String)(Value, Text))
                End Sub))
            Completed = True
            FrmMain.IsSizeSaveable = False
        Catch ex As Exception
            Logger.Error(ex, "PCL2 迁入失败", LogBehavior.Alert)
        Finally
            If Not Completed Then
                SetMigrationUiBusy(False)
                BtnSystemPcl2Migration.Text = "PCL2 迁入"
                Pcl2Migration.IsRunning = False
            End If
        End Try
        If Completed Then
            MyMsgBox("PCL2 的设置和游戏已复制到 PCL-Slash，原始文件与注册表未修改。请重新打开 PCL-Slash 使设置生效，并重新登录账号。" & vbCrLf & vbCrLf &
                     "PCL2 设置副本与转换缓存：" & vbCrLf & Migration.CacheDirectory, "迁入完成", "关闭启动器", ForceWait:=True)
            Pcl2Migration.IsRunning = False
            FrmMain.EndProgram(False)
        End If
    End Sub

    Private Shared Sub SetMigrationUiBusy(Busy As Boolean)
        FrmMain.PanMain.IsEnabled = Not Busy
        FrmMain.PanLeft.IsEnabled = Not Busy
        FrmMain.PanTitle.IsEnabled = Not Busy
    End Sub

#End Region

End Class
