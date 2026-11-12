' 下载设置与滑动条处理移自 PageSetupSystem，原实现来源保持不变。
Public Class PageSetupDownload
    Public Sub New()
        InitializeComponent()
        '自定义镜像校验及可见性。
        TextMinecraftMirrorCustom.ValidateRules.Add(New ValidateFunc(AddressOf ValidateDownloadMirrorAddress))
        TextCommunityMirrorCustom.ValidateRules.Add(New ValidateFunc(AddressOf ValidateDownloadMirrorAddress))
    End Sub
    Private Sub PageLoaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded
        PanBack.ScrollToHome()
        If SettingsLoaded Then Return
        SettingsLoaded = True
        AniControlEnabled += 1
        Try
            Reload()
            SliderLoad()
        Finally
            AniControlEnabled -= 1
        End Try
    End Sub
    Private SettingsLoaded As Boolean
    Public Sub Reload()
        SettingService.RefreshSettings(Me)
        RefreshMirrorUi()
    End Sub
    Private Sub RefreshMirrorUi() Handles ComboMinecraftMirror.SelectionChanged, ComboCommunityMirror.SelectionChanged
        If PanMinecraftMirrorCustom Is Nothing OrElse PanCommunityMirrorCustom Is Nothing Then Return
        PanMinecraftMirrorCustom.Visibility = If(ComboMinecraftMirror.SelectedIndex = 1, Visibility.Visible, Visibility.Collapsed)
        PanCommunityMirrorCustom.Visibility = If(ComboCommunityMirror.SelectedIndex = 1, Visibility.Visible, Visibility.Collapsed)
    End Sub
    Public Sub Reset()
        SettingService.ResetSettings(Me)
        Reload()
        Hint("已初始化本页设置！", HintType.Green, False)
    End Sub
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
    End Sub
    Private Sub SliderDownloadThread_PreviewChange(sender As Object, e As RouteEventArgs) Handles SliderDownloadThread.PreviewChange
        If SliderDownloadThread.Value < 100 Then Return
        If Not Settings.Get(Of Boolean)("HintDownloadThread") Then
            Settings.Set("HintDownloadThread", True)
            MyMsgBox("如果设置过多的下载线程，可能会导致下载时出现非常严重的卡顿。" & vbCrLf &
                     "一般设置 64 线程即可满足大多数下载需求，除非你知道你在干什么，否则不建议设置更多的线程数！", "警告", "我知道了", IsWarn:=True)
        End If
    End Sub

End Class
