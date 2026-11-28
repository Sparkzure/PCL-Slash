Imports System.Windows.Threading

Public Class PageOtherTetris
    Private Game As New TetrisBoard
    Private ReadOnly Cells As New List(Of Border)
    Private ReadOnly PreviewCells As New List(Of Border)
    Private ReadOnly GameTimer As DispatcherTimer
    Private HostWindow As Window
    Private IsGamePageActive As Boolean
    Private Shared ReadOnly PieceBrushes As Brush() = {
        Brushes.Transparent, New SolidColorBrush(Color.FromRgb(38, 198, 218)), New SolidColorBrush(Color.FromRgb(244, 197, 66)),
        New SolidColorBrush(Color.FromRgb(171, 120, 232)), New SolidColorBrush(Color.FromRgb(107, 203, 119)),
        New SolidColorBrush(Color.FromRgb(239, 104, 104)), New SolidColorBrush(Color.FromRgb(98, 147, 245)), New SolidColorBrush(Color.FromRgb(242, 166, 90))}

    Public Sub New()
        InitializeComponent()
        For Index = 0 To TetrisBoard.Width * TetrisBoard.Height - 1
            Dim Cell = CreateCell()
            Cells.Add(Cell)
            PanTetrisBoard.Children.Add(Cell)
        Next
        For Index = 0 To 15
            Dim Cell = CreateCell()
            PreviewCells.Add(Cell)
            PanTetrisNext.Children.Add(Cell)
        Next
        GameTimer = New DispatcherTimer With {.Interval = TimeSpan.FromMilliseconds(500)}
        AddHandler GameTimer.Tick, AddressOf TimerTick
        RefreshGame()
    End Sub

    Private Shared Function CreateCell() As Border
        Dim Cell As New Border With {.Margin = New Thickness(1), .CornerRadius = New CornerRadius(2), .BorderThickness = New Thickness(0.5)}
        Cell.SetResourceReference(Border.BorderBrushProperty, "ColorBrushGray6")
        Return Cell
    End Function

    Private Sub StartNewGame(sender As Object, e As EventArgs) Handles BtnTetrisRestart.Click
        GameTimer.Stop()
        Game = New TetrisBoard
        Game.Start()
        RefreshGame()
        FocusGame()
    End Sub

    Private Sub RefreshGame()
        For Row = 0 To TetrisBoard.Height - 1
            For Column = 0 To TetrisBoard.Width - 1
                PaintCell(Cells(Row * TetrisBoard.Width + Column), Game.GetCell(Column, Row))
            Next
        Next
        For Each Cell In Game.GetActiveCells()
            If Cell.Y >= 0 Then PaintCell(Cells(Cell.Y * TetrisBoard.Width + Cell.X), CInt(Game.CurrentPiece))
        Next
        For Each Cell In PreviewCells
            PaintCell(Cell, 0)
        Next
        For Each Cell In Game.GetNextCells()
            PaintCell(PreviewCells(Cell.Y * 4 + Cell.X), CInt(Game.NextPiece))
        Next
        LabTetrisScore.Text = $"得分：{Game.Score}"
        BtnTetrisRestart.Text = If(Game.State = TetrisState.Ready, "开始游戏", "重新开始")
        If Game.Score >= 60 Then MinigameProgress.Current.RecordCompletion(MinigameProgress.Tetris)
        UpdateTimer()
    End Sub

    Private Shared Sub PaintCell(Cell As Border, Piece As Integer)
        If Piece = 0 Then
            Cell.SetResourceReference(Border.BackgroundProperty, "ColorBrushCardBackground")
        Else
            Cell.Background = PieceBrushes(Piece)
        End If
    End Sub

    Private Function CanPlay() As Boolean
        Return IsGamePageActive AndAlso (HostWindow Is Nothing OrElse HostWindow.IsActive) AndAlso Game.State = TetrisState.Playing
    End Function

    Private Sub UpdateTimer()
        If CanPlay() Then
            GameTimer.Start()
        Else
            GameTimer.Stop()
        End If
        Select Case Game.State
            Case TetrisState.Ready : LabTetrisStatus.Text = "准备就绪"
            Case TetrisState.Playing : LabTetrisStatus.Text = If(CanPlay(), "游戏进行中", "已暂停")
            Case TetrisState.Lost : LabTetrisStatus.Text = "游戏结束"
        End Select
    End Sub

    Private Sub TimerTick(sender As Object, e As EventArgs)
        If Not CanPlay() Then
            UpdateTimer()
            Return
        End If
        If Game.Step() Then RefreshGame()
    End Sub

    Private Sub GameKeyDown(sender As Object, e As KeyEventArgs) Handles Me.PreviewKeyDown
        If Not CanPlay() OrElse Keyboard.Modifiers <> ModifierKeys.None Then Return
        Select Case e.Key
            Case Key.Left, Key.A : Game.Move(-1)
            Case Key.Right, Key.D : Game.Move(1)
            Case Key.Up, Key.W
                If Not e.IsRepeat Then Game.Rotate()
            Case Key.Down, Key.S : Game.Step()
            Case Else : Return
        End Select
        e.Handled = True
        RefreshGame()
    End Sub

    Private Sub FocusGame()
        Dispatcher.BeginInvoke(DispatcherPriority.Input, New Action(
            Sub()
                If IsGamePageActive AndAlso (HostWindow Is Nothing OrElse HostWindow.IsActive) Then Keyboard.Focus(Me)
            End Sub))
    End Sub

    Private Sub BoardMouseDown(sender As Object, e As MouseButtonEventArgs) Handles PanTetrisBoard.MouseLeftButtonDown
        FocusGame()
    End Sub

    Private Sub WindowActivated(sender As Object, e As EventArgs)
        UpdateTimer()
        FocusGame()
    End Sub

    Private Sub WindowDeactivated(sender As Object, e As EventArgs)
        UpdateTimer()
    End Sub

    Private Sub PageLoaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded
        IsGamePageActive = True
        HostWindow = Window.GetWindow(Me)
        If HostWindow IsNot Nothing Then
            AddHandler HostWindow.Activated, AddressOf WindowActivated
            AddHandler HostWindow.Deactivated, AddressOf WindowDeactivated
        End If
        UpdateTimer()
        FocusGame()
    End Sub

    Private Sub PageUnloaded(sender As Object, e As RoutedEventArgs) Handles Me.Unloaded
        IsGamePageActive = False
        GameTimer.Stop()
        If HostWindow IsNot Nothing Then
            RemoveHandler HostWindow.Activated, AddressOf WindowActivated
            RemoveHandler HostWindow.Deactivated, AddressOf WindowDeactivated
            HostWindow = Nothing
        End If
    End Sub

    Private Sub PageLeaving() Handles Me.PageExit
        IsGamePageActive = False
        UpdateTimer()
    End Sub
End Class
