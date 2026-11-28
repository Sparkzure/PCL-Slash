''' <summary>按小游戏保存达标记录；所有已登记的小游戏均通关后解锁活跃橙。</summary>
Friend NotInheritable Class MinigameProgress
    Friend Const Minesweeper As String = "minesweeper"
    Friend Const Tetris As String = "tetris"
    '新增小游戏时在此登记稳定的名称，由对应页面在满足自身通关条件后记录完成。
    Friend Shared ReadOnly Current As New MinigameProgress({Minesweeper, Tetris})

    Private ReadOnly RegisteredGames As HashSet(Of String)
    Private ReadOnly Gate As New Object

    Friend Sub New(GameKeys As IEnumerable(Of String))
        RegisteredGames = New HashSet(Of String)(GameKeys, StringComparer.Ordinal)
        If RegisteredGames.Count = 0 OrElse RegisteredGames.Any(Function(Key) String.IsNullOrWhiteSpace(Key)) Then
            Throw New ArgumentException("小游戏清单不能为空，也不能包含空名称。", NameOf(GameKeys))
        End If
    End Sub

    Friend Function RecordCompletion(GameKey As String) As Boolean
        If Not RegisteredGames.Contains(GameKey) Then Return False
        SyncLock Gate
            Dim Completed As New HashSet(Of String)(StringComparer.Ordinal)
            Try
                For Each Value In JArray.Parse(Settings.Get(Of String)("ToolMinigameCompleted"))
                    If Value.Type = JTokenType.String AndAlso RegisteredGames.Contains(Value.ToString()) Then Completed.Add(Value.ToString())
                Next
            Catch ex As Newtonsoft.Json.JsonException
                '损坏的记录不授予额外进度，当前这次通关仍可重新记录。
            End Try
            Dim Added = Completed.Add(GameKey)
            If Added Then
                Dim Saved = New JArray(Completed.OrderBy(Function(Key) Key, StringComparer.Ordinal)).ToString(Newtonsoft.Json.Formatting.None)
                Settings.Set("ToolMinigameCompleted", Saved)
                If Settings.Get(Of String)("ToolMinigameCompleted") <> Saved Then Return False
            End If
            If RegisteredGames.All(Function(Key) Completed.Contains(Key)) Then
                ThemeUnlock(LauncherTheme.ActiveOrange, False, "隐藏主题 活跃橙 已解锁！")
            End If
            Return Added
        End SyncLock
    End Function
End Class
