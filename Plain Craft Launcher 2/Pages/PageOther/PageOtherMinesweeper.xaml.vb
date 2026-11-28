Imports System.Diagnostics
Imports System.Windows.Automation
Imports System.Windows.Threading

Public Class PageOtherMinesweeper
    Private Game As MinesweeperBoard
    Private ReadOnly Cells As New List(Of Button)
    Private ReadOnly Clock As New Stopwatch
    Private ReadOnly GameTimer As DispatcherTimer
    Private IsGamePageActive As Boolean

    Public Sub New()
        InitializeComponent()
        GameTimer = New DispatcherTimer With {.Interval = TimeSpan.FromMilliseconds(10)}
        AddHandler GameTimer.Tick, AddressOf TimerTick
        StartNewGame()
    End Sub

    Private Sub StartNewGame()
        If GameTimer Is Nothing Then Return
        GameTimer.Stop()
        Clock.Reset()
        Select Case ComboMineDifficulty.SelectedIndex
            Case 1 : Game = New MinesweeperBoard(16, 16, 40)
            Case Else : Game = New MinesweeperBoard(9, 9, 10)
        End Select
        PanMineBoard.Children.Clear()
        Cells.Clear()
        PanMineBoard.Columns = Game.Width
        PanMineBoard.Rows = Game.Height
        PanMineBoard.Width = Game.Width * 30
        PanMineBoard.Height = Game.Height * 30
        For Index = 0 To Game.Width * Game.Height - 1
            Dim Cell As New Button With {.Tag = Index, .Style = CType(FindResource("MineCellStyle"), Style)}
            AddHandler Cell.Click, AddressOf RevealCell
            AddHandler Cell.PreviewMouseRightButtonDown, AddressOf FlagCell
            Cells.Add(Cell)
            PanMineBoard.Children.Add(Cell)
        Next
        MineBoardScroll.ScrollToLeftEnd()
        RefreshGame()
    End Sub

    Private Sub DifficultyChanged(sender As Object, e As SelectionChangedEventArgs) Handles ComboMineDifficulty.SelectionChanged
        StartNewGame()
    End Sub

    Private Sub Restart(sender As Object, e As EventArgs) Handles BtnMineRestart.Click
        StartNewGame()
    End Sub

    Private Sub RevealCell(sender As Object, e As RoutedEventArgs)
        If Game.Reveal(CInt(CType(sender, Button).Tag)) Then RefreshGame()
    End Sub

    Private Sub FlagCell(sender As Object, e As MouseButtonEventArgs)
        e.Handled = True
        If Game.ToggleFlag(CInt(CType(sender, Button).Tag)) Then RefreshGame()
    End Sub

    Private Sub RefreshGame()
        UpdateTimer()
        If Game.State = MinesweeperState.Won AndAlso Clock.Elapsed <= TimeSpan.FromSeconds(7) Then
            MinigameProgress.Current.RecordCompletion(MinigameProgress.Minesweeper)
        End If
        Dim Finished = Game.State = MinesweeperState.Won OrElse Game.State = MinesweeperState.Lost
        For Index = 0 To Cells.Count - 1
            Dim Data = Game.GetCell(Index), Cell = Cells(Index)
            Dim Caption As String = "", Description As String = "未翻开"
            Dim Background = "ColorBrush6", Foreground = "ColorBrush1"
            If Finished AndAlso Data.HasMine Then
                Caption = If(Game.State = MinesweeperState.Won OrElse Data.IsFlagged, "⚑", "✹")
                Description = "地雷"
                Foreground = "ColorBrushHintRedText"
                If Index = Game.ExplodedIndex Then Background = "ColorBrushHintRedBackground"
            ElseIf Finished AndAlso Data.IsFlagged AndAlso Not Data.HasMine Then
                Caption = "×" : Description = "标记错误" : Foreground = "ColorBrushHintRedText"
            ElseIf Data.IsFlagged Then
                Caption = "⚑" : Description = "已插旗" : Foreground = "ColorBrushHintRedText"
            ElseIf Data.IsRevealed Then
                Caption = If(Data.AdjacentMines = 0, "", Data.AdjacentMines.ToString())
                Description = If(Data.AdjacentMines = 0, "空白", $"周围有 {Data.AdjacentMines} 个雷")
                Background = "ColorBrushCardBackground"
                Select Case Data.AdjacentMines
                    Case 1 : Foreground = "ColorBrush3"
                    Case 3 : Foreground = "ColorBrushHintRedText"
                    Case 4 : Foreground = "ColorBrushHintBlueText"
                    Case 5 : Foreground = "ColorBrushHintYellowText"
                    Case 6 : Foreground = "ColorBrush2"
                End Select
            End If
            Cell.Content = Caption
            Cell.SetResourceReference(Control.BackgroundProperty, Background)
            Cell.SetResourceReference(Control.ForegroundProperty, Foreground)
            AutomationProperties.SetName(Cell, $"第 {Index \ Game.Width + 1} 行，第 {Index Mod Game.Width + 1} 列，{Description}")
        Next
        LabMineRemaining.Text = $"剩余雷数：{Game.MineCount - Game.FlagCount}"
        Select Case Game.State
            Case MinesweeperState.Ready : LabMineStatus.Text = "翻开任意一格，开始扫雷。"
            Case MinesweeperState.Playing : LabMineStatus.Text = "仔细观察数字，找出所有安全格。"
            Case MinesweeperState.Won : LabMineStatus.Text = "全部安全格已找到，你赢了！"
            Case MinesweeperState.Lost : LabMineStatus.Text = "踩到地雷了，再来一局吧。"
        End Select
    End Sub

    Private Sub UpdateTimer()
        If Game.State = MinesweeperState.Playing AndAlso IsGamePageActive Then
            Clock.Start()
            GameTimer.Start()
        Else
            Clock.Stop()
            GameTimer.Stop()
        End If
        TimerTick(Nothing, EventArgs.Empty)
    End Sub

    Private Sub TimerTick(sender As Object, e As EventArgs)
        LabMineTime.Text = $"用时：{Clock.Elapsed.TotalSeconds.ToString("F2", Globalization.CultureInfo.InvariantCulture)} 秒"
    End Sub

    Private Sub PageLoaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded
        IsGamePageActive = True
        UpdateTimer()
    End Sub

    Private Sub PageUnloaded(sender As Object, e As RoutedEventArgs) Handles Me.Unloaded
        IsGamePageActive = False
        Clock.Stop()
        GameTimer.Stop()
    End Sub
End Class
