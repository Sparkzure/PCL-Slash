' 2026-11-05 PCL-Slash 原创修改：增加显式只读 PCL2 迁入入口与进度提示（GPL-3.0-only）。
Public Class PageSetupSystem

    Public Sub New()
        InitializeComponent()
        TextLauncherUpdateCustomSource.ValidateRules.Add(New ValidateFunc(AddressOf ValidateLauncherUpdateCustomSource))
    End Sub

    Private Sub PageSetupSystem_Loaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded

        '重复加载部分
        PanBack.ScrollToHome()

        '非重复加载部分
        Static IsLoaded As Boolean = False
        If IsLoaded Then Return
        IsLoaded = True

        AniControlEnabled += 1
        Reload()
        SliderLoad()
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

    '滑动条
    Private Sub SliderLoad()
        SliderDownloadThread.GetHintText = Function(v) v + 1
        SliderDownloadSpeed.GetHintText =
        Function(v)
            Select Case v
                Case Is <= 14
                    Return (v + 1) * 0.1 & " M/s"
                Case Is <= 31
                    Return (v - 11) * 0.5 & " M/s"
                Case Is <= 41
                    Return (v - 21) & " M/s"
                Case Else
                    Return "无限制"
            End Select
        End Function
        SliderDebugAnim.GetHintText = Function(v) If(v > 29, "关闭", (v / 10 + 0.1) & "x")
    End Sub
    Private Sub SliderDownloadThread_PreviewChange(sender As Object, e As RouteEventArgs) Handles SliderDownloadThread.PreviewChange
        If SliderDownloadThread.Value < 100 Then Return
        If Not Settings.Get(Of Boolean)("HintDownloadThread") Then
            Settings.Set("HintDownloadThread", True)
            MyMsgBox("如果设置过多的下载线程，可能会导致下载时出现非常严重的卡顿。" & vbCrLf &
                     "一般设置 64 线程即可满足大多数下载需求，除非你知道你在干什么，否则不建议设置更多的线程数！", "警告", "我知道了", IsWarn:=True)
        End If
    End Sub

    '调试模式
    Private Sub CheckDebugMode_Change() Handles CheckDebugMode.Change
        If AniControlEnabled = 0 Then Hint("部分调试信息将在刷新或启动器重启后切换显示！",, False)
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

    Private Sub BtnSystemSettingExp_Click(sender As Object, e As MouseButtonEventArgs) Handles BtnSystemSettingExp.Click
        Hint("该功能尚在开发中！")
    End Sub
    Private Sub BtnSystemSettingImp_Click(sender As Object, e As MouseButtonEventArgs) Handles BtnSystemSettingImp.Click
        Hint("该功能尚在开发中！")
    End Sub

    Private Async Sub BtnSystemPcl2Migration_Click(sender As Object, e As MouseButtonEventArgs) Handles BtnSystemPcl2Migration.Click
        If Pcl2Migration.IsRunning Then Return
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
