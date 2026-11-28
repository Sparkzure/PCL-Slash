namespace PCLCS;

public enum TetrisState { Ready, Playing, Lost }
public enum TetrisPiece { I = 1, O, T, S, Z, J, L }
public readonly struct TetrisCell {
    public int X { get; }
    public int Y { get; }
    public TetrisCell(int x, int y) { X = x; Y = y; }
}

/// <summary>不依赖界面或持久化数据的俄罗斯方块棋盘。</summary>
public sealed class TetrisBoard {
    public const int Width = 10;
    public const int Height = 20;
    private readonly int[,] _cells = new int[Height, Width];
    private readonly Random _random;
    private readonly Queue<TetrisPiece> _bag = new();
    private static readonly TetrisCell[][] Shapes = [
        [], [new(0, 1), new(1, 1), new(2, 1), new(3, 1)],
        [new(1, 0), new(2, 0), new(1, 1), new(2, 1)],
        [new(1, 0), new(0, 1), new(1, 1), new(2, 1)],
        [new(1, 0), new(2, 0), new(0, 1), new(1, 1)],
        [new(0, 0), new(1, 0), new(1, 1), new(2, 1)],
        [new(0, 0), new(0, 1), new(1, 1), new(2, 1)],
        [new(2, 0), new(0, 1), new(1, 1), new(2, 1)]
    ];

    public TetrisState State { get; private set; } = TetrisState.Ready;
    public int Score { get; private set; }
    public TetrisPiece CurrentPiece { get; private set; }
    public TetrisPiece NextPiece { get; private set; }
    public int Rotation { get; private set; }
    public int X { get; private set; }
    public int Y { get; private set; }

    public TetrisBoard(int? seed = null) {
        _random = seed.HasValue ? new Random(seed.Value) : new Random();
        NextPiece = TakePiece();
    }

    public void Start() {
        if (State != TetrisState.Ready) return;
        State = TetrisState.Playing;
        Spawn();
    }

    private TetrisPiece TakePiece() {
        if (_bag.Count == 0) {
            var pieces = Enumerable.Range(1, 7).Select(i => (TetrisPiece)i).ToArray();
            for (int i = pieces.Length - 1; i > 0; i--) {
                int j = _random.Next(i + 1);
                (pieces[i], pieces[j]) = (pieces[j], pieces[i]);
            }
            foreach (var piece in pieces) _bag.Enqueue(piece);
        }
        return _bag.Dequeue();
    }

    private static IEnumerable<TetrisCell> Shape(TetrisPiece piece, int rotation) {
        foreach (var cell in Shapes[(int)piece]) {
            int x = cell.X, y = cell.Y;
            if (piece != TetrisPiece.O) {
                int edge = piece == TetrisPiece.I ? 3 : 2;
                for (int turn = 0; turn < rotation; turn++) (x, y) = (edge - y, x);
            }
            yield return new TetrisCell(x, y);
        }
    }

    public IEnumerable<TetrisCell> GetActiveCells() => State == TetrisState.Playing
        ? Shape(CurrentPiece, Rotation).Select(cell => new TetrisCell(X + cell.X, Y + cell.Y))
        : Enumerable.Empty<TetrisCell>();

    public IEnumerable<TetrisCell> GetNextCells() => Shape(NextPiece, 0);

    public int GetCell(int x, int y) {
        if (x < 0 || x >= Width) throw new ArgumentOutOfRangeException(nameof(x));
        if (y < 0 || y >= Height) throw new ArgumentOutOfRangeException(nameof(y));
        return _cells[y, x];
    }

    private bool Fits(int x, int y, int rotation) => Shape(CurrentPiece, rotation).All(cell => {
        int column = x + cell.X, row = y + cell.Y;
        return column >= 0 && column < Width && row < Height && (row < 0 || _cells[row, column] == 0);
    });

    public bool Move(int direction) {
        if (State != TetrisState.Playing || (direction != -1 && direction != 1) || !Fits(X + direction, Y, Rotation)) return false;
        X += direction;
        return true;
    }

    public bool Rotate() {
        if (State != TetrisState.Playing || CurrentPiece == TetrisPiece.O) return false;
        int rotation = (Rotation + 1) % 4;
        // 尝试小范围平移，让靠近边缘或底部的方块在不重叠的位置旋转。
        foreach (var kick in new[] { new TetrisCell(0, 0), new(-1, 0), new(1, 0), new(-2, 0), new(2, 0), new(0, -1), new(0, -2) }) {
            if (!Fits(X + kick.X, Y + kick.Y, rotation)) continue;
            X += kick.X; Y += kick.Y; Rotation = rotation;
            return true;
        }
        return false;
    }

    public bool Step() {
        if (State != TetrisState.Playing) return false;
        if (Fits(X, Y + 1, Rotation)) { Y++; return true; }
        var landed = GetActiveCells().ToArray();
        if (landed.Any(cell => cell.Y < 0)) { State = TetrisState.Lost; return true; }
        foreach (var cell in landed) _cells[cell.Y, cell.X] = (int)CurrentPiece;
        int write = Height - 1;
        for (int read = Height - 1; read >= 0; read--) {
            if (Enumerable.Range(0, Width).All(column => _cells[read, column] != 0)) { Score++; continue; }
            for (int column = 0; column < Width; column++) _cells[write, column] = _cells[read, column];
            write--;
        }
        for (; write >= 0; write--) for (int column = 0; column < Width; column++) _cells[write, column] = 0;
        Spawn();
        return true;
    }

    private void Spawn() {
        CurrentPiece = NextPiece;
        NextPiece = TakePiece();
        Rotation = 0; X = 3; Y = 0;
        if (!Fits(X, Y, Rotation)) State = TetrisState.Lost;
    }
}
