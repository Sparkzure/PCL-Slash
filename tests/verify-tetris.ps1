param([switch]$Preview)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool/cache/tetris-tests-' + [Guid]::NewGuid().ToString('N'))
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
    # A plain WPF host never queues launcher Startup, account loading or network work.
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
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using PCLCS;

public static class TetrisRegression {
    static readonly BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    static int[,] Cells(TetrisBoard game) { return (int[,])typeof(TetrisBoard).GetField("_cells", Private).GetValue(game); }
    static void Set(TetrisBoard game, string property, object value) { typeof(TetrisBoard).GetProperty(property).SetValue(game, value, null); }
    static void Call(object page, string name, params object[] args) { page.GetType().GetMethod(name, Private).Invoke(page, args); }
    static TetrisBoard LineFixture(int lines, int score) {
        var game = new TetrisBoard(7); game.Start();
        Set(game, "CurrentPiece", TetrisPiece.I); Set(game, "Rotation", 1); Set(game, "X", 2); Set(game, "Score", score);
        var cells = Cells(game);
        for (int y = 20 - lines; y < 20; y++) for (int x = 0; x < 10; x++) if (x != 4) cells[y, x] = 2;
        cells[10, 0] = 6;
        return game;
    }
    static void Land(TetrisBoard game) {
        for (int i = 0; i < 25; i++) {
            game.Step();
            if (game.State != TetrisState.Playing || game.Score != 0 || game.Y == 0) return;
        }
        throw new Exception("Piece did not land");
    }
    public static void Model() {
        for (int seed = 0; seed < 30; seed++) {
            var game = new TetrisBoard(seed);
            Check(game.State == TetrisState.Ready && !game.GetActiveCells().Any(), "New board has already started");
            Check(!game.Move(1) && !game.Rotate() && !game.Step(), "Ready board accepts moves");
            game.Start();
            var bag = new System.Collections.Generic.HashSet<TetrisPiece>();
            for (int i = 0; i < 7; i++) {
                Check(bag.Add(game.CurrentPiece), "Seven-piece bag repeats a shape");
                Check(game.GetActiveCells().Count() == 4 && game.GetNextCells().Count() == 4, "A shape does not have four cells");
                var original = String.Join(";", game.GetActiveCells().OrderBy(c => c.Y * 10 + c.X).Select(c => c.X + "," + c.Y));
                for (int r = 0; r < 4; r++) game.Rotate();
                Check(String.Join(";", game.GetActiveCells().OrderBy(c => c.Y * 10 + c.X).Select(c => c.X + "," + c.Y)) == original, "Four rotations changed a piece");
                while (game.Move(-1)) { }
                Check(game.GetActiveCells().Min(c => c.X) == 0 && !game.Move(-1), "Piece crosses the left wall");
                game.Rotate();
                Check(game.GetActiveCells().All(c => c.X >= 0 && c.X < 10 && c.Y < 20), "Wall rotation escaped the board");
                while (game.Move(1)) { }
                Check(game.GetActiveCells().Max(c => c.X) == 9 && !game.Move(1) && !game.Move(5), "Piece crosses the right wall");
                // Isolate bag generation from stack height while still landing each actual piece.
                Array.Clear(Cells(game), 0, 200);
                int placed = 0;
                while (placed < 25) {
                    game.Step(); placed++;
                    if (Cells(game).Cast<int>().Any(v => v != 0)) break;
                }
                Check(Cells(game).Cast<int>().Count(v => v != 0) == 4 && game.Score == 0, "Landing awards points or loses cells");
                Array.Clear(Cells(game), 0, 200);
            }
        }
        foreach (int count in new[] { 1, 2, 3, 4 }) {
            var game = LineFixture(count, 0); Land(game);
            Check(game.Score == count && game.State == TetrisState.Playing, "Line scoring is not one point per row");
            Check(game.GetCell(0, 10 + count) == 6 && game.GetCell(0, 0) == 0, "Clearing rows did not compact the board");
        }
        var near = LineFixture(1, 58); for (int i = 0; i < 25 && near.Score == 58; i++) near.Step();
        Check(near.Score == 59 && near.State == TetrisState.Playing, "Game finished below the completion threshold");
        foreach (int score in new[] { 59, 60, 100 }) foreach (int count in new[] { 1, 4 }) {
            var game = LineFixture(count, score);
            for (int i = 0; i < 25 && game.Score == score; i++) game.Step();
            Check(game.State == TetrisState.Playing && game.Score == score + count && game.GetActiveCells().Count() == 4,
                "Achievement threshold stopped the game, truncated scoring or failed to spawn the next piece");
            int y = game.Y;
            Check(game.Move(1) && game.Step() && game.Y == y + 1, "Game cannot continue after the achievement threshold");
        }
        var blocked = new TetrisBoard(4); blocked.Start(); Set(blocked, "Y", 16);
        for (int y = 0; y < 3; y++) for (int x = 3; x <= 6; x++) Cells(blocked)[y, x] = 3;
        Land(blocked);
        Check(blocked.State == TetrisState.Lost && blocked.Score == 0 && !blocked.Step(), "Blocked spawn does not end the game");
        var above = new TetrisBoard(1); above.Start(); Set(above, "CurrentPiece", TetrisPiece.I); Set(above, "Rotation", 1); Set(above, "Y", -1);
        Cells(above)[3, 5] = 2; above.Step();
        Check(above.State == TetrisState.Lost && Cells(above).Cast<int>().Count(v => v != 0) == 1, "Top-out partially wrote a piece above the board");
        var collision = new TetrisBoard(8); collision.Start(); Set(collision, "CurrentPiece", TetrisPiece.T); Set(collision, "Y", 7);
        foreach (var cell in collision.GetActiveCells()) Cells(collision)[cell.Y + 2, cell.X] = 1;
        collision.Step(); collision.Step();
        Check(Cells(collision).Cast<int>().Count(v => v != 0) >= 8, "Settled pieces were overwritten");
    }
    static KeyEventArgs Key(FrameworkElement page, PresentationSource source, System.Windows.Input.Key key) {
        var e = new KeyEventArgs(Keyboard.PrimaryDevice, source, Environment.TickCount, key) { RoutedEvent = Keyboard.PreviewKeyDownEvent };
        page.RaiseEvent(e); return e;
    }
    static void Pump(int ms) {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ms) };
        timer.Tick += delegate { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
    public static void Page(Assembly assembly, string previewRoot) {
        var page = (FrameworkElement)Activator.CreateInstance(assembly.GetType("PCL.PageOtherTetris"));
        var gameField = page.GetType().GetField("Game", Private);
        var timer = (DispatcherTimer)page.GetType().GetField("GameTimer", Private).GetValue(page);
        var settings = assembly.GetType("PCL.Settings"); var set = settings.GetMethod("Set");
        var get = settings.GetMethods().Single(m => m.Name == "Get" && !m.IsGenericMethod);
        var board = (System.Windows.Controls.Primitives.UniformGrid)page.FindName("PanTetrisBoard");
        Check(board.Children.Count == 200 && ((System.Windows.Controls.Primitives.UniformGrid)page.FindName("PanTetrisNext")).Children.Count == 16, "Board/preview dimensions are wrong");
        using (var source = new HwndSource(new HwndSourceParameters("Tetris regression") { Width = 1, Height = 1, PositionX = -10000, PositionY = -10000, WindowStyle = 0 })) {
            try {
                Call(page, "StartNewGame", page, EventArgs.Empty);
                Check(!timer.IsEnabled, "Unloaded page runs its timer");
                Call(page, "PageLoaded", page, null);
                var game = (TetrisBoard)gameField.GetValue(page);
                Set(game, "CurrentPiece", TetrisPiece.T);
                Pump(600);
                Check(game.Y > 0 && game.Score == 0, "Actual dispatcher ticks did not drop the piece without awarding points");
                foreach (var key in new[] { System.Windows.Input.Key.Left, System.Windows.Input.Key.A, System.Windows.Input.Key.Right, System.Windows.Input.Key.D }) {
                    int oldX = game.X;
                    Check(Key(page, source, key).Handled && game.X != oldX, "Movement key did not control the game: " + key);
                }
                foreach (var key in new[] { System.Windows.Input.Key.Up, System.Windows.Input.Key.W }) {
                    int rotation = game.Rotation;
                    Check(Key(page, source, key).Handled && rotation != game.Rotation, "Rotation key did not rotate: " + key);
                }
                foreach (var key in new[] { System.Windows.Input.Key.Down, System.Windows.Input.Key.S }) {
                    int y = game.Y;
                    Check(Key(page, source, key).Handled && game.Y == y + 1 && game.Score == 0, "Soft drop key changed scoring or failed");
                }
                Check(!Key(page, source, System.Windows.Input.Key.Space).Handled, "Game consumes an unrelated key");
                Call(page, "PageUnloaded", page, null);
                int pausedY = game.Y;
                Call(page, "TimerTick", page, EventArgs.Empty);
                Check(!timer.IsEnabled && game.Y == pausedY && !Key(page, source, System.Windows.Input.Key.S).Handled, "Unloaded page keeps playing");
                Call(page, "PageLoaded", page, null);
                Check(timer.IsEnabled && Object.ReferenceEquals(game, gameField.GetValue(page)), "Returning loses game state or does not resume");
                Call(page, "PageLeaving"); Check(!timer.IsEnabled, "Exit animation keeps the game running");
                var host = new Window { Content = page };
                try {
                    Call(page, "PageUnloaded", page, null); Call(page, "PageLoaded", page, null);
                    Check(!host.IsActive && !timer.IsEnabled && !Key(page, source, System.Windows.Input.Key.S).Handled, "Inactive window accepts input or runs the game");
                    foreach (bool dark in new[] { false, true }) {
                        set.Invoke(null, new object[] { "UiThemeDarkMode", dark, null });
                        foreach (var size in new[] { new Size(620, 410), new Size(810, 600) }) {
                            page.Measure(size); page.Arrange(new Rect(size)); page.UpdateLayout();
                            // MyCard titles normally initialize on Loaded, initialize explicitly in the hidden host.
                            page.FindName("CardTetris").GetType().GetProperty("MainTextBlock").GetValue(page.FindName("CardTetris"), null);
                            var bounds = board.TransformToAncestor(page).TransformBounds(new Rect(board.RenderSize));
                            Check(bounds.Top >= 0 && bounds.Bottom <= size.Height && bounds.Left >= 0 && bounds.Right <= size.Width && bounds.Height > 180, "Board clips or vanishes at launcher sizes");
                        }
                        var empty = board.Children.OfType<Border>().First(b => ((SolidColorBrush)b.Background).Color == ((SolidColorBrush)Application.Current.Resources["ColorBrushCardBackground"]).Color);
                        Check(empty != null, "Empty cells do not follow the current palette");
                        if (!String.IsNullOrEmpty(previewRoot)) {
                            var bitmap = new RenderTargetBitmap(810, 600, 96, 96, PixelFormats.Pbgra32); bitmap.Render(page);
                            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                            using (var stream = File.Create(System.IO.Path.Combine(previewRoot, dark ? "tetris-dark.png" : "tetris-light.png"))) encoder.Save(stream);
                        }
                    }
                } finally { Call(page, "PageUnloaded", page, null); host.Content = null; host.Close(); }
                set.Invoke(null, new object[] { "ToolMinigameCompleted", "[]", null });
                Call(page, "PageLoaded", page, null);
                var unfinished = LineFixture(1, 58);
                for (int i = 0; i < 25 && unfinished.Score == 58; i++) unfinished.Step();
                string playingCaption = null;
                foreach (var state in new[] { TetrisState.Playing, TetrisState.Lost }) {
                    Set(unfinished, "State", state); gameField.SetValue(page, unfinished); Call(page, "RefreshGame");
                    Check((string)get.Invoke(null, new object[] { "ToolMinigameCompleted", null }) == "[]", "Unfinished game recorded completion");
                    if (state == TetrisState.Playing) playingCaption = ((TextBlock)page.FindName("LabTetrisStatus")).Text;
                }
                var qualified = LineFixture(1, 59); for (int i = 0; i < 25 && qualified.Score == 59; i++) qualified.Step();
                gameField.SetValue(page, qualified); Call(page, "RefreshGame");
                var saved = (string)get.Invoke(null, new object[] { "ToolMinigameCompleted", null });
                Check(saved.Contains("tetris") && timer.IsEnabled && qualified.State == TetrisState.Playing,
                    "Achievement did not persist or interrupted endless play");
                Check(((TextBlock)page.FindName("LabTetrisStatus")).Text == playingCaption, "Achievement displayed a settlement or victory status");
                int qualifiedY = qualified.Y;
                Check(Key(page, source, System.Windows.Input.Key.S).Handled && qualified.Y == qualifiedY + 1,
                    "Achievement disabled keyboard controls");
                Pump(600);
                Check(qualified.Y > qualifiedY + 1 && timer.IsEnabled, "Achievement stopped automatic falling");
                Call(page, "RefreshGame");
                Check(saved == (string)get.Invoke(null, new object[] { "ToolMinigameCompleted", null }), "Endless play duplicated achievement progress");
                Set(qualified, "State", TetrisState.Lost); Call(page, "RefreshGame");
                Check(!timer.IsEnabled && saved == (string)get.Invoke(null, new object[] { "ToolMinigameCompleted", null }), "Losing did not stop play or erased the achievement");
                Call(page, "StartNewGame", page, EventArgs.Empty);
                Check(((TetrisBoard)gameField.GetValue(page)).Score == 0 && ((TetrisBoard)gameField.GetValue(page)).State == TetrisState.Playing, "Restart did not reset the game");
                var toolbox = (FrameworkElement)Activator.CreateInstance(assembly.GetType("PCL.PageOtherTest"));
                Check(toolbox.FindName("BtnTetris") != null && toolbox.FindName("PanTetrisBoard") == null, "Toolbox entry is missing or embeds the game");
                var pageType = assembly.GetType("PCL.FormMain+PageType");
                Check((int)Enum.Parse(pageType, "Tetris") == 10 && (int)Enum.Parse(pageType, "Minesweeper") == 9, "Navigation IDs changed");
                var mainType = assembly.GetType("PCL.FormMain");
                var stack = Activator.CreateInstance(assembly.GetType("PCL.FormMain+PageStackData"));
                stack.GetType().GetField("Page").SetValue(stack, Enum.Parse(pageType, "Tetris"));
                var main = System.Runtime.Serialization.FormatterServices.GetUninitializedObject(mainType);
                Check(!String.IsNullOrEmpty((string)mainType.GetMethod("PageNameGet", Private).Invoke(main, new[] { stack })), "Secondary page/back navigation registration is missing");
            } finally { Call(page, "PageUnloaded", page, null); }
        }
    }
}
'@
    [TetrisRegression]::Model()
    Write-Output 'PASS: seven-piece bags, rotation/walls, landing, collision, line compaction, per-row scoring, endless play across the achievement threshold, top-out and terminal states.'
    $previewRoot = if ($Preview) { $testRoot } else { $null }
    [TetrisRegression]::Page($assembly, $previewRoot)
    Write-Output 'PASS: routed arrow/WASD keys, pause/resume, inactive windows, restart, achievement persistence without settlement or interrupted play, light/dark rendering, launcher sizes and independent-page navigation.'
    if ($Preview) { Write-Output ('Previews: ' + $testRoot) }
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
