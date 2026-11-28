Public Class PageOtherTest

    Private Sub OpenTileMatch(sender As Object, e As EventArgs) Handles BtnTileMatch.Click
        FrmMain.PageChange(FormMain.PageType.TileMatch)
    End Sub

    Private Sub OpenTetris(sender As Object, e As EventArgs) Handles BtnTetris.Click
        FrmMain.PageChange(FormMain.PageType.Tetris)
    End Sub

    Private Sub OpenMinesweeper(sender As Object, e As EventArgs) Handles BtnMinesweeper.Click
        FrmMain.PageChange(FormMain.PageType.Minesweeper)
    End Sub

    Public Shared Sub StartCustomDownload(Url As String, FileName As String, Optional Folder As String = Nothing)
        Hint("尚未实现自定义下载事件。", HintType.Red)
    End Sub
    Public Shared Sub Jrrp()
        Hint("尚未实现今日人品事件。", HintType.Red)
    End Sub
    Public Shared Sub RubbishClear()
        Hint("尚未实现垃圾清理功能。", HintType.Red)
    End Sub
    Public Shared Sub MemoryOptimize(ShowHint As Boolean)
        If ShowHint Then Hint("尚未实现内存优化功能。", HintType.Red)
    End Sub
    Public Shared Sub MemoryOptimizeInternal(ShowHint As Boolean)
        If ShowHint Then Hint("尚未实现内存优化功能。", HintType.Red)
    End Sub
    Public Shared Function GetRandomCave() As String
        Return String.Empty
    End Function
    Public Shared Function GetRandomHint() As String
        Return String.Empty
    End Function
    Public Shared Function GetRandomPresetHint() As String
        Return String.Empty
    End Function

End Class
