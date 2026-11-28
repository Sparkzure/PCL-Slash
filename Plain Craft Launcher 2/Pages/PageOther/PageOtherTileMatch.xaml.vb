Imports System.Diagnostics
Imports System.Windows.Automation
Imports System.Windows.Threading

Public Class PageOtherTileMatch
    Private Game As New TileMatchBoard
    Private ReadOnly Cells As New List(Of Button)
    Private ReadOnly Clock As New Stopwatch
    Private ReadOnly GameTimer As DispatcherTimer
    Private SelectedIndex As Integer = -1
    Private RoundNumber As Integer = 1
    Private IsGamePageActive As Boolean
    Private HostWindow As Window
    Private Shared ReadOnly TileBrushes As Brush() = {
        Brushes.Transparent, New SolidColorBrush(Color.FromRgb(232, 86, 86)), New SolidColorBrush(Color.FromRgb(243, 155, 53)),
        New SolidColorBrush(Color.FromRgb(228, 201, 64)), New SolidColorBrush(Color.FromRgb(100, 185, 86)),
        New SolidColorBrush(Color.FromRgb(38, 183, 165)), New SolidColorBrush(Color.FromRgb(66, 181, 229)),
        New SolidColorBrush(Color.FromRgb(82, 121, 216)), New SolidColorBrush(Color.FromRgb(149, 100, 214)),
        New SolidColorBrush(Color.FromRgb(222, 119, 186)), New SolidColorBrush(Color.FromRgb(164, 124, 89))}

    Public Sub New()
        InitializeComponent()
        For Index = 0 To TileMatchBoard.Width * TileMatchBoard.Height - 1
            Dim Cell As New Button With {.Tag = Index, .Style = CType(FindResource("TileMatchCellStyle"), Style)}
            AddHandler Cell.Click, AddressOf TileClicked
            Cells.Add(Cell)
            PanTileMatchBoard.Children.Add(Cell)
        Next
        GameTimer = New DispatcherTimer With {.Interval = TimeSpan.FromMilliseconds(10)}
        AddHandler GameTimer.Tick, AddressOf TimerTick
        RefreshGame()
    End Sub

    Private Sub Restart(sender As Object, e As EventArgs) Handles BtnTileMatchRestart.Click
        GameTimer.Stop()
        Clock.Reset()
        Game = New TileMatchBoard
        RoundNumber = 1
        SelectedIndex = -1
        RefreshGame()
    End Sub

    Private Function CanPlay() As Boolean
        Return IsGamePageActive AndAlso (HostWindow Is Nothing OrElse HostWindow.IsActive)
    End Function

    Private Sub TileClicked(sender As Object, e As RoutedEventArgs)
        If Not CanPlay() Then Return
        Dim Index = CInt(CType(sender, Button).Tag)
        If Game.GetCell(Index) = 0 Then Return
        If Index = SelectedIndex Then
            SelectedIndex = -1
        ElseIf SelectedIndex < 0 Then
            SelectedIndex = Index
        ElseIf Game.TryMatch(SelectedIndex, Index) Then
            SelectedIndex = -1
            If Game.Remaining = 0 Then FinishRound()
        Else
            SelectedIndex = Index
        End If
        RefreshGame()
    End Sub

    Private Sub FinishRound()
        If Game.Remaining <> 0 Then Return
        Clock.Stop()
        If Clock.Elapsed <= TimeSpan.FromSeconds(70) Then MinigameProgress.Current.RecordCompletion(MinigameProgress.TileMatch)
        RoundNumber += 1
        Game = New TileMatchBoard
        SelectedIndex = -1
        Clock.Reset()
    End Sub

    Private Sub RefreshGame()
        For Index = 0 To Cells.Count - 1
            Dim Cell = Cells(Index), ColorIndex = Game.GetCell(Index)
            Cell.Visibility = If(ColorIndex = 0, Visibility.Hidden, Visibility.Visible)
            Cell.Background = TileBrushes(ColorIndex)
            Cell.BorderThickness = New Thickness(If(Index = SelectedIndex, 3, 0))
            AutomationProperties.SetName(Cell, $"第 {Index \ TileMatchBoard.Width + 1} 行，第 {Index Mod TileMatchBoard.Width + 1} 列，颜色 {ColorIndex}")
        Next
        LabTileMatchRound.Text = $"第 {RoundNumber} 轮"
        LabTileMatchRemaining.Text = $"剩余方块：{Game.Remaining}"
        UpdateTimer()
    End Sub

    Private Sub UpdateTimer()
        If CanPlay() Then
            Clock.Start()
            GameTimer.Start()
        Else
            Clock.Stop()
            GameTimer.Stop()
        End If
        TimerTick(Nothing, EventArgs.Empty)
    End Sub

    Private Sub TimerTick(sender As Object, e As EventArgs)
        LabTileMatchTime.Text = $"本轮用时：{Clock.Elapsed.TotalSeconds.ToString("F2", Globalization.CultureInfo.InvariantCulture)} 秒"
    End Sub

    Private Sub WindowActivationChanged(sender As Object, e As EventArgs)
        UpdateTimer()
    End Sub

    Private Sub PageLoaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded
        IsGamePageActive = True
        HostWindow = Window.GetWindow(Me)
        If HostWindow IsNot Nothing Then
            AddHandler HostWindow.Activated, AddressOf WindowActivationChanged
            AddHandler HostWindow.Deactivated, AddressOf WindowActivationChanged
        End If
        UpdateTimer()
    End Sub

    Private Sub PageUnloaded(sender As Object, e As RoutedEventArgs) Handles Me.Unloaded
        IsGamePageActive = False
        Clock.Stop()
        GameTimer.Stop()
        If HostWindow IsNot Nothing Then
            RemoveHandler HostWindow.Activated, AddressOf WindowActivationChanged
            RemoveHandler HostWindow.Deactivated, AddressOf WindowActivationChanged
            HostWindow = Nothing
        End If
    End Sub

    Private Sub PageLeaving() Handles Me.PageExit
        IsGamePageActive = False
        UpdateTimer()
    End Sub
End Class
