Public Class PageSetupLeft

    Private IsLoad As Boolean = False
    Private IsPageSwitched As Boolean = False '如果在 Loaded 前切换到其他页面，会导致触发 Loaded 时再次切换一次
    Private Sub PageSetupLeft_Loaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded
        '是否处于隐藏的子页面
        Dim IsHiddenPage As Boolean = False
        If ItemLaunch.Checked AndAlso Settings.Get(Of Boolean)("UiHiddenSetupLaunch") Then IsHiddenPage = True
        If ItemUI.Checked AndAlso Settings.Get(Of Boolean)("UiHiddenSetupUi") Then IsHiddenPage = True
        If ItemGame.Checked AndAlso Settings.Get(Of Boolean)("UiHiddenSetupGame") Then IsHiddenPage = True
        If ItemDownload.Checked AndAlso Settings.Get(Of Boolean)("UiHiddenSetupDownload") Then IsHiddenPage = True
        If ItemLauncher.Checked AndAlso Settings.Get(Of Boolean)("UiHiddenSetupLauncher") Then IsHiddenPage = True
        If ItemSystem.Checked AndAlso Settings.Get(Of Boolean)("UiHiddenSetupSystem") Then IsHiddenPage = True
        If PageSetupUI.HiddenForceShow Then IsHiddenPage = False
        '若页面错误，或尚未加载，则继续
        If IsLoad AndAlso Not IsHiddenPage Then Return
        IsLoad = True
        '刷新子页面隐藏情况
        PageSetupUI.HiddenRefresh()
        '选择第一个未被禁用的子页面
        If IsPageSwitched Then Return
        If Not Settings.Get(Of Boolean)("UiHiddenSetupLaunch") Then
            ItemLaunch.SetChecked(True, False, False)
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupGame") Then
            ItemGame.SetChecked(True, False, False)
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupDownload") Then
            ItemDownload.SetChecked(True, False, False)
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupUi") Then
            ItemUI.SetChecked(True, False, False)
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupLauncher") Then
            ItemLauncher.SetChecked(True, False, False)
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupSystem") Then
            ItemSystem.SetChecked(True, False, False)
        Else
            ItemLaunch.SetChecked(True, False, False)
        End If
    End Sub
    Private Sub PageOtherLeft_Unloaded(sender As Object, e As RoutedEventArgs) Handles Me.Unloaded
        IsPageSwitched = False
    End Sub

#Region "页面切换"

    ''' <summary>
    ''' 当前页面的编号，与导航控件的 Tag 一致。
    ''' </summary>
    Public PageID As FormMain.PageSubType
    Public Sub New()
        InitializeComponent()
        '选择第一个未被禁用的子页面
        If Not Settings.Get(Of Boolean)("UiHiddenSetupLaunch") Then
            PageID = FormMain.PageSubType.SetupLaunch
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupGame") Then
            PageID = FormMain.PageSubType.SetupGame
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupDownload") Then
            PageID = FormMain.PageSubType.SetupDownload
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupUi") Then
            PageID = FormMain.PageSubType.SetupUI
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupLauncher") Then
            PageID = FormMain.PageSubType.SetupLauncher
        ElseIf Not Settings.Get(Of Boolean)("UiHiddenSetupSystem") Then
            PageID = FormMain.PageSubType.SetupSystem
        Else
            PageID = FormMain.PageSubType.SetupLaunch
        End If
    End Sub

    ''' <summary>
    ''' 勾选事件改变页面。
    ''' </summary>
    Private Sub PageCheck(sender As MyListItem, e As EventArgs) Handles ItemGame.Check, ItemLaunch.Check, ItemDownload.Check, ItemLauncher.Check, ItemSystem.Check, ItemUI.Check
        '尚未初始化控件属性时，sender.Tag 为 Nothing，会跳过切换，且由于 PageID 默认为 0 而切换到第一个页面
        '若使用 IsLoaded，则会导致模拟点击不被执行（模拟点击切换页面时，控件的 IsLoaded 为 False）
        If sender.Tag IsNot Nothing Then PageChange(Val(sender.Tag))
    End Sub

    ''' <summary>
    ''' 获取当前导航指定的右页面。
    ''' </summary>
    Public Function PageGet(Optional ID As FormMain.PageSubType = -1)
        If ID = -1 Then ID = PageID
        Select Case ID
            Case FormMain.PageSubType.SetupLaunch
                If FrmSetupLaunch Is Nothing Then FrmSetupLaunch = New PageSetupLaunch
                Return FrmSetupLaunch
            Case FormMain.PageSubType.SetupUI
                If FrmSetupUI Is Nothing Then FrmSetupUI = New PageSetupUI
                Return FrmSetupUI
            Case FormMain.PageSubType.SetupGame
                If FrmSetupGame Is Nothing Then FrmSetupGame = New PageSetupGame
                Return FrmSetupGame
            Case FormMain.PageSubType.SetupDownload
                If FrmSetupDownload Is Nothing Then FrmSetupDownload = New PageSetupDownload
                Return FrmSetupDownload
            Case FormMain.PageSubType.SetupLauncher
                If FrmSetupLauncher Is Nothing Then FrmSetupLauncher = New PageSetupLauncher
                Return FrmSetupLauncher
            Case FormMain.PageSubType.SetupSystem
                If FrmSetupSystem Is Nothing Then FrmSetupSystem = New PageSetupSystem
                Return FrmSetupSystem
            Case Else
                Throw New Exception("未知的设置子页面种类：" & ID)
        End Select
    End Function

    ''' <summary>
    ''' 切换现有页面。
    ''' </summary>
    Public Sub PageChange(ID As FormMain.PageSubType)
        If PageID = ID Then Return
        AniControlEnabled += 1
        IsPageSwitched = True
        Try

            PageChangeRun(PageGet(ID))

            PageID = ID
        Catch ex As Exception
            Logger.Error(ex, $"切换分页面失败（ID {ID}）")
        Finally
            AniControlEnabled -= 1
        End Try
    End Sub
    Private Shared Sub PageChangeRun(Target As MyPageRight)
        AniStop("FrmMain PageChangeRight") '停止主页面的右页面切换动画，防止它与本动画一起触发多次 PageOnEnter
        If Target.Parent IsNot Nothing Then Target.SetValue(ContentPresenter.ContentProperty, Nothing)
        FrmMain.PageRight = Target
        CType(FrmMain.PanMainRight.Child, MyPageRight).PageOnExit()
        AniStart({
            AaCode(
            Sub()
                CType(FrmMain.PanMainRight.Child, MyPageRight).PageOnForceExit()
                FrmMain.PanMainRight.Child = FrmMain.PageRight
                FrmMain.PageRight.Opacity = 0
            End Sub, 130),
            AaCode(
            Sub()
                '延迟触发页面通用动画，以使得在 Loaded 事件中加载的控件得以处理
                FrmMain.PageRight.Opacity = 1
                FrmMain.PageRight.PageOnEnter()
            End Sub, 30, True)
        }, "PageLeft PageChange")
    End Sub

