'由于包含加解密等安全信息，本文件中的部分代码已被删除

Friend Module ModSecret

    '标注 PCL 的不同分支，仅用于替换标记
    Public Const VersionBranchMain As String = "Slash"
    '在开源版的注册表与常规版的注册表隔离，以防数据冲突
    Public Const RegFolder As String = BrandName
    '用于微软登录的 ClientId
    Public OAuthClientId As String = If(Environment.GetEnvironmentVariable("PCL_MS_CLIENT_ID"), "")
    'CurseForge API Key
    Public CurseForgeAPIKey As String = If(Environment.GetEnvironmentVariable("PCL_CURSEFORGE_API_KEY"), "")
    '用于匿名数据收集的腾讯云日志服务上报 URL，形如 https://{region}.cls.tencentcs.com/track?topic_id={topic_id}
    Public Const ClsBaseUrl As String = ""

#Region "网络鉴权"

    Friend Function SecretCdnSign(UrlWithMark As String) As String
        If Not UrlWithMark.EndsWithF("{CDN}") Then Return UrlWithMark
        Return UrlWithMark.Replace("{CDN}", "").Replace(" ", "%20")
    End Function
    ''' <summary>
    ''' 设置 Headers 的 UA、Referer。
    ''' </summary>
    Friend Sub SecretHeadersSign(Url As String, ByRef Req As HttpRequestMessage, Optional SimulateBrowserHeaders As Boolean = False)
        If Not Req.Headers.UserAgent.Any Then
            If Url.Contains("baidupcs.com") OrElse Url.Contains("baidu.com") Then
                Req.Headers.Add("User-Agent", "LogStatistic")  '#4951
            ElseIf SimulateBrowserHeaders Then
                Req.Headers.Add("User-Agent", $"{BrandName}/{VersionBaseName}.{CInt(BuildType)} Mozilla/5.0 AppleWebKit/537.36 Chrome/63.0.3239.132 Safari/537.36")
            Else
                Req.Headers.Add("User-Agent", $"{BrandName}/{VersionBaseName}.{CInt(BuildType)}")
            End If
        End If
        If Not SimulateBrowserHeaders Then Req.Headers.Add("Referer", SourceRepository)
        If Url.Contains("api.curseforge.com") OrElse Url.Contains("forgecdn.net") Then Req.Headers.Add("x-api-key", CurseForgeAPIKey)
    End Sub

#End Region

#Region "主题"

    Public Const DefaultThemeId As Integer = 15 '天依蓝；保留旧主题编号，8（赞助主题）不再使用。
    Public Const CangGreenThemeId As Integer = 16 '苍绿色 #39C5BB
    Public Color1 As New MyColor(38, 62, 74)
    Public Color2 As New MyColor(22, 124, 166)
    Public Color3 As New MyColor(22, 143, 194)
    Public Color4 As New MyColor(102, 204, 255) '#66CCFF
    Public Color5 As New MyColor(179, 230, 255)
    Public Color6 As New MyColor(214, 241, 255)
    Public Color7 As New MyColor(229, 246, 255)
    Public Color8 As New MyColor(240, 250, 255)
    Public ColorBg0 As New MyColor(179, 230, 255)
    Public ColorBg1 As New MyColor(190, Color7)
    Public ColorGray1 As New MyColor(64, 64, 64)
    Public ColorGray2 As New MyColor(115, 115, 115)
    Public ColorGray3 As New MyColor(140, 140, 140)
    Public ColorGray4 As New MyColor(166, 166, 166)
    Public ColorGray5 As New MyColor(204, 204, 204)
    Public ColorGray6 As New MyColor(235, 235, 235)
    Public ColorGray7 As New MyColor(240, 240, 240)
    Public ColorGray8 As New MyColor(245, 245, 245)
    Public ColorSemiTransparent As New MyColor(1, Color8)

    Public ThemeNow As Integer = -1
    Public ColorHue As Integer = 210, ColorSat As Integer = 85, ColorLightAdjust As Integer = 0, ColorHueTopbarDelta As OneOf(Of Integer, Integer()) = 0
    Public ThemeDontClick As Integer = 0

    Public Sub ThemeRefresh(Optional NewTheme As Integer = -1)
        Try
            If NewTheme >= 0 AndAlso Not ThemeCheckOne(NewTheme) Then
                '旧配置中的赞助主题或未知编号统一回退，其他主题选择不受影响。
                NewTheme = DefaultThemeId
                Settings.Set("UiLauncherTheme", DefaultThemeId)
            End If
            If ThemeNow = NewTheme AndAlso NewTheme >= 0 Then Return
            If NewTheme >= 0 Then ThemeNow = NewTheme
            If ThemeNow < 0 Then ThemeNow = DefaultThemeId

            '开源版本不包含上游的配色切换实现，为保留的主题提供独立配色。
            ColorHue = 210 : ColorSat = 85 : ColorLightAdjust = 0 : ColorHueTopbarDelta = 0
            Select Case ThemeNow
                Case 1 '甜柠青
                    ColorHue = 180 : ColorSat = 75
                Case 2 '小草绿
                    ColorHue = 120 : ColorSat = 65
                Case 3 '菠萝黄
                    ColorHue = 50 : ColorSat = 75
                Case 4 '橡木棕
                    ColorHue = 30 : ColorSat = 60 : ColorLightAdjust = -8
                Case 5 '玄素黑
                    ColorSat = 0 : ColorLightAdjust = -10
                Case 6 '铁杆粉
                    ColorHue = 335 : ColorSat = 75
                Case 7 '神秘紫
                    ColorHue = 270 : ColorSat = 65
                Case 9 '活跃橙
                    ColorHue = 25 : ColorSat = 85
                Case 10 '跳票红
                    ColorHue = 0 : ColorSat = 80
                Case 11 '极客蓝
                    ColorHue = 220 : ColorSat = 100 : ColorLightAdjust = -10
                Case 12 '滑稽彩
                    ColorHue = CInt((GetTimeMs() \ 80) Mod 360)
                    ColorSat = 80 : ColorHueTopbarDelta = 45
                Case 13 '欧皇彩
                    ColorHue = 260 : ColorSat = 80
                    ColorHueTopbarDelta = New Integer() {-120, 0, 120}
                Case 14 '自定义
                    ColorHue = Settings.Get(Of Integer)("UiLauncherHue")
                    ColorSat = Settings.Get(Of Integer)("UiLauncherSat")
                    ColorLightAdjust = Settings.Get(Of Integer)("UiLauncherLight") - 20
                    ColorHueTopbarDelta = Settings.Get(Of Integer)("UiLauncherDelta")
                Case DefaultThemeId '天依蓝
                    ColorHue = 200 : ColorSat = 100
                Case CangGreenThemeId '苍绿色
                    ColorHue = 176 : ColorSat = 55
            End Select

            Color1 = New MyColor().FromHSL2(ColorHue, ColorSat * 0.2, 25 + ColorLightAdjust * 0.3)
            Color2 = New MyColor().FromHSL2(ColorHue, ColorSat, 45 + ColorLightAdjust)
            Color3 = New MyColor().FromHSL2(ColorHue, ColorSat, 55 + ColorLightAdjust)
            Color4 = New MyColor().FromHSL2(ColorHue, ColorSat, 65 + ColorLightAdjust)
            Color5 = New MyColor().FromHSL2(ColorHue, ColorSat, 80 + ColorLightAdjust * 0.4)
            Color6 = New MyColor().FromHSL2(ColorHue, ColorSat, 91 + ColorLightAdjust * 0.1)
            Color7 = New MyColor().FromHSL2(ColorHue, ColorSat, 95)
            Color8 = New MyColor().FromHSL2(ColorHue, ColorSat, 97)
            If ThemeNow = DefaultThemeId Then
                '浅蓝用于高亮和装饰，交互文字使用更深的同色系，保证浅色背景上的辨识度。
                Color1 = New MyColor(38, 62, 74)
                Color2 = New MyColor(22, 124, 166)
                Color3 = New MyColor(22, 143, 194)
                Color4 = New MyColor(102, 204, 255)
                Color5 = New MyColor(179, 230, 255)
                Color6 = New MyColor(214, 241, 255)
                Color7 = New MyColor(229, 246, 255)
                Color8 = New MyColor(240, 250, 255)
            ElseIf ThemeNow = CangGreenThemeId Then
                Color1 = New MyColor(38, 62, 60)
                Color2 = New MyColor(26, 129, 122)
                Color3 = New MyColor(31, 145, 137)
                Color4 = New MyColor(57, 197, 187) '#39C5BB
                Color5 = New MyColor(156, 226, 221)
                Color6 = New MyColor(208, 240, 237)
                Color7 = New MyColor(226, 246, 244)
                Color8 = New MyColor(239, 251, 249)
            End If
            ColorBg0 = Color4 * 0.4 + Color5 * 0.4 + ColorGray4 * 0.2
            ColorBg1 = New MyColor(190, Color7)

            ColorSemiTransparent = New MyColor(1, Color8)
            Application.Current.Resources("ColorBrush1") = New SolidColorBrush(Color1)
            Application.Current.Resources("ColorBrush2") = New SolidColorBrush(Color2)
            Application.Current.Resources("ColorBrush3") = New SolidColorBrush(Color3)
            Application.Current.Resources("ColorBrush4") = New SolidColorBrush(Color4)
            Application.Current.Resources("ColorBrush5") = New SolidColorBrush(Color5)
            Application.Current.Resources("ColorBrush6") = New SolidColorBrush(Color6)
            Application.Current.Resources("ColorBrush7") = New SolidColorBrush(Color7)
            Application.Current.Resources("ColorBrush8") = New SolidColorBrush(Color8)
            Application.Current.Resources("ColorBrushBg0") = New SolidColorBrush(ColorBg0)
            Application.Current.Resources("ColorBrushBg1") = New SolidColorBrush(ColorBg1)
            Application.Current.Resources("ColorObject1") = CType(Color1, Color)
            Application.Current.Resources("ColorObject2") = CType(Color2, Color)
            Application.Current.Resources("ColorObject3") = CType(Color3, Color)
            Application.Current.Resources("ColorObject4") = CType(Color4, Color)
            Application.Current.Resources("ColorObject5") = CType(Color5, Color)
            Application.Current.Resources("ColorObject6") = CType(Color6, Color)
            Application.Current.Resources("ColorObject7") = CType(Color7, Color)
            Application.Current.Resources("ColorObject8") = CType(Color8, Color)
            Application.Current.Resources("ColorObjectBg0") = CType(ColorBg0, Color)
            Application.Current.Resources("ColorObjectBg1") = CType(ColorBg1, Color)
            ThemeRefreshMain()
        Catch ex As Exception
            Logger.Error(ex, "刷新主题颜色失败", LogBehavior.Toast)
        End Try
    End Sub
    Public Sub ThemeRefreshMain()
        If FrmMain Is Nothing Then Return
        RunInUi(
        Sub()
            If Not FrmMain.IsLoaded Then Return
            '顶部条背景
            Dim Brush = New LinearGradientBrush With {.EndPoint = New Point(1, 0), .StartPoint = New Point(0, 0)}
            Dim Deltas = ColorHueTopbarDelta.Switch(Function(d) New Integer() {-d, 0, d}, Function(d) d)
            Brush.GradientStops.Add(New GradientStop With {.Offset = 0, .Color = New MyColor().FromHSL2(ColorHue + Deltas(0), ColorSat, 48 + ColorLightAdjust)})
            Brush.GradientStops.Add(New GradientStop With {.Offset = 0.5, .Color = New MyColor().FromHSL2(ColorHue + Deltas(1), ColorSat, 54 + ColorLightAdjust)})
            Brush.GradientStops.Add(New GradientStop With {.Offset = 1, .Color = New MyColor().FromHSL2(ColorHue + Deltas(2), ColorSat, 48 + ColorLightAdjust)})
            FrmMain.PanTitle.Background = Brush
            FrmMain.PanTitle.Background.Freeze()
            '主页面背景
            If Settings.Get(Of Boolean)("UiBackgroundColorful") Then
                Brush = New LinearGradientBrush With {.EndPoint = New Point(0.1, 1), .StartPoint = New Point(0.9, 0)}
                Brush.GradientStops.Add(New GradientStop With {.Offset = -0.1, .Color = New MyColor().FromHSL2(ColorHue - 15, ColorSat * 0.8, 91)})
                Brush.GradientStops.Add(New GradientStop With {.Offset = 0.4, .Color = New MyColor().FromHSL2(ColorHue, ColorSat * 0.8, 91)})
                Brush.GradientStops.Add(New GradientStop With {.Offset = 1.1, .Color = New MyColor().FromHSL2(ColorHue + 15, ColorSat * 0.8, 91)})
                FrmMain.PanForm.Background = Brush
            Else
                FrmMain.PanForm.Background = New MyColor(245, 245, 245)
            End If
            FrmMain.PanForm.Background.Freeze()
        End Sub)
    End Sub
    Friend Sub ThemeCheckAll(EffectSetup As Boolean)
        Dim SelectedTheme = Settings.Get(Of Integer)("UiLauncherTheme")
        If Not ThemeCheckOne(SelectedTheme) Then Settings.Set("UiLauncherTheme", DefaultThemeId)
        If EffectSetup Then FrmSetupUI?.RefreshThemeChoices()
    End Sub
    Friend Function ThemeCheckOne(Id As Integer) As Boolean
        Select Case Id
            Case 0 To 4, 14, DefaultThemeId, CangGreenThemeId
                Return True
            Case 5 To 7, 9 To 13
                Return Settings.Get(Of String)("UiLauncherThemeHide2").Split("|"c).Contains(Id.ToString())
            Case Else
                Return False
        End Select
    End Function
    Friend Function ThemeUnlock(Id As Integer, Optional ShowDoubleHint As Boolean = True, Optional UnlockHint As String = Nothing) As Boolean
        If Id < 5 OrElse Id > 13 OrElse Id = 8 OrElse ThemeCheckOne(Id) Then Return False
        Dim Unlocked As New HashSet(Of String)(Settings.Get(Of String)("UiLauncherThemeHide2").Split("|"c))
        Unlocked.Add(Id.ToString())
        Settings.Set("UiLauncherThemeHide2", String.Join("|", Unlocked.OrderBy(Function(Value) Value)))
        RunInUi(
        Sub()
            FrmSetupUI?.RefreshThemeChoices()
            If ShowDoubleHint OrElse UnlockHint IsNot Nothing Then Hint(If(UnlockHint, "发现了新的隐藏主题！"), HintType.Green)
        End Sub)
        Return True
    End Function

#End Region

#Region "更新"

    Friend Sub UpdateCheckByButton()
        Hint("该版本中不包含更新功能……")
    End Sub

    Friend IsUpdateWaitingRestart As Boolean = False
    Public Sub UpdateRestart(TriggerRestartAndByEnd As Boolean)
    End Sub
    Public Sub UpdateReplace(ProcessId As Integer, OldFileName As String, NewFileName As String, TriggerRestart As Boolean)
    End Sub

    ''' <summary>
    ''' 确保 PathTemp/Latest.exe 是最新正式版的 PCL，它会被用于整合包打包。
    ''' 如果不是，则下载一个。
    ''' </summary>
    Friend Sub DownloadLatestPCL(Optional LoaderToSyncProgress As LoaderBase = Nothing)
        '注意：如果要自行实现这个功能，请换用另一个文件路径，以免与官方版本冲突
    End Sub

#End Region

#Region "联网配置"

    ''' <summary>
    ''' 联网获取的配置信息。
    ''' 若获取失败或仍在获取中，可能为 Nothing。
    ''' </summary>
    Public ServerConfig As JObject

    Public ServerLoader As New LoaderTask(Of Integer, Integer)("PCL-Slash 配置更新", Sub() Logger.Info("该版本中不包含更新通知功能……"), Priority:=ThreadPriority.BelowNormal) With
        {.ReloadTimeout = 1000 * 60 * 60} '超时 1 小时

#End Region

#Region "赞助等级"

    Public ReadOnly Property CurrentRank As DonationRank
        Get
            Return DonationRank.None
        End Get
    End Property

    Public Sub InputPotatoCode(IsUpdating As Boolean)
    End Sub
    Friend Sub GeneratePotatoCode()
    End Sub

    ''' <summary>
    ''' 获取设备识别码。
    ''' </summary>
    Friend Function GetIdentify() As String
        Return "0000-0000-0000-0000"
    End Function

#End Region

End Module
