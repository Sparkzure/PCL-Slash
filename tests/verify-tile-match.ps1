param([switch]$Preview)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool/cache/tile-match-tests-' + [Guid]::NewGuid().ToString('N'))
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
    $bin = Join-Path $repoRoot 'Plain Craft Launcher 2/bin'
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $bin 'Plain Craft Launcher Slash.exe'))
    $core = [Reflection.Assembly]::LoadFrom((Join-Path $bin 'PCLCS.dll'))
    Add-Type -AssemblyName PresentationFramework
    $application = [Windows.Application]::new()
    $application.ShutdownMode = [Windows.ShutdownMode]::OnExplicitShutdown
    $resources = [Resources.ResourceManager]::new('PCL.Resources', $assembly)
    foreach ($name in @('Newtonsoft.Json', 'ThrottleDebounce')) {
        [Reflection.Assembly]::Load([byte[]]$resources.GetObject($name)) | Out-Null
    }
    $application.Resources['ColorBrushSemiTransparent'] = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromArgb(1,234,242,254))
    $assembly.GetType('PCL.ModSecret').GetMethod('ThemeRefresh').Invoke($null, @($null))
    $references = @($core.Location, 'System.dll', 'System.Core.dll', [Windows.DependencyObject].Assembly.Location,
        [Windows.Media.Visual].Assembly.Location, [Windows.Window].Assembly.Location, [Windows.Markup.MarkupExtension].Assembly.Location)
    Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using PCLCS;

