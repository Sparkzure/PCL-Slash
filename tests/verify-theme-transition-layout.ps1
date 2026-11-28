param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool/cache/theme-transition-layout-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL/Portable.json'), '{}', [Text.UTF8Encoding]::new($false))
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$env:TEMP = $testRoot
$env:TMP = $testRoot
$application = $null
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2/bin/Plain Craft Launcher Slash.exe'))
    Add-Type -AssemblyName PresentationFramework
    $application = [Windows.Application]::new()
    $application.ShutdownMode = [Windows.ShutdownMode]::OnExplicitShutdown
    $resources = [Resources.ResourceManager]::new('PCL.Resources', $assembly)
    foreach ($name in @('Newtonsoft.Json', 'ThrottleDebounce')) {
        [Reflection.Assembly]::Load([byte[]]$resources.GetObject($name)) | Out-Null
    }
    foreach ($name in @('MeloongCore', 'MeloongCore.Wpf')) {
        [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot ('Plain Craft Launcher 2/bin/' + $name + '.dll'))) | Out-Null
    }
    function Get-StandaloneMarkup($document, $node) {
        $copy = $node.CloneNode($true)
        foreach ($attribute in $document.DocumentElement.Attributes) {
            if ($attribute.Name -eq 'xmlns' -or $attribute.Prefix -eq 'xmlns') { $copy.SetAttribute($attribute.Name, $attribute.Value) }
        }
        return $copy.OuterXml.Replace('clr-namespace:PCL"', ('clr-namespace:PCL;assembly=' + $assembly.GetName().Name + '"'))
    }
    # Load the real brushes and window template into a plain host, without launcher Startup or loaders.
    $appXml = [xml][IO.File]::ReadAllText((Join-Path $repoRoot 'Plain Craft Launcher 2/Application.xaml'), [Text.Encoding]::UTF8)
    foreach ($node in $appXml.DocumentElement.FirstChild.FirstChild.ChildNodes) {
        if ($node -isnot [Xml.XmlElement] -or $node.LocalName -notin @('Color', 'SolidColorBrush')) { continue }
        $key = $node.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml')
        $copy = $node.CloneNode($true)
        $copy.RemoveAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml')
        $application.Resources[$key] = [Windows.Markup.XamlReader]::Parse((Get-StandaloneMarkup $appXml $copy))
    }
    $windowStyle = $appXml.SelectSingleNode('//*[@*[local-name()="Key"]="MyWindow"]')
    $application.Resources['MyWindow'] = [Windows.Markup.XamlReader]::Parse((Get-StandaloneMarkup $appXml $windowStyle))
    $assembly.GetType('PCL.ModSecret').GetMethod('ThemeRefresh').Invoke($null, @($null))
    $mainXml = [xml][IO.File]::ReadAllText((Join-Path $repoRoot 'Plain Craft Launcher 2/FormMain.xaml'), [Text.Encoding]::UTF8)
    $ns = [Xml.XmlNamespaceManager]::new($mainXml.NameTable)
    $ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $frameNode = $mainXml.SelectSingleNode('//*[@x:Name="PanWindow"]', $ns)
    $frame = [Windows.Markup.XamlReader]::Parse((Get-StandaloneMarkup $mainXml $frameNode))
    # The startup animation removes this transform before ordinary theme selection.
    $frame.FindName('PanBack').RenderTransform = $null
    $references = @('System.dll', 'System.Core.dll', [Windows.DependencyObject].Assembly.Location,
        [Windows.Media.Visual].Assembly.Location, [Windows.Window].Assembly.Location, [Windows.Markup.MarkupExtension].Assembly.Location)
    Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

