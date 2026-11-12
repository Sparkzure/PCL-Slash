' 鸣谢内容移自 PageOtherAbout，保留原内容来源。
Public Class PageOtherCredits
    Public Sub New()
        InitializeComponent()
    End Sub
    Private Sub PageLoaded(sender As Object, e As RoutedEventArgs) Handles Me.Loaded
        PanBack.ScrollToHome()
    End Sub
End Class
