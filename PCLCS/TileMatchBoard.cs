namespace PCLCS;

/// <summary>10×10 连连看；同色方块之间可经过空格和棋盘外沿，路径最多转折两次。</summary>
public sealed class TileMatchBoard {
    public const int Width = 10;
    public const int Height = 10;
    public const int ColorCount = 10;
    private readonly int[] _cells = new int[Width * Height];
    private readonly Random _random;
    private static readonly int[] Dx = [1, 0, -1, 0];
    private static readonly int[] Dy = [0, 1, 0, -1];
    public int Remaining { get; private set; } = Width * Height;

    public TileMatchBoard(int? seed = null) {
        _random = seed.HasValue ? new Random(seed.Value) : new Random();
        for (int i = 0; i < _cells.Length; i++) _cells[i] = i / 2 % ColorCount + 1;
        EnsureMove();
    }

    public int GetCell(int index) {
        if (index < 0 || index >= _cells.Length) throw new ArgumentOutOfRangeException(nameof(index));
        return _cells[index];
    }

    public bool CanMatch(int first, int second) => first >= 0 && first < _cells.Length && second >= 0 && second < _cells.Length &&
        first != second && _cells[first] != 0 && _cells[first] == _cells[second] && CanConnect(first, second);

    private bool CanConnect(int first, int second) {
        int endX = second % Width + 1, endY = second / Width + 1;
        var best = new int[Height + 2, Width + 2, 4];
        for (int y = 0; y < Height + 2; y++) for (int x = 0; x < Width + 2; x++)
            for (int d = 0; d < 4; d++) best[y, x, d] = 3;
        var queue = new Queue<(int X, int Y, int Direction, int Turns)>();
        for (int d = 0; d < 4; d++) {
            int x = first % Width + 1, y = first / Width + 1;
            best[y, x, d] = 0;
            queue.Enqueue((x, y, d, 0));
        }
        while (queue.Count > 0) {
            var current = queue.Dequeue();
            for (int d = 0; d < 4; d++) {
                if (d == (current.Direction + 2) % 4) continue;
                int turns = current.Turns + (d == current.Direction ? 0 : 1);
                int x = current.X + Dx[d], y = current.Y + Dy[d];
                if (turns > 2 || x < 0 || x >= Width + 2 || y < 0 || y >= Height + 2) continue;
                if (x == endX && y == endY) return true;
                if (x >= 1 && x <= Width && y >= 1 && y <= Height && _cells[(y - 1) * Width + x - 1] != 0) continue;
                if (best[y, x, d] <= turns) continue;
                best[y, x, d] = turns;
                queue.Enqueue((x, y, d, turns));
            }
        }
        return false;
    }

    public bool HasMove() {
        for (int first = 0; first < _cells.Length; first++) {
            if (_cells[first] == 0) continue;
            for (int second = first + 1; second < _cells.Length; second++)
                if (CanMatch(first, second)) return true;
        }
        return false;
    }

    public bool TryMatch(int first, int second) {
        if (!CanMatch(first, second)) return false;
        _cells[first] = _cells[second] = 0;
        Remaining -= 2;
        if (Remaining > 0 && !HasMove()) EnsureMove();
        return true;
    }

    private void EnsureMove() {
        var positions = Enumerable.Range(0, _cells.Length).Where(i => _cells[i] != 0).ToArray();
        if (positions.Length < 2) return;
        for (int attempt = 0; attempt < 32; attempt++) {
            for (int i = positions.Length - 1; i > 0; i--) {
                int a = positions[i], b = positions[_random.Next(i + 1)];
                (_cells[a], _cells[b]) = (_cells[b], _cells[a]);
            }
            if (HasMove()) return;
        }
        // 极端布局下，选出一对可连通的位置并换入同色方块，保留空格和每种颜色的数量。
        for (int i = 0; i < positions.Length; i++) for (int j = i + 1; j < positions.Length; j++) {
            int first = positions[i], second = positions[j];
            if (!CanConnect(first, second)) continue;
            int partner = positions.First(p => p != first && _cells[p] == _cells[first]);
            (_cells[second], _cells[partner]) = (_cells[partner], _cells[second]);
            return;
        }
        throw new InvalidOperationException("未能为剩余方块生成可连接的配对。");
    }
}
