param([switch]$Preview)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool/cache/minesweeper-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL/Portable.json'), '{}', [Text.UTF8Encoding]::new($false))
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
$page = $null
$hostWindow = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
try {
    $bin = Join-Path $repoRoot 'Plain Craft Launcher 2/bin'
    $core = [Reflection.Assembly]::LoadFrom((Join-Path $bin 'PCLCS.dll'))
    Add-Type -ReferencedAssemblies @($core.Location, 'System.Core') -TypeDefinition @'
using System;
using System.Linq;
using System.Collections.Generic;
using PCLCS;
public static class MinesweeperRegression {
    public static MinesweeperBoard CreateBoard() { return new MinesweeperBoard(9, 9, 10, 11); }
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static IEnumerable<int> Around(MinesweeperBoard board, int index) {
        int x = index % board.Width, y = index / board.Width;
        return Enumerable.Range(0, board.Width * board.Height).Where(i => i != index &&
            Math.Abs(i % board.Width - x) <= 1 && Math.Abs(i / board.Width - y) <= 1);
    }
    static string Snapshot(MinesweeperBoard board) {
        return board.State + ":" + board.FlagCount + ":" + board.RevealedCount + ":" +
            string.Join(",", Enumerable.Range(0, board.Width * board.Height).Select(i =>
                board.GetCell(i).IsRevealed + "/" + board.GetCell(i).IsFlagged));
    }
    static void CheckEnded(MinesweeperBoard board) {
        string before = Snapshot(board);
        for (int i = 0; i < board.Width * board.Height; i++) {
            Check(!board.Reveal(i) && !board.ToggleFlag(i), "A finished board accepts moves");
        }
        Check(Snapshot(board) == before, "A finished board changes");
    }
    public static void Run() {
        int[][] levels = { new[] {9, 9, 10}, new[] {16, 16, 40} };
        foreach (int[] level in levels) {
            int length = level[0] * level[1];
            foreach (int first in new[] {0, length / 2, length - 1}) {
                for (int seed = 0; seed < 4; seed++) {
                    var board = new MinesweeperBoard(level[0], level[1], level[2], seed);
                    Check(board.State == MinesweeperState.Ready, "New game is not ready");
                    Check(board.Reveal(first), "First reveal failed");
                    Check(board.GetCell(first).IsRevealed && board.GetCell(first).AdjacentMines == 0, "First cell is not empty and safe");
                    Check(Around(board, first).All(i => !board.GetCell(i).HasMine), "First-click neighbors contain a mine");
                    Check(Enumerable.Range(0, length).Count(i => board.GetCell(i).HasMine) == level[2], "Wrong mine count");
                    for (int i = 0; i < length; i++) {
                        var cell = board.GetCell(i);
                        Check(cell.AdjacentMines == Around(board, i).Count(n => board.GetCell(n).HasMine), "Wrong adjacent count");
                        Check(!cell.IsRevealed || !cell.HasMine, "Flood fill revealed a mine");
                        if (cell.IsRevealed && cell.AdjacentMines == 0)
                            Check(Around(board, i).All(n => board.GetCell(n).IsRevealed), "Flood fill left a reachable cell closed");
                    }
                }
            }
        }
        var flagged = new MinesweeperBoard(9, 9, 10, 3);
        Check(flagged.ToggleFlag(40) && !flagged.Reveal(40), "A flagged cell can be revealed");
        Check(flagged.State == MinesweeperState.Ready, "Flagging starts the game");
        Check(flagged.ToggleFlag(40) && flagged.Reveal(40), "Removing a flag does not restore reveal");
        Check(!flagged.ToggleFlag(40), "A revealed cell can be flagged");
        var limited = new MinesweeperBoard(9, 9, 10, 4);
        for (int i = 0; i < 10; i++) Check(limited.ToggleFlag(i), "Flagging failed");
        Check(!limited.ToggleFlag(10) && limited.FlagCount == 10, "Flag count exceeds mine count");
        Check(limited.ToggleFlag(0) && limited.FlagCount == 9, "Unflagging failed");
        var won = new MinesweeperBoard(9, 9, 10, 7);
        won.Reveal(40);
        for (int i = 0; i < 81; i++) if (!won.GetCell(i).HasMine) won.Reveal(i);
        Check(won.State == MinesweeperState.Won && won.RevealedCount == 71 && won.FlagCount == 10, "Victory is not detected");
        CheckEnded(won);
        var lost = new MinesweeperBoard(9, 9, 10, 11);
        lost.Reveal(40);
        int mine = Enumerable.Range(0, 81).First(i => lost.GetCell(i).HasMine);
        Check(lost.Reveal(mine) && lost.State == MinesweeperState.Lost && lost.ExplodedIndex == mine, "Mine click does not lose");
        CheckEnded(lost);
        foreach (bool correct in new[] {true, false}) {
            bool tested = false;
            for (int seed = 0; seed < 100 && !tested; seed++) {
                var board = new MinesweeperBoard(9, 9, 10, seed);
                board.Reveal(40);
                for (int i = 0; i < 81 && !tested; i++) {
                    var cell = board.GetCell(i);
                    int[] neighbors = Around(board, i).ToArray();
                    int[] safe = neighbors.Where(n => !board.GetCell(n).IsRevealed && !board.GetCell(n).HasMine).ToArray();
                    if (!cell.IsRevealed || cell.AdjacentMines == 0 || safe.Length < cell.AdjacentMines) continue;
                    Check(!board.Reveal(i), "Chording without matching flags changes the board");
                    foreach (int n in correct ? neighbors.Where(n => board.GetCell(n).HasMine) : safe.Take(cell.AdjacentMines))
                        Check(board.ToggleFlag(n), "Chord setup flag failed");
                    Check(board.Reveal(i), "Chording does not reveal neighbors");
                    if (correct) {
                        Check(board.State != MinesweeperState.Lost && safe.All(n => board.GetCell(n).IsRevealed), "Correct flags do not chord safely");
                    } else {
                        Check(board.State == MinesweeperState.Lost, "Incorrect flags do not expose the mine");
                    }
                    tested = true;
                }
            }
            Check(tested, "No chord scenario was exercised");
        }
        foreach (int[] bad in new[] {new[] {0, 9, 10}, new[] {9, 31, 10}, new[] {9, 9, 0}, new[] {9, 9, 73}}) {
            bool rejected = false;
            try { new MinesweeperBoard(bad[0], bad[1], bad[2]); } catch (ArgumentOutOfRangeException) { rejected = true; }
            Check(rejected, "Invalid board dimensions or mine count accepted");
        }
    }
}
'@
    [MinesweeperRegression]::Run()
    Write-Output 'PASS: first-click safety, mine counts, adjacency, flood fill, flags, chording, win/loss and terminal states.'
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $bin 'Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $page = [Activator]::CreateInstance($assembly.GetType('PCL.PageOtherMinesweeper'))
    # Application resource changes notify window trees; keep the test host hidden.
    $hostWindow = [Windows.Window]::new()
    $hostWindow.Content = $page
    $flags = [Reflection.BindingFlags]'Instance, NonPublic'
    $gameField = $page.GetType().GetField('Game', $flags)
    $timer = $page.GetType().GetField('GameTimer', $flags).GetValue($page)
    $clock = $page.GetType().GetField('Clock', $flags).GetValue($page)
    Assert ($page.FindName('LabMineTime').Text.Contains('0.00')) 'A new game does not show two decimal places'
    $boardPanel = $page.FindName('PanMineBoard')
    $combo = $page.FindName('ComboMineDifficulty')
    Assert ($combo.Items.Count -eq 2) 'The game must offer only beginner and intermediate difficulty'
    foreach ($level in @(@(0,81,10), @(1,256,40))) {
        $combo.SelectedIndex = $level[0]
        Assert ($boardPanel.Children.Count -eq $level[1]) 'Difficulty does not rebuild the cells'
        Assert ($gameField.GetValue($page).MineCount -eq $level[2]) 'Difficulty has the wrong mine count'
        foreach ($boardCell in $boardPanel.Children) {
            Assert (-not $boardCell.Focusable -and -not $boardCell.IsTabStop) 'A board cell accepts keyboard focus or tab selection'
        }
        foreach ($width in @(800,620)) {
            $page.Measure([Windows.Size]::new($width, 850))
            $page.Arrange([Windows.Rect]::new(0, 0, $width, 850))
            $page.UpdateLayout()
            $scroll = $page.FindName('MineBoardScroll')
            $viewport = $scroll.Template.FindName('PART_ScrollContentPresenter', $scroll)
            $boardLeft = $boardPanel.TranslatePoint([Windows.Point]::new(0, 0), $viewport).X
            Assert ([Math]::Abs($boardLeft - ($viewport.ActualWidth - $boardPanel.ActualWidth) / 2) -le 1) 'The board is not horizontally centered'
        }
    }
    $page.Measure([Windows.Size]::new(500, 850))
    $page.Arrange([Windows.Rect]::new(0, 0, 500, 850))
    $page.UpdateLayout()
    Assert ($page.FindName('MineBoardScroll').ScrollableWidth -gt 0) 'Intermediate board does not scroll in a narrow viewport'
    $combo.SelectedIndex = 0
    $gameField.SetValue($page, [MinesweeperRegression]::CreateBoard())
    $cell = $boardPanel.Children[40]
    $rightClick = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Right)
    $rightClick.RoutedEvent = [Windows.UIElement]::PreviewMouseRightButtonDownEvent
    $cell.RaiseEvent($rightClick)
    Assert ($gameField.GetValue($page).GetCell(40).IsFlagged -and $rightClick.Handled) 'Right-click is not wired to flagging'
    Assert (-not $cell.IsKeyboardFocused) 'Right-click leaves the cell selected'
    $cell.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($gameField.GetValue($page).State.ToString() -eq 'Ready') 'Clicking a flag starts the game'
    $rightClick = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Right)
    $rightClick.RoutedEvent = [Windows.UIElement]::PreviewMouseRightButtonDownEvent
    $cell.RaiseEvent($rightClick)
    $cell.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($gameField.GetValue($page).GetCell(40).IsRevealed) 'Left-click is not wired to revealing'
    Assert (-not $cell.IsKeyboardFocused) 'Left-click leaves the cell selected'
    $page.GetType().GetMethod('PageLoaded', $flags).Invoke($page, @($page, $null)) | Out-Null
    Assert ($timer.IsEnabled -and $clock.IsRunning) 'Entering an active game does not start the clock'
    $page.GetType().GetMethod('PageUnloaded', $flags).Invoke($page, @($page, $null)) | Out-Null
    Assert (-not $timer.IsEnabled -and -not $clock.IsRunning) 'Leaving a game does not pause the clock'
    $pausedTicks = $clock.ElapsedTicks
    $page.GetType().GetMethod('PageLoaded', $flags).Invoke($page, @($page, $null)) | Out-Null
    Assert ($clock.IsRunning -and $clock.ElapsedTicks -ge $pausedTicks) 'Returning resets the game clock'
    $activeGame = $gameField.GetValue($page)
    $mineIndex = @(0..80 | Where-Object { $activeGame.GetCell($_).HasMine })[0]
    $boardPanel.Children[$mineIndex].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($activeGame.State.ToString() -eq 'Lost' -and -not $timer.IsEnabled -and -not $clock.IsRunning) 'Losing does not stop the game clock'
    $timeText = [regex]::Match($page.FindName('LabMineTime').Text, '(?<!\d)\d+\.\d{2}(?!\d)')
    Assert ($timeText.Success) 'Final elapsed time does not have exactly two decimal places'
    $displayedSeconds = [double]::Parse($timeText.Value, [Globalization.CultureInfo]::InvariantCulture)
    Assert ([Math]::Abs($displayedSeconds - $clock.Elapsed.TotalSeconds) -le 0.0051) 'Final elapsed time loses fractional precision'
    $page.GetType().GetMethod('PageUnloaded', $flags).Invoke($page, @($page, $null)) | Out-Null
    $oldGame = $gameField.GetValue($page)
    $page.GetType().GetMethod('Restart', $flags).Invoke($page, @($page.FindName('BtnMineRestart'), [EventArgs]::Empty)) | Out-Null
    Assert (-not [Object]::ReferenceEquals($oldGame, $gameField.GetValue($page))) 'Restart retains the old board'
    Assert ($gameField.GetValue($page).State.ToString() -eq 'Ready' -and $clock.ElapsedTicks -eq 0 -and -not $timer.IsEnabled) 'Restart does not reset timer/state'
    Assert ($page.FindName('LabMineTime').Text.Contains('0.00')) 'Restart does not reset the displayed fractional time'
    $toolbox = [Activator]::CreateInstance($assembly.GetType('PCL.PageOtherTest'))
    Assert ($null -ne $toolbox.FindName('BtnMinesweeper')) 'The toolbox jump button is missing'
    Assert ($null -eq $toolbox.FindName('PanMineBoard')) 'The game is embedded in the toolbox instead of an independent page'
    $pageType = $assembly.GetType('PCL.FormMain+PageType')
    foreach ($entry in @(@('Launch',0), @('Download',1), @('Setup',3), @('Other',4), @('InstanceSelect',5), @('TaskManager',6), @('InstanceSetup',7), @('ResourceDetail',8), @('Minesweeper',9))) {
        Assert ([int][Enum]::Parse($pageType, $entry[0]) -eq $entry[1]) 'A navigation ID was renumbered'
    }
    $mainType = $assembly.GetType('PCL.FormMain')
    $stack = [Activator]::CreateInstance($assembly.GetType('PCL.FormMain+PageStackData'))
    $stack.Page = [Enum]::Parse($pageType, 'Minesweeper')
    $main = [Runtime.Serialization.FormatterServices]::GetUninitializedObject($mainType)
    Assert (-not [string]::IsNullOrWhiteSpace($mainType.GetMethod('PageNameGet', $flags).Invoke($main, @($stack)))) 'The game is not registered as a secondary page with back navigation'
    $refresh = $assembly.GetType('PCL.ModSecret').GetMethod('ThemeRefresh')
    $cell = $boardPanel.Children[0]
    $lightBrush = $null
    foreach ($theme in @('tianyi-blue', 'night-black')) {
        $refresh.Invoke($null, @($theme)) | Out-Null
        Assert ($cell.Background.Color -eq $application.Resources['ColorBrush6'].Color) "Cells do not follow $theme : actual=$($cell.Background.Color), expected=$($application.Resources['ColorBrush6'].Color)"
        Assert ($cell.Foreground.Color -eq $application.Resources['ColorBrush1'].Color) 'Cell text does not follow the theme'
        if ($theme -eq 'tianyi-blue') { $lightBrush = $cell.Background.Color }
        else { Assert ($cell.Background.Color -ne $lightBrush) 'Night theme keeps the light board colors' }
        if ($Preview) {
            $previewGame = [MinesweeperRegression]::CreateBoard()
            $previewGame.Reveal(40) | Out-Null
            $mineIndex = @(0..80 | Where-Object { $previewGame.GetCell($_).HasMine })[0]
            $previewGame.ToggleFlag($mineIndex) | Out-Null
            $gameField.SetValue($page, $previewGame)
            $page.GetType().GetMethod('RefreshGame', $flags).Invoke($page, @()) | Out-Null
            $page.Measure([Windows.Size]::new(810, 850))
            $page.Arrange([Windows.Rect]::new(0, 0, 810, 850))
            $page.UpdateLayout()
            $card = $page.FindName('CardMinesweeper')
            $card.Measure([Windows.Size]::new(760, [double]::PositiveInfinity))
            $card.Arrange([Windows.Rect]::new(0, 0, 760, $card.DesiredSize.Height))
            $card.UpdateLayout()
            foreach ($visibleCell in $boardPanel.Children) {
                $visibleCell.ApplyTemplate() | Out-Null
                $label = $visibleCell.Template.FindName('CellLabel', $visibleCell)
                Assert ($label.Foreground.Color -eq $visibleCell.Foreground.Color) 'The implicit TextBlock style overrides number or flag colors'
            }
            $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(760, [int][Math]::Ceiling($card.ActualHeight), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($card)
            $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream = [IO.File]::Create((Join-Path $repoRoot ('.tool/cache/minesweeper-' + $theme + '.png')))
            try { $encoder.Save($stream) } finally { $stream.Dispose() }
            $page.GetType().GetMethod('Restart', $flags).Invoke($page, @($page.FindName('BtnMineRestart'), [EventArgs]::Empty)) | Out-Null
            $cell = $boardPanel.Children[0]
        }
    }
    Write-Output 'PASS: independent page, toolbox button, stable navigation IDs, two difficulties, centered boards, mouse-only cells without focus selection, restart, timer pause and light/night themes.'
} finally {
    if ($page) { $page.GetType().GetMethod('PageUnloaded', [Reflection.BindingFlags]'Instance, NonPublic').Invoke($page, @($page, $null)) | Out-Null }
    if ($hostWindow) { $hostWindow.Content = $null; $hostWindow.Close() }
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
