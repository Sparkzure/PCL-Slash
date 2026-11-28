Imports System.Windows.Media.Animation
Imports System.Windows.Threading

''' <summary>点击切换主题或明暗模式时，以柔边圆形揭开新配色。</summary>
Friend NotInheritable Class ThemeTransition
    Private Sub New()
    End Sub

    Private NotInheritable Class Reveal
        Public Root As Grid
        Public Snapshot As RenderTargetBitmap
        Public Origin As Point
        Public Size As Size
        Public Overlay As Image
        Public Mask As RadialGradientBrush
    End Class

    Private Shared Pending As Reveal
    Private Shared Active As Reveal

    Friend Shared Sub Prepare(Root As Grid, Origin As Point)
        Pending = Nothing
        If Root Is Nothing OrElse Not Root.IsLoaded OrElse Not Root.IsVisible OrElse AniControlEnabled <> 0 OrElse AniSpeed >= 200 Then Return
        Dim Width = Root.ActualWidth, Height = Root.ActualHeight
        If Width <= 0 OrElse Height <= 0 Then Return
        Try
            Dim Dpi = VisualTreeHelper.GetDpi(Root)
            Dim PixelWidth = Math.Ceiling(Width * Dpi.DpiScaleX)
            Dim PixelHeight = Math.Ceiling(Height * Dpi.DpiScaleY)
            If PixelWidth * PixelHeight > 16777216 Then Return
            '连续切换时连同当前遮罩一起截图，避免先跳到上一次动画的终点。
            Dim Snapshot As New RenderTargetBitmap(CInt(PixelWidth), CInt(PixelHeight), Dpi.PixelsPerInchX, Dpi.PixelsPerInchY, PixelFormats.Pbgra32)
            Snapshot.Render(Root)
            Snapshot.Freeze()
            Dim Prepared As New Reveal With {
                .Root = Root, .Snapshot = Snapshot, .Size = New Size(Width, Height),
                .Origin = New Point(Math.Max(0, Math.Min(Width, Origin.X)), Math.Max(0, Math.Min(Height, Origin.Y)))}
            Pending = Prepared
            '鼠标抬起后若未触发设置改变，不把这次点击带到之后的程序化刷新。
            Root.Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, New Action(
                Sub()
                    If ReferenceEquals(Pending, Prepared) Then Pending = Nothing
                End Sub))
        Catch ex As Exception
            Logger.Warn(ex, "准备主题过渡失败")
        End Try
    End Sub

    Friend Shared Sub Apply(RefreshTheme As Action)
        Dim Prepared = Pending
        Pending = Nothing
        Finish(Active)
        RefreshTheme()
        If Prepared Is Nothing OrElse Not Prepared.Root.IsLoaded OrElse Not Prepared.Root.IsVisible OrElse
           Prepared.Root.RenderSize <> Prepared.Size OrElse AniControlEnabled <> 0 OrElse AniSpeed >= 200 Then Return
        Try
            Dim FarX = Math.Max(Prepared.Origin.X, Prepared.Size.Width - Prepared.Origin.X)
            Dim FarY = Math.Max(Prepared.Origin.Y, Prepared.Size.Height - Prepared.Origin.Y)
            Dim Radius = Math.Sqrt(FarX * FarX + FarY * FarY) / 0.85 + 2
            Prepared.Mask = New RadialGradientBrush With {
                .MappingMode = BrushMappingMode.Absolute, .Center = Prepared.Origin, .GradientOrigin = Prepared.Origin,
                .RadiusX = 0.1, .RadiusY = 0.1}
            Prepared.Mask.GradientStops.Add(New GradientStop(Colors.Transparent, 0.85))
            Prepared.Mask.GradientStops.Add(New GradientStop(Colors.White, 1))
            Prepared.Overlay = New Image With {
                .Source = Prepared.Snapshot, .OpacityMask = Prepared.Mask, .Stretch = Stretch.Fill,
                .IsHitTestVisible = False, .Focusable = False}
            Grid.SetRowSpan(Prepared.Overlay, Math.Max(1, Prepared.Root.RowDefinitions.Count))
            Grid.SetColumnSpan(Prepared.Overlay, Math.Max(1, Prepared.Root.ColumnDefinitions.Count))
            Panel.SetZIndex(Prepared.Overlay, Integer.MaxValue)
            Active = Prepared
            Prepared.Root.Children.Add(Prepared.Overlay)
            AddHandler Prepared.Root.SizeChanged, AddressOf RootSizeChanged
            AddHandler Prepared.Root.Unloaded, AddressOf RootUnloaded
            Dim Animation As New DoubleAnimation(0.1, Radius, TimeSpan.FromMilliseconds(750 / AniSpeed)) With {
                .EasingFunction = New CubicEase With {.EasingMode = EasingMode.EaseOut}}
            Dim VerticalAnimation = Animation.Clone()
            AddHandler Animation.Completed, Sub() Finish(Prepared)
            Prepared.Mask.BeginAnimation(RadialGradientBrush.RadiusXProperty, Animation)
            Prepared.Mask.BeginAnimation(RadialGradientBrush.RadiusYProperty, VerticalAnimation)
        Catch ex As Exception
            Finish(Prepared)
            Logger.Warn(ex, "播放主题过渡失败")
        End Try
    End Sub

    Friend Shared Sub Cancel()
        Pending = Nothing
        Finish(Active)
    End Sub

    Private Shared Sub RootSizeChanged(Sender As Object, e As SizeChangedEventArgs)
        Finish(Active)
    End Sub

    Private Shared Sub RootUnloaded(Sender As Object, e As RoutedEventArgs)
        Finish(Active)
    End Sub

    Private Shared Sub Finish(State As Reveal)
        If State Is Nothing OrElse Not ReferenceEquals(Active, State) Then Return
        Active = Nothing
        RemoveHandler State.Root.SizeChanged, AddressOf RootSizeChanged
        RemoveHandler State.Root.Unloaded, AddressOf RootUnloaded
        State.Mask.BeginAnimation(RadialGradientBrush.RadiusXProperty, Nothing)
        State.Mask.BeginAnimation(RadialGradientBrush.RadiusYProperty, Nothing)
        State.Root.Children.Remove(State.Overlay)
        State.Overlay.OpacityMask = Nothing
        State.Overlay.Source = Nothing
        State.Snapshot = Nothing
    End Sub
End Class
