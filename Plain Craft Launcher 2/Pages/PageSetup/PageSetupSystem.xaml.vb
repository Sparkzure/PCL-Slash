Public Class PageSetupSystem
    Public Sub New()
        InitializeComponent()
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
    End Sub
    Public Sub Reset()
        SettingService.ResetSettings(Me)
        Reload()
        Hint("已初始化本页设置！", HintType.Green, False)
    End Sub
    Private Sub SliderLoad()
        SliderDebugAnim.GetHintText = Function(v) If(v > 29, "关闭", (v / 10 + 0.1) & "x")
    End Sub
    Private Sub CheckDebugMode_Change() Handles CheckDebugMode.Change
        If AniControlEnabled = 0 Then Hint("部分调试信息将在刷新或启动器重启后切换显示！",, False)
    End Sub
End Class
