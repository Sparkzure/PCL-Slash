param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool/cache/theme-transition-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL/Portable.json'), '{}', [Text.UTF8Encoding]::new($false))
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2/bin/Plain Craft Launcher Slash.exe'))
    Add-Type -AssemblyName PresentationFramework
    # Pump real WPF frames with a plain host; never queue the launcher's Startup handler.
    $application = [Windows.Application]::new()
    $application.ShutdownMode = [Windows.ShutdownMode]::OnExplicitShutdown
    $resources = [Resources.ResourceManager]::new('PCL.Resources', $assembly)
    foreach ($dependency in @('Newtonsoft.Json', 'ThrottleDebounce')) {
        [Reflection.Assembly]::Load([byte[]]$resources.GetObject($dependency)) | Out-Null
    }
    $assembly.GetType('PCL.ModSecret').GetMethod('ThemeRefresh').Invoke($null, @($null))
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

public static class ThemeTransitionRegression {
    static readonly BindingFlags Flags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
    static Type transition;
    static MethodInfo set;
    static Grid root;
    static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    static void Set(string key, object value) { set.Invoke(null, new object[] { key, value, null }); }
    static void Dark(bool value) { Set("UiThemeDarkMode", value); }
    static void Prepare(Point origin) { transition.GetMethod("Prepare", Flags).Invoke(null, new object[] { root, origin }); }
    static void Cancel() { transition.GetMethod("Cancel", Flags).Invoke(null, null); }
    static Image Overlay() { return root.Children.OfType<Image>().SingleOrDefault(); }
    static bool Near(Color a, Color b) { return Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) <= 9; }
    static void Pump(int milliseconds) {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.ApplicationIdle);
        timer.Interval = TimeSpan.FromMilliseconds(milliseconds);
        timer.Tick += delegate { timer.Stop(); frame.Continue = false; };
        timer.Start();
        Dispatcher.PushFrame(frame);
        timer.Stop();
    }
    static RenderTargetBitmap Capture() {
        root.UpdateLayout();
        var frame = new RenderTargetBitmap((int)root.ActualWidth, (int)root.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        frame.Render(root);
        frame.Freeze();
        return frame;
    }
    static Color Pixel(BitmapSource frame, int x, int y) {
        var bytes = new byte[4];
        frame.CopyPixels(new Int32Rect(x, y, 1, 1), bytes, 4, 0);
        return Color.FromArgb(bytes[3], bytes[2], bytes[1], bytes[0]);
    }
    public static void Run(Assembly assembly, string previewPath) {
        transition = assembly.GetType("PCL.ThemeTransition", true);
        set = assembly.GetType("PCL.Settings", true).GetMethod("Set");
        root = new Grid();
        root.SetResourceReference(Panel.BackgroundProperty, "ColorBrushGray8");
        var caption = new TextBlock { Text = "Theme transition", Margin = new Thickness(20), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
        caption.SetResourceReference(TextBlock.ForegroundProperty, "ColorBrush1");
        root.Children.Add(caption);
        var window = new Window { Content = root, Width = 640, Height = 360, WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize, Left = -10000, Top = -10000, Opacity = 0, ShowActivated = false, ShowInTaskbar = false };
        try {
            Set("SystemDebugAnim", 4);
            Dark(false);
            window.Show();
            window.UpdateLayout();
            Pump(30);
            var light = Capture();
            var lightColor = Pixel(light, 600, 320);
            var origin = new Point(70, 90);
            Prepare(origin);
            Dark(true);
            root.UpdateLayout();
            var overlay = Overlay();
            Check(overlay != null && !overlay.IsHitTestVisible && !overlay.Focusable, "Transition blocks input or failed to start through the real setting callback");
            var mask = overlay.OpacityMask as RadialGradientBrush;
            Check(mask != null && mask.HasAnimatedProperties && mask.Center == origin && mask.GradientOrigin == origin, "Reveal is not animated from the click position");
            Check(mask.MappingMode == BrushMappingMode.Absolute && Math.Abs(mask.RadiusX - mask.RadiusY) < 0.01, "Reveal is distorted instead of circular");
            var start = Capture();
            Pump(80);
            var radius = mask.RadiusX;
            Check(radius > 10 && Math.Abs(mask.RadiusY - radius) < 0.01, "Circle did not expand on real WPF animation frames");
            var middle = Capture();
            var darkColor = ((SolidColorBrush)Application.Current.Resources["ColorBrushGray8"]).Color;
            Check(Near(Pixel(middle, 70, 90), darkColor), "New palette is not revealed at the click position");
            Check(Near(Pixel(middle, 600, 320), lightColor), "Distant pixels changed before the circle reached them");
            int edgeX = (int)Math.Round(origin.X + radius * 0.925);
            Check(edgeX < middle.PixelWidth, "Soft-edge sample is outside the frame");
            var edge = Pixel(middle, edgeX, 90);
            Check(edge.R > darkColor.R + 5 && edge.R < lightColor.R - 5, "The expanding circle has a hard edge instead of a feathered transition");
            Pump(100);
            Check(mask.RadiusX > radius, "Reveal stopped before covering the window");
            Pump(850);
            Check(Overlay() != null, "Reveal finished before the slower transition duration");
            Pump(700);
            Check(Overlay() == null && overlay.Source == null && overlay.OpacityMask == null, "Completed transition retained its screenshot or overlay");
            var end = Capture();
            Check(Near(Pixel(end, 600, 320), darkColor), "Final frame did not cover the farthest corner");

            Prepare(new Point(200, 120));
            Dark(false);
            Check(Overlay() != null, "Reverse transition did not start");
            Pump(80);
            var beforeReverse = Capture();
            var previous = Overlay();
            Prepare(new Point(450, 180));
            Dark(true);
            root.UpdateLayout();
            Check(Overlay() != null && !Object.ReferenceEquals(previous, Overlay()) && root.Children.OfType<Image>().Count() == 1, "Rapid toggles stacked screenshots");
            Check(previous.Source == null && previous.OpacityMask == null, "Interrupted animation retained its resources");
            Check(Near(Pixel(Capture(), 70, 90), Pixel(beforeReverse, 70, 90)), "Rapid toggle jumped to the previous animation endpoint");
            Dark(false);
            Check(Overlay() == null, "Programmatic change reused an old click or left a stale overlay");

            root.SetResourceReference(Panel.BackgroundProperty, "ColorBrush4");
            foreach (bool darkMode in new[] { false, true }) {
                Dark(darkMode);
                Set("UiThemeSelected", "tianyi-blue");
                var oldTheme = Capture();
                var themeOrigin = new Point(130, 120);
                Prepare(themeOrigin);
                Set("UiThemeSelected", "cang-green");
                root.UpdateLayout();
                var themeOverlay = Overlay();
                var themeMask = themeOverlay == null ? null : themeOverlay.OpacityMask as RadialGradientBrush;
                Check(themeMask != null && themeMask.HasAnimatedProperties && themeMask.Center == themeOrigin, "Theme selection did not reuse the click-origin reveal");
                Pump(80);
                var themeFrame = Capture();
                var themeColor = ((SolidColorBrush)Application.Current.Resources["ColorBrush4"]).Color;
                Check(Near(Pixel(themeFrame, 130, 120), themeColor), "Theme accent is not revealed at the clicked choice");
                Check(Near(Pixel(themeFrame, 600, 320), Pixel(oldTheme, 600, 320)), "Theme changed outside the reveal circle");
                var current = assembly.GetType("PCL.ModSecret").GetField("CurrentTheme").GetValue(null);
                Check((string)current == "cang-green" && (bool)assembly.GetType("PCL.ModSecret").GetProperty("IsDarkTheme").GetValue(null, null) == darkMode, "Theme transition changed the selected theme or brightness mode");
                Prepare(new Point(250, 160));
                Set("UiThemeSelected", "totoro-blue");
                Check(Overlay() != null && !Object.ReferenceEquals(themeOverlay, Overlay()) && themeOverlay.Source == null, "Rapid theme selection stacked old screenshots");
                Set("UiThemeSelected", "lemon-cyan");
                Check(Overlay() == null, "Programmatic theme selection retained an old animation");
            }
            Dark(false);

            Prepare(origin);
            Pump(30);
            Dark(true);
            Check(Overlay() == null, "A cancelled click affected a later setting change");

            Prepare(origin);
            Dark(false);
            Check(Overlay() != null, "Resize probe did not start");
            root.Width = 600;
            root.UpdateLayout();
            Check(Overlay() == null, "Resizing retained an incorrectly sized screenshot");
            root.Width = double.NaN;
            root.UpdateLayout();

            Prepare(origin);
            Dark(true);
            Cancel();
            Check(Overlay() == null, "Page departure did not cancel its transition");

            Set("SystemDebugAnim", 30);
            Prepare(origin);
            Dark(false);
            Check(Overlay() == null, "Transition ignored disabled animations");
            Set("SystemDebugAnim", 4);
            Prepare(origin);
            Dark(true);
            var unloading = Overlay();
            Check(unloading != null, "Unload probe did not start");
            window.Content = null;
            Pump(30);
            Check(Overlay() == null && unloading.Source == null && unloading.OpacityMask == null, "Unloading retained the transition or snapshot");

            if (!String.IsNullOrEmpty(previewPath)) {
                var drawing = new DrawingVisual();
                using (var context = drawing.RenderOpen()) {
                    context.DrawImage(start, new Rect(0, 0, 640, 360));
                    context.DrawImage(middle, new Rect(640, 0, 640, 360));
                    context.DrawImage(end, new Rect(1280, 0, 640, 360));
                }
                var preview = new RenderTargetBitmap(1920, 360, 96, 96, PixelFormats.Pbgra32);
                preview.Render(drawing);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(preview));
                using (var stream = File.Create(previewPath)) encoder.Save(stream);
            }
        } finally {
            Cancel();
            window.Content = null;
            window.Close();
        }
    }
}
'@
    [ThemeTransitionRegression]::Run($assembly, $PreviewPath)
    Write-Output 'PASS: slower circular reveal, click origin and feathered pixels, theme selection in light/dark modes, both brightness directions, rapid theme/brightness changes, programmatic changes, cancelled clicks, resize, unload, input passthrough and screenshot cleanup.'
} catch {
    Write-Output $_.Exception.ToString()
    throw
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
