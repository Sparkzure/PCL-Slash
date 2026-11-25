Imports System.Windows.Threading

Public Class PageLaunchRight
    Implements IRefreshable, IDispatcherUnhandledException

    Private Sub Init() Handles Me.Loaded
        PanBack.ScrollToHome()
        PanLog.Visibility = ModeDebug.ToVisibility
        '快照版提示
        PanHint.Visibility =
            (BuildType <> BuildTypes.Release AndAlso VersionBranchMain = "Official" AndAlso
             Not Settings.Get(Of Boolean)("HintSnapshot")).ToVisibility
    End Sub

#Region "主页"

    Private Const SlashQuickStartContent As String = "
        <local:MyCard Title=""Slash快速上手"" Margin=""0,0,0,15"">
            <StackPanel Margin=""25,40,25,20"">
                <TextBlock Text=""欢迎使用 PCL-Slash"" FontSize=""18"" Foreground=""{DynamicResource ColorBrush1}"" TextWrapping=""Wrap"" Margin=""0,0,0,10"" />
                <TextBlock Text=""基于原版 PCL 的第三方分支，独立维护与发布。启动、下载和版本选择沿用原版操作。"" TextWrapping=""Wrap"" />
                <TextBlock Text=""如需关闭此预设，请前往 设置 → 个性化 → 主页，选择「空白」。"" TextWrapping=""Wrap"" Margin=""0,8,0,0"" />
                <local:MyButton Text=""主页预设设置"" EventType=""切换页面"" EventData=""Setup|SetupUI|CardCustom"" Height=""32"" Padding=""15,0"" Margin=""0,12,0,0"" HorizontalAlignment=""Left"" />
            </StackPanel>
        </local:MyCard>
        <local:MyCard Title=""1 · 迁入原版数据"" Margin=""0,0,0,15"">
            <StackPanel Margin=""25,40,25,20"">
                <TextBlock Text=""将两个启动器放在独立且互不包含的目录，关闭原版 PCL 及游戏，再到 设置 → 启动器 → PCL2 迁入。"" TextWrapping=""Wrap"" />
                <TextBlock Text=""迁入会复制设置和游戏，保留原版数据，但会覆盖 Slash 对应设置。已有设置请先导出；完成后重开 Slash 并重新登录。"" TextWrapping=""Wrap"" Margin=""0,8,0,12"" />
                <local:MyButton Text=""迁入与备份"" EventType=""切换页面"" EventData=""Setup|SetupLauncher"" Height=""32"" Padding=""15,0"" HorizontalAlignment=""Left"" ColorType=""Highlight"" />
            </StackPanel>
        </local:MyCard>
        <local:MyCard Title=""2 · 常用设置"" Margin=""0,0,0,15"">
            <StackPanel Margin=""25,40,25,12"">
                <TextBlock Text=""启动：Java、内存与启动参数。游戏功能：离线皮肤和游戏更新提示。"" TextWrapping=""Wrap"" />
                <TextBlock Text=""下载：镜像与下载策略。个性化：主题、背景、主页与功能隐藏。"" TextWrapping=""Wrap"" Margin=""0,8,0,0"" />
                <TextBlock Text=""F12 可临时显示隐藏功能。"" TextWrapping=""Wrap"" Margin=""0,8,0,12"" />
                <WrapPanel>
                    <local:MyButton Text=""启动设置"" EventType=""切换页面"" EventData=""Setup|SetupLaunch"" Height=""32"" Padding=""15,0"" Margin=""0,0,10,8"" />
                    <local:MyButton Text=""游戏功能"" EventType=""切换页面"" EventData=""Setup|SetupGame"" Height=""32"" Padding=""15,0"" Margin=""0,0,10,8"" />
                    <local:MyButton Text=""下载设置"" EventType=""切换页面"" EventData=""Setup|SetupDownload"" Height=""32"" Padding=""15,0"" Margin=""0,0,10,8"" />
                    <local:MyButton Text=""个性化"" EventType=""切换页面"" EventData=""Setup|SetupUI"" Height=""32"" Padding=""15,0"" Margin=""0,0,0,8"" />
                </WrapPanel>
            </StackPanel>
        </local:MyCard>
        <local:MyCard Title=""3 · 备份与更新"" Margin=""0,0,0,15"">
            <StackPanel Margin=""25,40,25,12"">
                <TextBlock Text=""设置 → 启动器 可导入、导出配置、外观资源与实例整合包。备份不含账号、Java 路径、游戏本体及运行资源，恢复后需联网补全。"" TextWrapping=""Wrap"" />
                <TextBlock Text=""配置与缓存位于启动器旁的 PCL 文件夹。新版请按提示前往 Slash 发布页下载，手动更新。"" TextWrapping=""Wrap"" Margin=""0,8,0,12"" />
                <WrapPanel>
                    <local:MyButton Text=""查看更新"" EventType=""检查更新"" Height=""32"" Padding=""15,0"" Margin=""0,0,10,8"" />
                    <local:MyButton Text=""关于 Slash"" EventType=""切换页面"" EventData=""Other|OtherAbout"" Height=""32"" Padding=""15,0"" Margin=""0,0,10,8"" />
                    <local:MyButton Text=""问题反馈"" EventType=""打开网页"" EventData=""{x:Static local:ModBase.FeedbackUrl}"" Height=""32"" Padding=""15,0"" Margin=""0,0,0,8"" />
                </WrapPanel>
            </StackPanel>
        </local:MyCard>"

    ''' <summary>
    ''' 刷新主页。
    ''' </summary>
    Private Sub Refresh() Handles Me.Loaded
        RunInThread(
        Sub()
            Try
                SyncLock RefreshLock
                    RefreshReal()
                End SyncLock
            Catch ex As Exception
                Logger.Error(ex, "加载 PCL-Slash 主页自定义信息失败", If(ModeDebug, LogBehavior.Alert, LogBehavior.Toast))
            End Try
        End Sub)
    End Sub
    Private Sub RefreshReal()
        Dim Content As String = Nothing, Url As String = Nothing
        Select Case Settings.Get(Of Integer)("UiCustomType")
            Case 1
                '加载本地文件
                Logger.Info("主页自定义数据来源：本地文件")
                Content = FileUtils.TryReadAsString(Paths.Base & "PCL\Custom.xaml")
            Case 2
                '联网下载
                Url = Settings.Get(Of String)("UiCustomNet")
            Case 3
                '预设
                Logger.Info("主页预设：Slash快速上手")
                Content = SlashQuickStartContent
        End Select
        '联网下载
        If Not String.IsNullOrWhiteSpace(Url) Then
            '替换自定义变量与设置
            Url = ArgumentReplace(Url, AddressOf WebUtility.HtmlEncode)
            If Url = Settings.Get(Of String)("CacheSavedPageUrl") AndAlso FileUtils.Exists(PathTemp & "Cache\Custom.xaml") Then
                '缓存可用
                Logger.Info("主页自定义数据来源：联网缓存文件")
                Content = FileUtils.TryReadAsString(PathTemp & "Cache\Custom.xaml")
                '后台更新缓存
                OnlineLoader.Start((Url, False))
            Else
                '缓存不可用
                Logger.Info("主页自定义数据来源：联网全新下载")
                Hint("正在加载主页……")
                RunInUiWait(Sub() LoadContent(Nothing)) '在加载结束前清空页面
                Settings.Set("CacheSavedPageVersion", "")
                OnlineLoader.Start((Url, True)) '下载完成后将会再次触发更新
                Return
            End If
        End If
        '同步到 UI
        RunInUi(Sub() LoadContent(Content))
    End Sub
    Private RefreshLock As New Object

    '联网获取主页文件
    Private OnlineLoader As New LoaderTask(Of (Address As String, ShouldRefresh As Boolean), Integer)("下载主页", AddressOf OnlineLoaderSub) With {.ReloadTimeout = 10 * 60 * 1000}
    Private Sub OnlineLoaderSub(Task As LoaderTask(Of (Address As String, ShouldRefresh As Boolean), Integer))
        Dim Address As String = Task.Input.Address '#3721 中连续触发两次导致内容变化
        Dim ShouldRefresh As Boolean = Task.Input.ShouldRefresh
        Try
            '获取版本校验地址
            Dim VersionAddress As String
            If Address.Contains(".xaml") Then
                VersionAddress = Address.Replace(".xaml", ".xaml.ini")
            Else
                VersionAddress = Address.BeforeFirst("?")
                If Not VersionAddress.EndsWithF("/") Then VersionAddress += "/"
                VersionAddress += "version"
                If Address.Contains("?") Then VersionAddress += "?" & Address.AfterFirst("?")
            End If
            '校验版本
            Dim Version As String = ""
            Try
                Version = NetRequestByClientRetry(VersionAddress)
                If Version.Length > 1000 Then Throw New Exception($"获取的主页版本过长（{Version.Length} 字符）")
                Dim CurrentVersion As String = Settings.Get(Of String)("CacheSavedPageVersion")
                If Version <> "" AndAlso CurrentVersion <> "" AndAlso Version = CurrentVersion Then
                    Logger.Info($"当前缓存的主页已为最新，当前版本：{Version}，检查源：{VersionAddress}")
                    Return
                End If
                Logger.Info($"需要下载联网主页，当前版本：{Version}，检查源：{VersionAddress}")
            Catch exx As Exception
                Logger.Warn(exx, $"联网获取主页版本失败")
                Logger.Info($"无法检查联网主页版本，将直接下载，检查源：{VersionAddress}")
            End Try
            '实际下载
            Dim FileContent As String = NetRequestByClientRetry(Address)
            Logger.Info($"已联网下载主页，内容长度：{FileContent.Length}，来源：{Address}")
            Settings.Set("CacheSavedPageUrl", Address)
            Settings.Set("CacheSavedPageVersion", Version)
            FileUtils.Write(PathTemp & "Cache\Custom.xaml", FileContent)
            '若内容变更则要求刷新
            If LoadedContentHash <> FileContent.GetStableHashCode() AndAlso ShouldRefresh Then Refresh()
        Catch ex As Exception
            Logger.Error(ex, $"下载主页失败（{Address}）", If(ModeDebug, LogBehavior.Alert, LogBehavior.Toast))
        End Try
    End Sub

    ''' <summary>
    ''' 立即强制刷新主页。
    ''' 必须在 UI 线程调用。
    ''' </summary>
    Public Sub ForceRefresh() Implements IRefreshable.Refresh
        Logger.Info("要求强制刷新主页")
        ClearCache()
        '实际的刷新
        If FrmMain.PageCurrent.Page = FormMain.PageType.Launch Then
            PanBack.ScrollToHome()
            Refresh()
        Else
            FrmMain.PageChange(FormMain.PageType.Launch)
        End If
    End Sub

    ''' <summary>
    ''' 清空主页缓存信息。
    ''' </summary>
    Private Sub ClearCache()
        LoadedContentHash = Nothing
        OnlineLoader.Input = ("", True)
        Settings.Set("CacheSavedPageUrl", "")
        Settings.Set("CacheSavedPageVersion", "")
        Logger.Info("已清空主页缓存")
    End Sub

    ''' <summary>
    ''' 从文本内容中加载主页。
    ''' 必须在 UI 线程调用。
    ''' </summary>
    Private Sub LoadContent(Content As String)
        Try
            SyncLock LoadContentLock
                '如果加载目标内容一致则不加载
                Dim Hash = If(Content, "").GetStableHashCode()
                If Hash = LoadedContentHash Then Return
                LoadedContentHash = Hash
                '实际加载内容
                PanCustom.Children.Clear()
                If String.IsNullOrWhiteSpace(Content) Then
                    Logger.Info($"实例化：清空主页 UI，来源为空")
                    Return
                End If
                Dim LoadStartTime As Date = Date.Now
                Content = ArgumentReplace(Content, AddressOf StringUtils.XmlEscape)
                Do While Content.Contains("xmlns")
                    Content = Content.RegexReplace("xmlns[^""']*(""|')[^""']*(""|')", "").Replace("xmlns", "") '禁止声明命名空间
                Loop
                Content = "<StackPanel xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" xmlns:sys=""clr-namespace:System;assembly=mscorlib"" xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml"" xmlns:local=""clr-namespace:PCL;assembly=Plain Craft Launcher Slash"" xmlns:core=""clr-namespace:MeloongCore;assembly=MeloongCore"" xmlns:corewpf=""clr-namespace:MeloongCore.Wpf;assembly=MeloongCore.Wpf"">" & Content & "</StackPanel>"
                Logger.Info($"实例化：加载主页 UI 开始，最终内容长度：{Content.Count}")
                PanCustom.Children.Add(GetObjectFromXML(Content))
                '加载计时
                Dim LoadCostTime = (Date.Now - LoadStartTime).Milliseconds
                Logger.Info($"实例化：加载主页 UI 完成，耗时 {LoadCostTime}ms")
                If LoadCostTime > 3000 Then Hint($"主页加载过于缓慢（花费了 {Math.Round(LoadCostTime / 1000, 1)} 秒），请向主页作者反馈此问题，或暂时停止使用该主页")
            End SyncLock
        Catch ex As Exception
            Logger.Warn(ex, $"加载失败的主页内容：{vbCrLf}{Content}")
            OnLoadContentFailed(ex)
        End Try
    End Sub
    ''' <summary>
    ''' 加载主页失败时调用。
    ''' </summary>
    Private Sub OnLoadContentFailed(ex As Exception)
        If ModeDebug OrElse Settings.Get(Of Integer)("UiCustomType") = 1 Then
            Logger.Warn(ex, "加载主页失败")
            If MyMsgBox(If(TypeOf ex Is UnauthorizedAccessException, ex.Message, $"主页内容编写有误，请根据下列错误信息进行检查：{vbCrLf}{ex.GetDisplay(False)}"),
                        "加载主页失败", "重试", "取消") = 1 Then ForceRefresh()
        Else
            Logger.Error(ex, "加载主页失败", LogBehavior.Toast)
        End If
    End Sub
    ''' <summary>
    ''' 捕获主页在 Measure 和 Arrange 阶段抛出的异常。
    ''' </summary>
    Private Sub DispatcherUnhandledException(sender As Object, e As DispatcherUnhandledExceptionEventArgs) Implements IDispatcherUnhandledException.DispatcherUnhandledException
        If TypeOf e.Exception IsNot Markup.XamlParseException Then Return
        e.Handled = True
        LoadContent(Nothing)
        OnLoadContentFailed(e.Exception)
    End Sub

    Private LoadedContentHash As ULong? = Nothing
    Private LoadContentLock As New Object

#End Region

End Class