public static class ThemeTransitionLayoutRegression {
    static readonly BindingFlags Flags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
    static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    static void Pump(int ms) {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ms) };
        timer.Tick += delegate { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
    static RenderTargetBitmap Capture(Grid frame) {
        frame.UpdateLayout();
        var dpi = VisualTreeHelper.GetDpi(frame);
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(frame.ActualWidth * dpi.DpiScaleX),
            (int)Math.Ceiling(frame.ActualHeight * dpi.DpiScaleY), dpi.PixelsPerInchX, dpi.PixelsPerInchY, PixelFormats.Pbgra32);
        bitmap.Render(frame); bitmap.Freeze(); return bitmap;
    }
    static Color Pixel(BitmapSource bitmap, Point point) {
        var bytes = new byte[4];
        bitmap.CopyPixels(new Int32Rect((int)Math.Floor(point.X * bitmap.DpiX / 96),
            (int)Math.Floor(point.Y * bitmap.DpiY / 96), 1, 1), bytes, 4, 0);
        return Color.FromArgb(bytes[3], bytes[2], bytes[1], bytes[0]);
    }
    static bool Near(Color a, Color b) { return Math.Abs(a.A - b.A) + Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) <= 12; }
    public static void Run(Assembly assembly, Grid frame, string previewPath) {
        var transition = assembly.GetType("PCL.ThemeTransition");
        var set = assembly.GetType("PCL.Settings").GetMethod("Set");
        Action<bool> dark = value => set.Invoke(null, new object[] { "UiThemeDarkMode", value, null });
        Action cancel = () => transition.GetMethod("Cancel", Flags).Invoke(null, null);
        var root = (Grid)frame.FindName("PanForm");
        var boundary = (Border)frame.FindName("BorderForm");
        var layer = (Canvas)frame.FindName("PanThemeTransition");
        var content = (Grid)frame.FindName("PanMain");
        var title = (Grid)frame.FindName("PanTitle");
        var left = (Border)frame.FindName("PanMainLeft");
        var right = (Border)frame.FindName("PanMainRight");
        root.SetResourceReference(Panel.BackgroundProperty, "ColorBrushGray8");
        left.Width = 150; left.Background = Brushes.White;
        var body = new Grid(); body.SetResourceReference(Panel.BackgroundProperty, "ColorBrushGray8"); right.Child = body;
        for (int i = 0; i < 5; i++) body.Children.Add(new Border {
            Background = i % 2 == 0 ? Brushes.Red : Brushes.Blue, Width = 8, Height = 260,
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(35 + i * 100, 45, 0, 0) });
        ((Canvas)frame.FindName("ImgBack")).Children.Add(new Border {
            Background = Brushes.Orange, Width = 1100, Height = 700, Margin = new Thickness(-60, -30, 0, 0), Opacity = 0.1 });
        var window = new Window { Content = frame, Width = 850, Height = 500, AllowsTransparency = true,
            Background = Brushes.Transparent, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize,
            Left = -10000, Top = -10000, Opacity = 0.72, ShowActivated = false, ShowInTaskbar = false,
            Style = (Style)Application.Current.Resources["MyWindow"] };
        try {
            set.Invoke(null, new object[] { "SystemDebugAnim", 4, null });
            window.Show();
            foreach (double width in new[] { 850.0, 1024.5 }) {
                window.Width = width; window.Height = width == 850 ? 500 : 640.25;
                window.UpdateLayout();
                // Match FormMain_SizeChanged, including its fractional content size and rounded clip.
                root.Width = boundary.ActualWidth + 0.001; root.Height = boundary.ActualHeight + 0.001;
                content.Width = root.Width; content.Height = root.Height - title.ActualHeight;
                ((RectangleGeometry)boundary.Clip).Rect = new Rect(boundary.RenderSize);
                frame.UpdateLayout(); Pump(30); dark(false);
                var before = Capture(frame);
                var rightPosition = right.TranslatePoint(new Point(), frame);
                var origin = body.TranslatePoint(new Point(260, 350), layer);
                transition.GetMethod("Prepare", Flags).Invoke(null, new object[] { layer, boundary, origin });
                dark(true);
                var start = Capture(frame);
                var image = layer.Children.OfType<Image>().SingleOrDefault();
                Check(image != null && !layer.IsHitTestVisible && !image.IsHitTestVisible, "Dedicated overlay is missing or blocks input");
                Check(VisualTreeHelper.GetOffset(frame) == new Vector() && VisualTreeHelper.GetOffset(layer) == new Vector() &&
                    VisualTreeHelper.GetOffset(image) == new Vector(), "Frame, mask and screenshot do not share the window origin");
                Check(image.Width == image.Source.Width && image.Height == image.Source.Height, "Screenshot was rescaled after pixel rounding");
                Check(title.ActualHeight == 48 && left.ActualWidth == 150 && right.TranslatePoint(new Point(), frame) == rightPosition,
                    "Overlay changed the title or page layout");
                for (int i = 0; i < 5; i++) foreach (int dx in new[] { -4, 4, 12 }) {
                    var point = body.TranslatePoint(new Point(35 + i * 100 + dx, 120), frame);
                    var expected = Pixel(before, point);
                    if (dx == 4) Check(Near(expected, i % 2 == 0 ? Colors.Red : Colors.Blue), "Reference marker is missing or has window opacity applied");
                    Check(Near(Pixel(start, point), expected), "Screenshot shifted in the real main-window layout");
                }
                var outside = new Point(10, 10);
                Check(Near(Pixel(before, outside), Pixel(start, outside)), "Overlay changed the window shadow outside the rounded content");
                Pump(90);
                var middle = Capture(frame);
                var darkColor = ((SolidColorBrush)Application.Current.Resources["ColorBrushGray8"]).Color;
                Check(Near(Pixel(middle, origin), darkColor), "Reveal center is offset in the clipped main window");
                var distant = body.TranslatePoint(new Point(520, 50), frame);
                Check(Near(Pixel(middle, distant), Pixel(before, distant)), "Distant palette changed outside the circle");
                transition.GetMethod("Prepare", Flags).Invoke(null, new object[] { layer, boundary, new Point(30, 35) });
                dark(false);
                Check(Near(Pixel(Capture(frame), origin), Pixel(middle, origin)), "Interrupted reveal jumped or moved the screenshot");
                cancel(); dark(true);
                Check(layer.Children.Count == 0 && layer.Clip == null && layer.OpacityMask == null && image.Source == null, "Overlay retained render state after cleanup");
                if (width == 850 && !String.IsNullOrEmpty(previewPath)) {
                    var end = Capture(frame);
                    var drawing = new DrawingVisual();
                    using (var context = drawing.RenderOpen()) {
                        context.DrawImage(start, new Rect(0, 0, 850, 500));
                        context.DrawImage(middle, new Rect(850, 0, 850, 500));
                        context.DrawImage(end, new Rect(1700, 0, 850, 500));
                    }
                    var preview = new RenderTargetBitmap(2550, 500, 96, 96, PixelFormats.Pbgra32); preview.Render(drawing);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(preview));
                    using (var stream = File.Create(previewPath)) encoder.Save(stream);
                }
            }
        } finally { cancel(); window.Content = null; window.Close(); }
    }
}
'@
    [ThemeTransitionLayoutRegression]::Run($assembly, $frame, $PreviewPath)
    Write-Output 'PASS: real FormMain XAML, shared window origin, native bitmap size, fractional window dimensions, stable title/sidebar/page layout, rounded content clip, overflow, window opacity, reveal origin, interrupted reveal and cleanup.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
