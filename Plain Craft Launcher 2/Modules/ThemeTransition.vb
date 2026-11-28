Imports System.Windows.Media.Animation
Imports System.Windows.Threading

''' <summary>点击切换主题或明暗模式时，以柔边圆形揭开新配色。</summary>
Friend NotInheritable Class ThemeTransition
    Private Sub New()
    End Sub

    Private NotInheritable Class Reveal
        Public Frame As Grid
        Public Layer As Canvas
        Public Content As FrameworkElement
        Public Snapshot As RenderTargetBitmap
        Public Origin As Point
        Public Size As Size
        Public ContentSize As Size
        Public Clip As Geometry
        Public Overlay As Image
        Public Mask As RadialGradientBrush
    End Class

    Private Shared Pending As Reveal
    Private Shared Active As Reveal

    Friend Shared Sub Prepare(Layer As Canvas, Content As FrameworkElement, Origin As Point)
        Pending = Nothing
        If Layer Is Nothing OrElse Content Is Nothing OrElse Not Layer.IsLoaded OrElse Not Layer.IsVisible OrElse
           AniControlEnabled <> 0 OrElse AniSpeed >= 200 Then Return
        '最外层 Frame 和专用 Canvas 共用窗口坐标，不让截图参与原界面的测量或布局。
        Dim Frame = TryCast(Layer.Parent, Grid)
        If Frame Is Nothing OrElse Window.GetWindow(Frame)?.Content IsNot Frame Then Return
        Try
            Frame.UpdateLayout()
            Dim Width = Frame.ActualWidth, Height = Frame.ActualHeight
            If Width <= 0 OrElse Height <= 0 Then Return
            Dim Dpi = VisualTreeHelper.GetDpi(Frame)
            Dim PixelWidth = Math.Ceiling(Width * Dpi.DpiScaleX)
            Dim PixelHeight = Math.Ceiling(Height * Dpi.DpiScaleY)
            If PixelWidth * PixelHeight > 16777216 Then Return
            Dim ContentToFrame = TryCast(Content.TransformToAncestor(Frame), Transform)
            If ContentToFrame Is Nothing Then Return
            Dim Clip = If(Content.Clip, New RectangleGeometry(New Rect(Content.RenderSize))).CloneCurrentValue()
            Dim ClipTransforms As New TransformGroup
            ClipTransforms.Children.Add(Clip.Transform)
            ClipTransforms.Children.Add(ContentToFrame)
            Clip.Transform = ClipTransforms
            Clip.Freeze()
            '连续切换时连同当前遮罩一起截图，避免先跳到上一次动画的终点。
            '只截窗口内容，避免将窗口透明度再次叠加到旧画面上。
            Dim Snapshot As New RenderTargetBitmap(CInt(PixelWidth), CInt(PixelHeight), Dpi.PixelsPerInchX, Dpi.PixelsPerInchY, PixelFormats.Pbgra32)
            Snapshot.Render(Frame)
            Snapshot.Freeze()
            Dim Prepared As New Reveal With {
                .Frame = Frame, .Layer = Layer, .Content = Content, .Clip = Clip, .ContentSize = Content.RenderSize,
                .Snapshot = Snapshot, .Size = Frame.RenderSize,
                .Origin = New Point(Math.Max(0, Math.Min(Width, Origin.X)), Math.Max(0, Math.Min(Height, Origin.Y)))}
            Pending = Prepared
            '鼠标抬起后若未触发设置改变，不把这次点击带到之后的程序化刷新。
            Frame.Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, New Action(
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
        If Prepared Is Nothing OrElse Not Prepared.Layer.IsLoaded OrElse Not Prepared.Layer.IsVisible OrElse
           Prepared.Frame.RenderSize <> Prepared.Size OrElse Prepared.Content.RenderSize <> Prepared.ContentSize OrElse
           AniControlEnabled <> 0 OrElse AniSpeed >= 200 Then Return
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
                .Source = Prepared.Snapshot, .Width = Prepared.Snapshot.Width, .Height = Prepared.Snapshot.Height,
                .Stretch = Stretch.Fill, .UseLayoutRounding = False, .SnapsToDevicePixels = False,
                .IsHitTestVisible = False, .Focusable = False}
            Active = Prepared
            Prepared.Layer.Clip = Prepared.Clip
            Prepared.Layer.OpacityMask = Prepared.Mask
            Prepared.Layer.Children.Add(Prepared.Overlay)
            AddHandler Prepared.Frame.SizeChanged, AddressOf ViewportSizeChanged
            AddHandler Prepared.Content.SizeChanged, AddressOf ViewportSizeChanged
            AddHandler Prepared.Layer.Unloaded, AddressOf LayerUnloaded
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

    Private Shared Sub ViewportSizeChanged(Sender As Object, e As SizeChangedEventArgs)
        Finish(Active)
    End Sub

    Private Shared Sub LayerUnloaded(Sender As Object, e As RoutedEventArgs)
        Finish(Active)
    End Sub

    Private Shared Sub Finish(State As Reveal)
        If State Is Nothing OrElse Not ReferenceEquals(Active, State) Then Return
        Active = Nothing
        RemoveHandler State.Frame.SizeChanged, AddressOf ViewportSizeChanged
        RemoveHandler State.Content.SizeChanged, AddressOf ViewportSizeChanged
        RemoveHandler State.Layer.Unloaded, AddressOf LayerUnloaded
        State.Mask.BeginAnimation(RadialGradientBrush.RadiusXProperty, Nothing)
        State.Mask.BeginAnimation(RadialGradientBrush.RadiusYProperty, Nothing)
        State.Layer.Children.Remove(State.Overlay)
        State.Layer.OpacityMask = Nothing
        State.Layer.Clip = Nothing
        State.Overlay.Source = Nothing
        State.Snapshot = Nothing
    End Sub
End Class