public static class TileMatchRegression {
    static readonly BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    static int[] Cells(TileMatchBoard game) { return (int[])typeof(TileMatchBoard).GetField("_cells", Private).GetValue(game); }
    static TileMatchBoard Fixture(int[] cells) {
        var game = new TileMatchBoard(7); Array.Copy(cells, Cells(game), 100);
        typeof(TileMatchBoard).GetProperty("Remaining").SetValue(game, cells.Count(c => c != 0), null);
        return game;
    }
    static bool Clear(int[] cells, int ax, int ay, int bx, int by, int first, int second) {
        if (ax != bx && ay != by) return false;
        int dx = Math.Sign(bx - ax), dy = Math.Sign(by - ay);
        for (;;) {
            int index = ay * 10 + ax;
            if (ax >= 0 && ax < 10 && ay >= 0 && ay < 10 && index != first && index != second && cells[index] != 0) return false;
            if (ax == bx && ay == by) return true;
            ax += dx; ay += dy;
        }
    }
    static bool Reference(int[] cells, int first, int second) {
        if (first == second || cells[first] == 0 || cells[first] != cells[second]) return false;
        int ax = first % 10, ay = first / 10, bx = second % 10, by = second / 10;
        // Independent oracle: enumerate every vertical or horizontal middle segment, not a directional BFS.
        for (int k = -1; k <= 10; k++) {
            if (Clear(cells, ax, ay, k, ay, first, second) && Clear(cells, k, ay, k, by, first, second) && Clear(cells, k, by, bx, by, first, second)) return true;
            if (Clear(cells, ax, ay, ax, k, first, second) && Clear(cells, ax, k, bx, k, first, second) && Clear(cells, bx, k, bx, by, first, second)) return true;
        }
        return false;
    }
    static int[] Pair(TileMatchBoard game) {
        for (int a = 0; a < 100; a++) for (int b = a + 1; b < 100; b++) if (game.CanMatch(a, b)) return new[] { a, b };
        throw new Exception("Board has no available pair");
    }
    public static void Model() {
        var random = new Random(73);
        for (int trial = 0; trial < 12; trial++) {
            var cells = Enumerable.Range(0, 100).Select(i => random.Next(5) < 2 ? 0 : random.Next(1, 4)).ToArray();
            var game = Fixture(cells);
            for (int i = 0; i < 200; i++) {
                int a = random.Next(100), b = random.Next(100);
                Check(game.CanMatch(a, b) == Reference(cells, a, b), "Path disagrees with the two-turn oracle");
                Check(game.CanMatch(a, b) == game.CanMatch(b, a), "Connectivity is not symmetric");
            }
        }
        var enclosed = Enumerable.Repeat(2, 100).ToArray(); enclosed[11] = enclosed[35] = 1;
        foreach (int i in new[] { 12, 13, 23, 33, 34 }) enclosed[i] = 0;
        Check(Fixture(enclosed).CanMatch(11, 35), "A two-turn corridor is rejected");
        enclosed[35] = 2; enclosed[44] = 1;
        Check(!Fixture(enclosed).CanMatch(11, 44), "A three-turn corridor is accepted");
        var outside = Enumerable.Repeat(2, 100).ToArray(); outside[0] = outside[9] = 1;
        Check(Fixture(outside).CanMatch(0, 9), "A path around the board edge is rejected");
        var dead = Enumerable.Range(0, 100).Select(i => (i % 10 + i / 10 * 3) % 10 + 1).ToArray();
        var stuck = Fixture(dead);
        Check(!stuck.HasMove(), "Dead-board fixture unexpectedly has a move");
        typeof(TileMatchBoard).GetMethod("EnsureMove", Private).Invoke(stuck, null);
        Check(stuck.HasMove() && Cells(stuck).OrderBy(v => v).SequenceEqual(dead.OrderBy(v => v)), "Dead-board recovery changed colors or failed to restore a move");
        for (int seed = 0; seed < 12; seed++) {
            var game = new TileMatchBoard(seed);
            Check(game.Remaining == 100 && Enumerable.Range(1, 10).All(c => Cells(game).Count(v => v == c) == 10), "New board is not a balanced ten-color 10x10 grid");
            Check(!game.TryMatch(-1, 0) && !game.TryMatch(0, 100) && !game.TryMatch(0, 0), "Invalid selection changes the board");
            for (int move = 0; move < 50; move++) {
                Check(game.HasMove(), "A playable round became stuck");
                var pair = Pair(game); int color = game.GetCell(pair[0]);
                var counts = Enumerable.Range(1, 10).Select(c => Cells(game).Count(v => v == c)).ToArray();
                var holes = Enumerable.Range(0, 100).Where(i => game.GetCell(i) == 0).ToArray();
                Check(Reference(Cells(game), pair[0], pair[1]) && game.TryMatch(pair[0], pair[1]), "Legal pair was not removed");
                Check(game.Remaining == 98 - move * 2 && Cells(game).Count(v => v != 0) == game.Remaining, "Removal count is wrong");
                Check(holes.All(i => game.GetCell(i) == 0) && game.GetCell(pair[0]) == 0 && game.GetCell(pair[1]) == 0, "Reshuffling refilled a removed position");
                foreach (int c in Enumerable.Range(1, 10)) Check(Cells(game).Count(v => v == c) == counts[c - 1] - (c == color ? 2 : 0), "Removal or reshuffle changed color counts");
                Check(!game.TryMatch(pair[0], pair[1]), "Removed cells can be matched again");
            }
            Check(game.Remaining == 0 && !game.HasMove(), "Board did not finish after fifty pairs");
        }
    }
    static void Call(object page, string method, params object[] args) { page.GetType().GetMethod(method, Private).Invoke(page, args); }
    static void Click(FrameworkElement page, int index) {
        ((System.Windows.Controls.Primitives.UniformGrid)page.FindName("PanTileMatchBoard")).Children[index].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    }
    static void SetElapsed(Stopwatch clock, double seconds) {
        clock.Reset();
        var elapsed = typeof(Stopwatch).GetFields(Private).Single(f => f.FieldType == typeof(long) && f.Name.ToLowerInvariant().Contains("elapsed"));
        elapsed.SetValue(clock, (long)Math.Round(seconds * Stopwatch.Frequency));
    }
    static void Pump(int ms) {
        var frame = new DispatcherFrame(); var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ms) };
        timer.Tick += delegate { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
    public static void Page(Assembly assembly, string previewRoot) {
        var page = (FrameworkElement)Activator.CreateInstance(assembly.GetType("PCL.PageOtherTileMatch"));
        var gameField = page.GetType().GetField("Game", Private);
        var clock = (Stopwatch)page.GetType().GetField("Clock", Private).GetValue(page);
        var timer = (DispatcherTimer)page.GetType().GetField("GameTimer", Private).GetValue(page);
        var round = page.GetType().GetField("RoundNumber", Private);
        var board = (System.Windows.Controls.Primitives.UniformGrid)page.FindName("PanTileMatchBoard");
        var settings = assembly.GetType("PCL.Settings"); var set = settings.GetMethod("Set");
        var get = settings.GetMethods().Single(m => m.Name == "Get" && !m.IsGenericMethod);
        Action clear = () => set.Invoke(null, new object[] { "ToolMinigameCompleted", "[]", null });
        Func<string> saved = () => (string)get.Invoke(null, new object[] { "ToolMinigameCompleted", null });
        try {
            Check(board.Rows == 10 && board.Columns == 10 && board.Children.Count == 100 && board.Children.OfType<Button>().All(b => !b.Focusable && !b.IsTabStop), "Grid dimensions or mouse-only cells are wrong");
            Check(!clock.IsRunning && !timer.IsEnabled, "Unloaded page runs its clock");
            Call(page, "PageLoaded", page, null); Pump(50);
            Check(clock.IsRunning && timer.IsEnabled && clock.Elapsed.TotalMilliseconds >= 30, "Actual dispatcher frames did not run the clock");
            var fixture = new int[100]; fixture[0] = fixture[1] = 1; fixture[10] = fixture[11] = 2;
            gameField.SetValue(page, Fixture(fixture)); Call(page, "RefreshGame");
            Click(page, 0); Check(((Button)board.Children[0]).BorderThickness.Left == 3, "Selection is not visible");
            Click(page, 0); Check(((Button)board.Children[0]).BorderThickness.Left == 0, "Selecting the same tile does not cancel selection");
            Click(page, 0); Click(page, 10);
            Check(((TileMatchBoard)gameField.GetValue(page)).Remaining == 4 && ((Button)board.Children[10]).BorderThickness.Left == 3, "Mismatched selection removed tiles or did not move selection");
            Click(page, 0); Click(page, 1);
            Check(((TileMatchBoard)gameField.GetValue(page)).Remaining == 2 && board.Children[0].Visibility == Visibility.Hidden && board.Children[1].Visibility == Visibility.Hidden, "Matched cells are not hidden in their fixed grid slots");
            Call(page, "PageLeaving");
            var paused = clock.ElapsedTicks; Click(page, 10); Click(page, 11);
            Check(!clock.IsRunning && !timer.IsEnabled && ((TileMatchBoard)gameField.GetValue(page)).Remaining == 2, "Leaving the page did not pause input and time");
            Call(page, "PageLoaded", page, null);
            Check(clock.IsRunning && clock.ElapsedTicks >= paused, "Returning reset elapsed time");
            clear(); SetElapsed(clock, 69.5);
            Click(page, 10); Click(page, 11);
            Check((int)round.GetValue(page) == 2 && ((TileMatchBoard)gameField.GetValue(page)).Remaining == 100 && saved().Contains("tile-match"), "Fast round did not persist completion and advance automatically");
            Check(clock.IsRunning && timer.IsEnabled && clock.Elapsed.TotalSeconds < 1 && board.Children.OfType<Button>().All(b => b.Visibility == Visibility.Visible), "Next round stopped or retained old elapsed time/holes");
            Call(page, "PageUnloaded", page, null);
            foreach (double seconds in new[] { 69.99, 70.0, 70.0001, 71.0 }) {
                clear(); gameField.SetValue(page, Fixture(new int[100])); SetElapsed(clock, seconds);
                int oldRound = (int)round.GetValue(page);
                Call(page, "FinishRound"); Call(page, "RefreshGame");
                Check(saved().Contains("tile-match") == (seconds <= 70), "Completion used rounded display time or the wrong time limit");
                Check((int)round.GetValue(page) == oldRound + 1 && ((TileMatchBoard)gameField.GetValue(page)).Remaining == 100, "Slow or fast completion stopped endless rounds");
                var before = saved(); Call(page, "FinishRound");
                Check((int)round.GetValue(page) == oldRound + 1 && saved() == before, "An unfinished/repeated round recorded progress");
            }
            clear(); gameField.SetValue(page, Fixture(fixture)); Call(page, "RefreshGame"); Call(page, "PageLoaded", page, null);
            var currentBoard = gameField.GetValue(page); int currentRound = (int)round.GetValue(page);
            SetElapsed(clock, 69.95); Call(page, "UpdateTimer"); Pump(120);
            Check(clock.Elapsed.TotalSeconds > 70 && timer.IsEnabled && clock.IsRunning && Object.ReferenceEquals(currentBoard, gameField.GetValue(page)) &&
                (int)round.GetValue(page) == currentRound && ((TileMatchBoard)currentBoard).Remaining == 4 && saved() == "[]",
                "Crossing the achievement time limit ended, replaced or completed the unfinished round");
            var timeText = ((TextBlock)page.FindName("LabTileMatchTime")).Text;
            var timeNumber = System.Text.RegularExpressions.Regex.Match(timeText, @"\d+\.\d{2}");
            Check(timeNumber.Success && double.Parse(timeNumber.Value, System.Globalization.CultureInfo.InvariantCulture) >= 70,
                "Timer displays a countdown instead of elapsed time");
            Click(page, 0); Click(page, 1); Click(page, 10); Click(page, 11);
            Check(saved() == "[]" && timer.IsEnabled && ((TileMatchBoard)gameField.GetValue(page)).Remaining == 100, "A slow round ended endless play or granted completion");
            Call(page, "Restart", page, EventArgs.Empty);
            Check((int)round.GetValue(page) == 1 && clock.Elapsed.TotalSeconds < 1 && ((TileMatchBoard)gameField.GetValue(page)).Remaining == 100, "Restart did not reset the round");
            var host = new Window { Content = page };
            try {
                Call(page, "PageUnloaded", page, null); Call(page, "PageLoaded", page, null);
                var before = clock.ElapsedTicks; Click(page, Pair((TileMatchBoard)gameField.GetValue(page))[0]);
                Check(!host.IsActive && !clock.IsRunning && !timer.IsEnabled && clock.ElapsedTicks == before, "Inactive window does not pause the clock");
                foreach (bool dark in new[] { false, true }) {
                    set.Invoke(null, new object[] { "UiThemeDarkMode", dark, null });
                    foreach (var size in new[] { new Size(620, 410), new Size(810, 600) }) {
                        page.Measure(size); page.Arrange(new Rect(size)); page.UpdateLayout();
                        var card = page.FindName("CardTileMatch"); card.GetType().GetProperty("MainTextBlock").GetValue(card, null);
                        var bounds = board.TransformToAncestor(page).TransformBounds(new Rect(board.RenderSize));
                        Check(bounds.Left >= 0 && bounds.Right <= size.Width && bounds.Top >= 0 && bounds.Bottom <= size.Height && bounds.Height > 180, "Grid does not fit launcher sizes");
                    }
                    var border = (Border)board.Parent;
                    Check(((SolidColorBrush)border.Background).Color == ((SolidColorBrush)Application.Current.Resources["ColorBrushGray8"]).Color, "Board does not follow the current palette");
                    Check(board.Children.OfType<Button>().Select(b => ((SolidColorBrush)b.Background).Color).Distinct().Count() == 10, "Color blocks were replaced or recolored by theme styles");
                    if (!String.IsNullOrEmpty(previewRoot)) {
                        var bitmap = new RenderTargetBitmap(810, 600, 96, 96, PixelFormats.Pbgra32); bitmap.Render(page);
                        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                        using (var stream = File.Create(System.IO.Path.Combine(previewRoot, dark ? "tile-match-dark.png" : "tile-match-light.png"))) encoder.Save(stream);
                    }
                }
            } finally { Call(page, "PageUnloaded", page, null); host.Content = null; host.Close(); }
            var toolbox = (FrameworkElement)Activator.CreateInstance(assembly.GetType("PCL.PageOtherTest"));
            Check(toolbox.FindName("BtnTileMatch") != null && toolbox.FindName("PanTileMatchBoard") == null, "Toolbox entry does not lead to an independent page");
            var pageType = assembly.GetType("PCL.FormMain+PageType");
            Check((int)Enum.Parse(pageType, "TileMatch") == 11 && (int)Enum.Parse(pageType, "Tetris") == 10 && (int)Enum.Parse(pageType, "Minesweeper") == 9, "Navigation IDs were renumbered");
            var mainType = assembly.GetType("PCL.FormMain");
            var stack = Activator.CreateInstance(assembly.GetType("PCL.FormMain+PageStackData"));
            stack.GetType().GetField("Page").SetValue(stack, Enum.Parse(pageType, "TileMatch"));
            var main = System.Runtime.Serialization.FormatterServices.GetUninitializedObject(mainType);
            Check(!String.IsNullOrEmpty((string)mainType.GetMethod("PageNameGet", Private).Invoke(main, new[] { stack })), "Back-navigation registration is missing");
        } finally { Call(page, "PageUnloaded", page, null); }
    }
}
'@
    [TileMatchRegression]::Model()
    Write-Output 'PASS: independent two-turn path oracle, blocked corridors, outside edges, matching, balanced colors, dead-board recovery and complete rounds without stuck states.'
    $previewRoot = if ($Preview) { $testRoot } else { $null }
    [TileMatchRegression]::Page($assembly, $previewRoot)
    Write-Output 'PASS: mouse selection, fixed empty slots, exact elapsed-time boundary, endless rounds, protected completion, pause/resume, inactive windows, restart, light/dark layout and stable navigation.'
    if ($Preview) { Write-Output ('Previews: ' + $testRoot) }
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
