' 辅助功能与离线皮肤分别移自 PageSetupLauncher、PageSetupLaunch，原实现来源保持不变。
Public Class PageSetupGame
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
        Finally
            AniControlEnabled -= 1
        End Try
    End Sub
    Private SettingsLoaded As Boolean
    Public Sub Reload()
        SettingService.RefreshSettings(Me)
        RefreshSkinType()
    End Sub
    Public Sub Reset()
        SettingService.ResetSettings(Me)
        Reload()
        Hint("已初始化本页设置！", HintType.Green, False)
    End Sub
#Region "离线皮肤"

    Private Sub BtnSkinChange_Click(sender As Object, e As EventArgs) Handles BtnSkinChange.Click
        Dim SkinInfo As McSkinInfo = McSkinSelect()
        If Not SkinInfo.IsVaild Then Return
        ChangeSkin(SkinInfo)
    End Sub
    Private Sub RadioSkinType3_Check(sender As Object, e As RouteEventArgs) Handles RadioSkinType4.PreviewCheck
        If Not (AniControlEnabled = 0 AndAlso e.RaiseByMouse) Then Return
        '已有图片则不再选择
        If FileUtils.Exists(Paths.BaseThenName & "CustomSkin.png") Then Return
        '没有图片则要求选择
        Dim SkinInfo As McSkinInfo = McSkinSelect()
        If Not SkinInfo.IsVaild Then
            e.Handled = True
            Return
        End If
        '正式改变
        If Not ChangeSkin(SkinInfo) Then e.Handled = True
    End Sub
    '返回是否成功改变
    Private Function ChangeSkin(SkinInfo As McSkinInfo) As Boolean
        Try
            '复制文件
            FileUtils.Copy(SkinInfo.LocalFile, Paths.BaseThenName & "CustomSkin.png")
            '将单层皮肤扩展到双层
            Dim Bitmap As New MyBitmap(Paths.BaseThenName & "CustomSkin.png")
            If Bitmap.Pic.Width = 64 AndAlso Bitmap.Pic.Height = 32 Then
                Dim Img As System.Drawing.Image = Bitmap
                Dim NewBitmap As New System.Drawing.Bitmap(64, 64)
                Using g As System.Drawing.Graphics = System.Drawing.Graphics.FromImage(NewBitmap)
                    g.DrawImageUnscaled(Img, New System.Drawing.Point(0, 0))
                End Using
                FileUtils.Delete(Paths.BaseThenName & "CustomSkin.png")
                NewBitmap.Save(Paths.BaseThenName & "CustomSkin.png")
            End If
            '更新设置
            Settings.Set("LaunchSkinSlim", SkinInfo.IsSlim)
            Return True
        Catch ex As Exception
            Logger.Error(ex, "改变离线皮肤失败", LogBehavior.Alert)
            Return False
        Finally
            '设置当前显示
            PageLaunchLeft.SkinLegacy.Start(IsForceRestart:=True)
        End Try
    End Function
    Private Sub BtnSkinDelete_Click(sender As Object, e As EventArgs) Handles BtnSkinDelete.Click
        Try
            FileUtils.Delete(Paths.BaseThenName & "CustomSkin.png")
            RadioSkinType0.SetChecked(True, True)
            Hint("离线皮肤已清空！", HintType.Green)
        Catch ex As Exception
            Logger.Error(ex, "清空离线皮肤失败", LogBehavior.Alert)
        End Try
    End Sub
    Private Sub BtnSkinSave_Click(sender As Object, e As EventArgs) Handles BtnSkinSave.Click
        MySkin.Save(PageLaunchLeft.SkinLegacy)
    End Sub
    Private Sub BtnSkinCache_Click(sender As Object, e As EventArgs) Handles BtnSkinCache.Click
        MySkin.RefreshCache(Nothing)
    End Sub

    Public Shared Sub UpdateSkinType()
        PageLaunchLeft.SkinLegacy.Start()
        FrmSetupGame?.RefreshSkinType()
    End Sub

    Private Sub RefreshSkinType()
        Select Case Settings.Get(Of Integer)("LaunchSkinType")
            Case 0, 1, 2 '默认
                PanSkinID.Visibility = Visibility.Collapsed
                PanSkinChange.Visibility = Visibility.Collapsed
            Case 3 '正版
                PanSkinID.Visibility = Visibility.Visible
                PanSkinChange.Visibility = Visibility.Collapsed
            Case 4 '自定义
                PanSkinID.Visibility = Visibility.Collapsed
                PanSkinChange.Visibility = Visibility.Visible
        End Select
        CardSkin.TriggerForceResize()
    End Sub

#End Region
End Class
