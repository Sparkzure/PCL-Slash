namespace PCLCS;

public enum MinesweeperState { Ready, Playing, Won, Lost }

public sealed class MinesweeperCell {
    public bool HasMine { get; internal set; }
    public bool IsRevealed { get; internal set; }
    public bool IsFlagged { get; internal set; }
    public int AdjacentMines { get; internal set; }
}

/// <summary>不依赖界面或持久化数据的扫雷棋盘，首次翻开时才布雷。</summary>
public sealed class MinesweeperBoard {
    private readonly MinesweeperCell[] _cells;
    private readonly Random _random;
    public int Width { get; }
    public int Height { get; }
    public int MineCount { get; }
    public int FlagCount { get; private set; }
    public int RevealedCount { get; private set; }
    public int ExplodedIndex { get; private set; } = -1;
    public MinesweeperState State { get; private set; } = MinesweeperState.Ready;

    public MinesweeperBoard(int width, int height, int mineCount, int? seed = null) {
        if (width < 3 || width > 30) throw new ArgumentOutOfRangeException(nameof(width));
        if (height < 3 || height > 30) throw new ArgumentOutOfRangeException(nameof(height));
        if (mineCount < 1 || mineCount > width * height - 9) throw new ArgumentOutOfRangeException(nameof(mineCount));
        Width = width;
        Height = height;
        MineCount = mineCount;
        _random = seed.HasValue ? new Random(seed.Value) : new Random();
        _cells = Enumerable.Range(0, width * height).Select(_ => new MinesweeperCell()).ToArray();
    }

    public MinesweeperCell GetCell(int index) {
        if (index < 0 || index >= _cells.Length) throw new ArgumentOutOfRangeException(nameof(index));
        return _cells[index];
    }

    private IEnumerable<int> Neighbors(int index) {
        int x = index % Width, y = index / Width;
        for (int row = Math.Max(0, y - 1); row <= Math.Min(Height - 1, y + 1); row++) {
            for (int col = Math.Max(0, x - 1); col <= Math.Min(Width - 1, x + 1); col++) {
                int neighbor = row * Width + col;
                if (neighbor != index) yield return neighbor;
            }
        }
    }

    public bool ToggleFlag(int index) {
        var cell = GetCell(index);
        if (State is MinesweeperState.Won or MinesweeperState.Lost || cell.IsRevealed) return false;
        if (!cell.IsFlagged && FlagCount >= MineCount) return false;
        cell.IsFlagged = !cell.IsFlagged;
        FlagCount += cell.IsFlagged ? 1 : -1;
        return true;
    }

    public bool Reveal(int index) {
        var cell = GetCell(index);
        if (State is MinesweeperState.Won or MinesweeperState.Lost || cell.IsFlagged) return false;
        if (State == MinesweeperState.Ready) PlaceMines(index);
        int previousCount = RevealedCount;
        if (cell.IsRevealed) {
            // 在数字格周围标满相应旗数后，再次点击即可展开剩余邻格。
            var neighbors = Neighbors(index).ToArray();
            if (cell.AdjacentMines == 0 || neighbors.Count(i => _cells[i].IsFlagged) != cell.AdjacentMines) return false;
            foreach (int neighbor in neighbors) {
                RevealRegion(neighbor);
                if (State == MinesweeperState.Lost) break;
            }
        } else {
            RevealRegion(index);
        }
        if (State == MinesweeperState.Playing && RevealedCount == _cells.Length - MineCount) {
            State = MinesweeperState.Won;
            foreach (var mine in _cells.Where(c => c.HasMine)) mine.IsFlagged = true;
            FlagCount = MineCount;
        }
        return RevealedCount != previousCount || State == MinesweeperState.Lost;
    }

    private void PlaceMines(int firstIndex) {
        var safe = new HashSet<int>(Neighbors(firstIndex)) { firstIndex };
        var candidates = Enumerable.Range(0, _cells.Length).Where(i => !safe.Contains(i)).ToArray();
        for (int i = 0; i < MineCount; i++) {
            int selected = _random.Next(i, candidates.Length);
            (candidates[i], candidates[selected]) = (candidates[selected], candidates[i]);
            _cells[candidates[i]].HasMine = true;
        }
        for (int i = 0; i < _cells.Length; i++) _cells[i].AdjacentMines = Neighbors(i).Count(n => _cells[n].HasMine);
        State = MinesweeperState.Playing;
    }

    private void RevealRegion(int index) {
        var pending = new Queue<int>();
        pending.Enqueue(index);
        while (pending.Count > 0) {
            int current = pending.Dequeue();
            var cell = _cells[current];
            if (cell.IsRevealed || cell.IsFlagged) continue;
            if (cell.HasMine) {
                ExplodedIndex = current;
                State = MinesweeperState.Lost;
                return;
            }
            cell.IsRevealed = true;
            RevealedCount++;
            if (cell.AdjacentMines == 0) {
                foreach (int neighbor in Neighbors(current)) {
                    if (!_cells[neighbor].IsRevealed && !_cells[neighbor].IsFlagged) pending.Enqueue(neighbor);
                }
            }
        }
    }
}