#End Region

    Public Sub Reset(sender As Object, e As EventArgs)
        Select Case Val(sender.Tag)
            Case FormMain.PageSubType.SetupLaunch
                If MyMsgBox("是否要初始化 启动 页面的所有设置？该操作不可撤销。", "初始化确认",, "取消", IsWarn:=True) = 1 Then
                    If IsNothing(FrmSetupLaunch) Then FrmSetupLaunch = New PageSetupLaunch
                    FrmSetupLaunch.Reset()
                    ItemLaunch.Checked = True
                End If
            Case FormMain.PageSubType.SetupUI
                If MyMsgBox("是否要初始化 个性化 页面的所有设置？该操作不可撤销。" & vbCrLf & "（背景图片与音乐、主页等外部文件不会被删除）", "初始化确认",, "取消", IsWarn:=True) = 1 Then
                    If IsNothing(FrmSetupUI) Then FrmSetupUI = New PageSetupUI
                    FrmSetupUI.Reset()
                    ItemUI.Checked = True
                End If
            Case FormMain.PageSubType.SetupGame
                If MyMsgBox("是否要初始化 游戏功能 页面的所有设置？该操作不可撤销。", "初始化确认",, "取消", IsWarn:=True) = 1 Then
                    If FrmSetupGame Is Nothing Then FrmSetupGame = New PageSetupGame
                    FrmSetupGame.Reset()
                    ItemGame.Checked = True
                End If
            Case FormMain.PageSubType.SetupDownload
                If MyMsgBox("是否要初始化 下载 页面的所有设置？该操作不可撤销。", "初始化确认",, "取消", IsWarn:=True) = 1 Then
                    If FrmSetupDownload Is Nothing Then FrmSetupDownload = New PageSetupDownload
                    FrmSetupDownload.Reset()
                    ItemDownload.Checked = True
                End If
            Case FormMain.PageSubType.SetupLauncher
                If MyMsgBox("是否要初始化 启动器 页面的所有设置？该操作不可撤销。", "初始化确认",, "取消", IsWarn:=True) = 1 Then
                    If FrmSetupLauncher Is Nothing Then FrmSetupLauncher = New PageSetupLauncher
                    FrmSetupLauncher.Reset()
                    ItemLauncher.Checked = True
                End If
            Case FormMain.PageSubType.SetupSystem
                If MyMsgBox("是否要初始化 其他 页面的所有设置？该操作不可撤销。", "初始化确认",, "取消", IsWarn:=True) = 1 Then
                    If IsNothing(FrmSetupSystem) Then FrmSetupSystem = New PageSetupSystem
                    FrmSetupSystem.Reset()
                    ItemSystem.Checked = True
                End If
        End Select
    End Sub

End Class
