' Copyright (C) 2026 PCL-Slash contributors
' SPDX-License-Identifier: GPL-3.0-only

Imports Microsoft.Win32
Imports System.Globalization
Imports System.Security.Cryptography
Imports System.Text.RegularExpressions

''' <summary>
''' 显式迁入工具。源目录和源注册表只读，正常的设置读取不兼容 PCL2 格式。
''' </summary>
Public NotInheritable Class Pcl2Migration

    Public Shared Property IsRunning As Boolean
    Private Shared ReadOnly Utf8 As New UTF8Encoding(False)
    Private ReadOnly SourceBase As String
    Private ReadOnly TargetBase As String
    Private ReadOnly SourceRegistry As String
    Private ReadOnly TargetRegistry As String
    Private ReadOnly GameFolders As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly PathMappings As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ReadOnly Games As New List(Of CopyEntry)
    Private ReadOnly Assets As New List(Of CopyEntry)
    Private ReadOnly EmptyDirectories As New List(Of String)
    Private ReadOnly RegistryChanges As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
    Private ConvertedSetup As Dictionary(Of String, String)
    Private Prepared As Boolean
    Private Executed As Boolean
    Public ReadOnly CacheDirectory As String
    Public ReadOnly GameDirectory As String
    Public ReadOnly Property GameFolderCount As Integer
        Get
            Return GameFolders.Count
        End Get
    End Property
    Public ReadOnly Property CopyBytes As Long
        Get
            Return Games.Sum(Function(Item) Item.Length) + Assets.Sum(Function(Item) Item.Length)
        End Get
    End Property

    Private Class CopyEntry
        Public Source As String
        Public Target As String
        Public Length As Long
    End Class
    Public Sub New(SourceFolder As String, TargetFolder As String,
                   Optional SourceRegistryPath As String = "Software\PCL",
                   Optional TargetRegistryPath As String = "Software\PCL-Slash")
        SourceBase = FullFolder(SourceFolder)
        TargetBase = FullFolder(TargetFolder)
        Dim CacheBase = FullFolder(Path.Combine(TargetBase, "PCL\Cache"))
        If Overlaps(SourceBase, TargetBase) Then Throw New IOException("PCL-Slash 不得与 PCL2 位于同一目录或互相包含的目录中。请先将两个启动器放到独立目录。")
        If String.Equals(SourceRegistryPath, TargetRegistryPath, StringComparison.OrdinalIgnoreCase) Then Throw New ArgumentException("源注册表与目标注册表不能相同。")
        EnsureNoLinks(SourceBase)
        EnsureNoLinks(TargetBase)
        EnsureNoLinks(CacheBase)
        If Not File.Exists(PathUtils.ForApi(Path.Combine(SourceBase, "PCL\Setup.ini"))) Then Throw New FileNotFoundException("所选目录中没有 PCL\Setup.ini，请选择已经使用过的 PCL2 所在目录。")
        SourceRegistry = SourceRegistryPath
        TargetRegistry = TargetRegistryPath
        Dim SessionId = Guid.NewGuid().ToString("N")
        Dim Session = Date.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture) & "-" & SessionId
        CacheDirectory = Path.Combine(CacheBase, "PCL2Migration", Session)
        GameDirectory = Path.Combine(TargetBase, "PCL2-Migrated", SessionId)
    End Sub

    ''' <summary>先保存设置快照，再仅从快照读取及转换；不调用源启动器，也不触发源目录的权限写入测试。</summary>
    Public Sub Prepare(Optional SourceThemeIdentity As String = Nothing)
        If Prepared Then Throw New InvalidOperationException("迁入计划已准备。")
        CheckSourceClosed()
        Directory.CreateDirectory(PathUtils.ForApi(CacheDirectory))
        CopyReadOnly(Path.Combine(SourceBase, "PCL\Setup.ini"), Path.Combine(CacheDirectory, "Source\Setup.ini"))
        Dim SourceSetup = ReadSettings(Path.Combine(CacheDirectory, "Source\Setup.ini"))
        Dim SourceValues = ReadSourceRegistry(SourceRegistry)
        WriteJson(Path.Combine(CacheDirectory, "Source\Registry.json"), SourceValues)
        '转换只能使用已经保存的缓存快照。
        SourceValues = JsonConvert.DeserializeObject(Of Dictionary(Of String, String))(File.ReadAllText(PathUtils.ForApi(Path.Combine(CacheDirectory, "Source\Registry.json")), Utf8))
        ConvertedSetup = ReadSettings(Path.Combine(TargetBase, "PCL\Setup.ini"))
        ConvertThemeSettings(SourceSetup, SourceValues, SourceThemeIdentity)
        PathMappings(SourceBase) = TargetBase
        DiscoverGameFolders(SourceSetup, SourceValues)
        PathMappings(FullFolder(Path.Combine(SourceBase, "PCL"))) = FullFolder(Path.Combine(TargetBase, "PCL"))
        ConvertSettings(SourceSetup, Settings.Sources.Normal, ConvertedSetup)
        ConvertSettings(SourceValues, Settings.Sources.Registry, RegistryChanges)
        Dim FolderEntries As New List(Of String)
        Using Key = Registry.CurrentUser.OpenSubKey(TargetRegistry, False)
            Dim Existing = If(Key?.GetValue("LaunchFolders"), "").ToString()
            For Each Item In Existing.Split("|"c)
                Dim Separator = Item.IndexOf(">"c)
                If Separator < 1 Then Continue For
                Dim Folder = FullFolder(Item.Substring(Separator + 1))
                If GameFolders.Keys.Any(Function(Source) Overlaps(Folder, Source)) Then Continue For
                FolderEntries.Add(Item)
            Next
        End Using
        FolderEntries.AddRange(GameFolders.Select(Function(Pair) Pair.Value & ">" & PathMappings(Pair.Key)))
        RegistryChanges("LaunchFolders") = String.Join("|", FolderEntries)
        Dim Selected = SourceSetup.GetOrDefault("LaunchFolderSelect", "")
        If Selected <> "" Then Selected = ResolveSourceFolder(Selected)
        If Selected = "" OrElse Not GameFolders.ContainsKey(Selected) Then Selected = GameFolders.Keys.FirstOrDefault()
        If Selected IsNot Nothing AndAlso Selected <> "" Then ConvertedSetup("LaunchFolderSelect") = PathMappings(Selected)
        WriteSettings(Path.Combine(CacheDirectory, "Converted\Setup.ini"), ConvertedSetup)
        WriteJson(Path.Combine(CacheDirectory, "Converted\Registry.json"), RegistryChanges)
        '外观资源同样先复制进缓存，再安装到目标目录。
        For Each Name In {"Logo.png", "Custom.xaml", "Pictures", "Musics"}
            Dim Source = Path.Combine(SourceBase, "PCL", Name)
            Dim Target = Path.Combine(TargetBase, "PCL", Name)
            If Directory.Exists(PathUtils.ForApi(Source)) Then
                CollectFiles(Source, Target, Assets)
            ElseIf File.Exists(PathUtils.ForApi(Source)) Then
                AddFile(Source, Target, Assets)
            End If
        Next
        EnsureSpaceAvailable()
        Prepared = True
    End Sub

    Private Sub DiscoverGameFolders(Setup As Dictionary(Of String, String), Values As Dictionary(Of String, String))
        If Directory.Exists(PathUtils.ForApi(Path.Combine(SourceBase, "versions"))) Then AddGameFolder(SourceBase, "PCL2 游戏目录")
        For Each Folder In Directory.GetDirectories(PathUtils.ForApi(SourceBase)).Select(AddressOf PathUtils.RemoveExtendedPrefix)
            If Directory.Exists(PathUtils.ForApi(Path.Combine(Folder, "versions"))) OrElse Path.GetFileName(Folder) = ".minecraft" Then AddGameFolder(Folder, Path.GetFileName(Folder))
        Next
        For Each Item In Values.GetOrDefault("LaunchFolders", "").Split("|"c)
            If Item = "" Then Continue For
            Dim Separator = Item.IndexOf(">"c)
            If Separator < 1 Then Throw New InvalidDataException("PCL2 的游戏目录列表格式无效，请先在 PCL2 中修复后重试。")
            AddGameFolder(ResolveSourceFolder(Item.Substring(Separator + 1)), Item.Substring(0, Separator))
        Next
        Dim Selected = Setup.GetOrDefault("LaunchFolderSelect", "")
        If Selected <> "" Then AddGameFolder(ResolveSourceFolder(Selected), "PCL2 当前目录")
        '祖先目录只复制一次，保留嵌套注册目录各自的映射。
        Dim Roots = GameFolders.Keys.Where(Function(Folder) Not GameFolders.Keys.Any(Function(Other) Other <> Folder AndAlso IsInside(Folder, Other))).ToList()
        For Index = 0 To Roots.Count - 1
            Dim Root = Roots(Index)
            Dim Destination = FullFolder(Path.Combine(GameDirectory, (Index + 1).ToString(CultureInfo.InvariantCulture)))
            For Each Folder In GameFolders.Keys
                If IsInside(Folder, Root) Then PathMappings(Folder) = Destination & Folder.Substring(Root.Length)
            Next
            CollectFiles(Root, Destination, Games, String.Equals(Root, SourceBase, StringComparison.OrdinalIgnoreCase))
        Next
    End Sub

    Private Sub AddGameFolder(Folder As String, Name As String)
        Folder = FullFolder(Folder)
        If GameFolders.ContainsKey(Folder) Then Return
        If Not Directory.Exists(PathUtils.ForApi(Folder)) Then Throw New DirectoryNotFoundException("PCL2 的游戏目录不可访问：" & Folder)
        If Overlaps(Folder, TargetBase) Then
            Throw New IOException("游戏源目录与 PCL-Slash 或其缓存目录重叠，无法保证只读复制：" & Folder)
        End If
        EnsureNoLinks(Folder)
        GameFolders.Add(Folder, Name.Replace("|", "").Replace(">", ""))
    End Sub

    Private Function ResolveSourceFolder(Value As String) As String
        Value = Value.Replace("$", SourceBase)
        Return FullFolder(If(Path.IsPathRooted(Value), Value, Path.Combine(SourceBase, Value)))
    End Function

    Private Sub CollectFiles(Source As String, Target As String, Items As List(Of CopyEntry), Optional LauncherRoot As Boolean = False)
        EnsureNoLinks(Source)
        EmptyDirectories.Add(Target)
        For Each FilePath In Directory.GetFiles(PathUtils.ForApi(Source)).Select(AddressOf PathUtils.RemoveExtendedPrefix)
            AddFile(FilePath, Path.Combine(Target, Path.GetFileName(FilePath)), Items)
        Next
        For Each Folder In Directory.GetDirectories(PathUtils.ForApi(Source)).Select(AddressOf PathUtils.RemoveExtendedPrefix)
            If LauncherRoot AndAlso Path.GetFileName(Folder).Equals("PCL", StringComparison.OrdinalIgnoreCase) Then Continue For
            CollectFiles(Folder, Path.Combine(Target, Path.GetFileName(Folder)), Items)
        Next
    End Sub

    Private Sub AddFile(Source As String, Target As String, Items As List(Of CopyEntry))
        EnsureNoLinks(Source)
        EnsureNoLinks(Target)
        Items.Add(New CopyEntry With {.Source = Source, .Target = Target, .Length = New FileInfo(PathUtils.ForApi(Source)).Length})
    End Sub

    Private Shared Function IsMigratable(Key As String, Source As Settings.Sources) As Boolean
        Dim Entry As Settings.Setting = Nothing
        If Not Settings.Entries.TryGetValue(Key, Entry) OrElse Entry.Source <> Source OrElse Entry.Encrypted Then Return False
        '不迁入登录凭据、运行计数、缓存位置、更新源以及已删除的功能。
        Return Key.StartsWith("Launch", StringComparison.Ordinal) OrElse Key.StartsWith("Ui", StringComparison.Ordinal) OrElse
               Key.StartsWith("Tool", StringComparison.Ordinal) OrElse Key = "WindowWidth" OrElse Key = "WindowHeight"
    End Function

    Private Shared ReadOnly RenamedKeys As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) From {
        {"UiLauncherHue", "UiThemeCustomHue"}, {"UiLauncherSat", "UiThemeCustomSaturation"},
        {"UiLauncherDelta", "UiThemeCustomGradient"}, {"UiLauncherLight", "UiThemeCustomLightness"},
        {"UiBackgroundColorful", "UiThemeColorfulBackground"}}

    Private Sub ConvertSettings(Values As Dictionary(Of String, String), Source As Settings.Sources, Output As Dictionary(Of String, String))
        For Each Pair In Values
            Dim Key = RenamedKeys.GetOrDefault(Pair.Key, Pair.Key)
            If Not IsMigratable(Key, Source) OrElse Key = "LaunchFolders" OrElse Key = "LaunchFolderSelect" Then Continue For
            Dim Value = RemapPaths(Pair.Value)
            If Key = "LaunchArgumentInfo" AndAlso Value = "PCL" Then Value = BrandName
            If Key = "UiThemeSelected" Then Continue For '主题使用下方的显式编号转换。
            Try
                CTypeDynamic(Value, Settings.Entries(Key).Type)
            Catch ex As Exception
                Throw New InvalidDataException("PCL2 设置格式无效：" & Pair.Key, ex)
            End Try
            Output(Key) = Value
        Next
    End Sub

    Private Shared ReadOnly LegacyThemes As New Dictionary(Of Integer, String) From {
        {0, LauncherTheme.TotoroBlue}, {1, LauncherTheme.LemonCyan}, {2, LauncherTheme.GrassGreen},
        {3, LauncherTheme.PineappleYellow}, {4, LauncherTheme.OakBrown}, {5, LauncherTheme.MonochromeBlack},
        {6, LauncherTheme.LoyalPink}, {7, LauncherTheme.MysteryPurple}, {9, LauncherTheme.ActiveOrange},
        {10, LauncherTheme.DelayedRed}, {11, LauncherTheme.GeekBlue}, {12, LauncherTheme.FunnyRainbow},
        {13, LauncherTheme.LuckyRainbow}, {14, LauncherTheme.Custom}, {15, LauncherTheme.TianyiBlue}, {16, LauncherTheme.CangGreen}}
    Private Shared ReadOnly LegacyUnlockKeys As String() = {"UiLauncherThemeHide", "UiLauncherThemeHide2"}
    Private Shared ReadOnly HiddenThemeKeys As New HashSet(Of String)(LegacyThemes.Where(Function(Pair) IsHiddenThemeId(Pair.Key)).Select(Function(Pair) Pair.Value), StringComparer.Ordinal)

    Public Class ThemeUnlockMigrationException
        Inherits Exception
        Public Sub New()
            MyBase.New("无法解密 PCL2 的主题解锁记录，请填写原 PCL2 中显示的识别码后重试。")
        End Sub
    End Class

    Private Shared Function IsHiddenThemeId(Id As Integer) As Boolean
        Return Id >= 5 AndAlso Id <= 13 AndAlso Id <> 8
    End Function

    Private Shared Function TryReadThemeList(Value As String, ByRef Result As HashSet(Of String)) As Boolean
        Result = New HashSet(Of String)(StringComparer.Ordinal)
        Value = Value.Trim()
        Dim Items As IEnumerable(Of String)
        If Value.StartsWith("[") Then
            Try
                Dim Array = JArray.Parse(Value)
                If Array.Any(Function(Item) Item.Type <> JTokenType.String AndAlso Item.Type <> JTokenType.Integer) Then Return False
                Items = Array.Select(Function(Item) Item.ToString()).ToList()
            Catch ex As JsonException
                Return False
            End Try
        ElseIf Value = "" OrElse Regex.IsMatch(Value, "^\d+(?:\|\d+)*$") Then
            Items = Value.Split("|"c)
        Else
            Return False
        End If
        For Each Item In Items
            Dim Id As Integer
            If Integer.TryParse(Item, NumberStyles.None, CultureInfo.InvariantCulture, Id) Then
                If IsHiddenThemeId(Id) AndAlso LegacyThemes.ContainsKey(Id) Then Result.Add(LegacyThemes(Id))
            ElseIf HiddenThemeKeys.Contains(Item) Then
                Result.Add(Item)
            End If
        Next
        Return True
    End Function

    '仅转换主题记录，不引入 PCL2 的常规设置兼容、设备识别码生成或登录凭据迁入。
    Private Shared Function TransformThemeRecord(Value As String, Key As String, Decrypt As Boolean) As String
        Dim KeyBytes = Utf8.GetBytes(Key.GetStableHashCode().ToString().EnsureLength("X"c, 8).Substring(0, 8))
        Using Cipher = DES.Create()
            Cipher.Key = KeyBytes
            Cipher.IV = Utf8.GetBytes("95168702")
            Using Transform = If(Decrypt, Cipher.CreateDecryptor(), Cipher.CreateEncryptor())
                Dim Input = If(Decrypt, Convert.FromBase64String(Value), Utf8.GetBytes(Value))
                Dim Output = Transform.TransformFinalBlock(Input, 0, Input.Length)
                Return If(Decrypt, Utf8.GetString(Output), Convert.ToBase64String(Output))
            End Using
        End Using
    End Function

    Private Sub ConvertThemeSettings(Setup As Dictionary(Of String, String), Values As Dictionary(Of String, String), Identity As String)
        Dim Unlocked As New HashSet(Of String)(StringComparer.Ordinal)
        Using Target = Registry.CurrentUser.OpenSubKey(TargetRegistry, False)
            Dim Current = TryCast(Target?.GetValue("UiThemeUnlocked"), String)
            If Current IsNot Nothing Then
                Try
                    TryReadThemeList(TransformThemeRecord(Current, BrandName, True), Unlocked)
                Catch ex As CryptographicException
                Catch ex As FormatException
                End Try
            End If
        End Using
        Dim CandidateKeys As New List(Of String)
        If Not String.IsNullOrWhiteSpace(Identity) Then CandidateKeys.Add("PCL" & Identity.Trim())
        Using Source = Registry.CurrentUser.OpenSubKey(SourceRegistry, False)
            Dim StoredIdentity = TryCast(Source?.GetValue("Identify"), String)
            If Not String.IsNullOrWhiteSpace(StoredIdentity) Then CandidateKeys.Add("PCL" & StoredIdentity)
        End Using
        CandidateKeys.Add("PCL0000-0000-0000-0000") '公开源码版使用的固定识别码。
        Dim HasRecord As Boolean = False
        For Each Name In LegacyUnlockKeys
            If Not Values.ContainsKey(Name) Then Continue For
            HasRecord = True
            Dim Imported As HashSet(Of String) = Nothing
            Dim Decoded = TryReadThemeList(Values(Name), Imported)
            If Not Decoded Then
                For Each Key In CandidateKeys.Distinct()
                    Try
                        If TryReadThemeList(TransformThemeRecord(Values(Name), Key, True), Imported) Then
                            Decoded = True
                            Exit For
                        End If
                    Catch ex As CryptographicException
                    Catch ex As FormatException
                    End Try
                Next
            End If
            If Not Decoded Then Throw New ThemeUnlockMigrationException()
            Unlocked.UnionWith(Imported)
        Next
        If HasRecord Then RegistryChanges("UiThemeUnlocked") = TransformThemeRecord(New JArray(Unlocked.OrderBy(Function(Key) Key, StringComparer.Ordinal)).ToString(Formatting.None), BrandName, False)
        If Setup.ContainsKey("UiLauncherTheme") Then
            Dim Id As Integer
            Dim Selected = DefaultThemeKey
            If Integer.TryParse(Setup("UiLauncherTheme"), Id) AndAlso LegacyThemes.ContainsKey(Id) Then
                If Not IsHiddenThemeId(Id) OrElse Unlocked.Contains(LegacyThemes(Id)) Then Selected = LegacyThemes(Id)
                If Id = 14 AndAlso Unlocked.Count < 5 Then Selected = DefaultThemeKey
            End If
            ConvertedSetup("UiThemeSelected") = Selected
        End If
    End Sub

    Public Shared Function ReadSourceRegistry(RegistryPath As String) As Dictionary(Of String, String)
        Dim Values As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
        Using Key = Registry.CurrentUser.OpenSubKey(RegistryPath, False)
            If Key Is Nothing Then Return Values
            For Each Name In Key.GetValueNames()
                If LegacyUnlockKeys.Contains(Name) OrElse IsMigratable(RenamedKeys.GetOrDefault(Name, Name), Settings.Sources.Registry) Then
                    Values(Name) = Convert.ToString(Key.GetValue(Name, Nothing, RegistryValueOptions.DoNotExpandEnvironmentNames), CultureInfo.InvariantCulture)
                End If
            Next
        End Using
        Return Values
    End Function

    ''' <summary>空间按缓存和目标所在卷合并计算，额外预留文件系统及设置写入空间。</summary>
    Public Sub EnsureSpaceAvailable(Optional AvailableSpace As Func(Of String, Long) = Nothing)
        If AvailableSpace Is Nothing Then AvailableSpace = Function(Root) New DriveInfo(Root).AvailableFreeSpace
        Dim Demands As New Dictionary(Of String, Long)(StringComparer.OrdinalIgnoreCase)
        Dim CacheBytes = Assets.Sum(Function(Item) AllocatedSize(Item.Length))
        Dim TargetBytes = Games.Sum(Function(Item) AllocatedSize(Item.Length)) + CacheBytes
        For Each Pair In {New KeyValuePair(Of String, Long)(CacheDirectory, CacheBytes), New KeyValuePair(Of String, Long)(TargetBase, TargetBytes)}
            Dim Root = Path.GetPathRoot(Pair.Key)
            Demands(Root) = Demands.GetOrDefault(Root, 0L) + Pair.Value + 64L * 1024 * 1024
        Next
        For Each Pair In Demands
            If AvailableSpace(Pair.Key) < Pair.Value Then Throw New IOException($"存储空间不足：{Pair.Key} 至少需要 {Math.Ceiling(Pair.Value / 1024 / 1024)} MB 可用空间（含缓存与预留空间）。")
        Next
    End Sub

    Private Shared Function AllocatedSize(Length As Long) As Long
        Return ((Length + 4095) \ 4096) * 4096
    End Function

    Public Sub Execute(Optional Progress As Action(Of Double, String) = Nothing)
        If Not Prepared OrElse Executed Then Throw New InvalidOperationException("请先准备迁入计划，且每份计划只能执行一次。")
        Executed = True
        CheckSourceClosed()
        EnsureSpaceAvailable()
        Dim SettingsStarted As Boolean = False
        Try
            Dim Copied As Long = 0
            Dim Total = Math.Max(1L, CopyBytes)
            For Each Item In Assets
                CopyReadOnly(Item.Source, AssetCachePath(Item.Target), Sub(Count)
                                                                           Copied += Count
                                                                           Progress?.Invoke(Copied / Total * 0.9, "缓存设置资源")
                                                                       End Sub)
                If Path.GetFileName(Item.Target).Equals("Custom.xaml", StringComparison.OrdinalIgnoreCase) Then
                    Dim CachedPath = PathUtils.ForApi(AssetCachePath(Item.Target))
                    File.WriteAllText(CachedPath, RemapPaths(File.ReadAllText(CachedPath, Utf8)), Utf8)
                End If
            Next
            For Each Folder In EmptyDirectories.Where(Function(Value) IsInside(Value, GameDirectory))
                EnsureNoLinks(Folder)
                Directory.CreateDirectory(PathUtils.ForApi(Folder))
            Next
            Dim LastProcessCheck = Stopwatch.StartNew()
            For Each Item In Games
                If LastProcessCheck.ElapsedMilliseconds > 2000 Then
                    CheckSourceClosed()
                    LastProcessCheck.Restart()
                End If
                CopyReadOnly(Item.Source, Item.Target, Sub(Count)
                                                          Copied += Count
                                                          Progress?.Invoke(Copied / Total * 0.9, "复制游戏实例")
                                                      End Sub)
                If IsGameSettingsFile(Item.Target) Then
                    Dim Values = ReadSettings(Item.Target)
                    For Each Key In Values.Keys.ToList()
                        Values(Key) = RemapPaths(Values(Key))
                        If Key = "VersionArgumentInfo" AndAlso Values(Key) = "PCL" Then Values(Key) = BrandName
                    Next
                    If Path.GetFileName(Item.Target).Equals("PCL.ini", StringComparison.OrdinalIgnoreCase) Then Values("InstanceCache") = ""
                    WriteSettings(Item.Target, Values)
                End If
            Next
            CheckSourceClosed()
            Progress?.Invoke(0.92, "覆盖 PCL-Slash 设置")
            SettingsStarted = True
            For Each Item In Assets
                CopyReadOnly(AssetCachePath(Item.Target), Item.Target)
            Next
            For Each Folder In EmptyDirectories.Where(Function(Value) Not IsInside(Value, GameDirectory))
                EnsureNoLinks(Folder)
                Directory.CreateDirectory(PathUtils.ForApi(Folder))
            Next
            CopyReadOnly(Path.Combine(CacheDirectory, "Converted\Setup.ini"), Path.Combine(TargetBase, "PCL\Setup.ini"))
            Using Key = Registry.CurrentUser.CreateSubKey(TargetRegistry)
                For Each Pair In RegistryChanges
                    Key.SetValue(Pair.Key, Pair.Value, RegistryValueKind.String)
                Next
            End Using
            Progress?.Invoke(1, "迁入完成")
        Catch ex As Exception
            '覆盖设置之前失败时，仅清理本次新建的游戏目录。
            '开始覆盖后保留副本，避免已写入的游戏目录引用失效。
            If Not SettingsStarted AndAlso Directory.Exists(PathUtils.ForApi(GameDirectory)) Then
                EnsureNoLinks(GameDirectory)
                Directory.Delete(PathUtils.ForApi(GameDirectory), True)
            End If
            Dim Message = If(SettingsStarted,
                "迁入未完成，部分 PCL-Slash 设置可能已被覆盖。未创建原设置备份，请重新迁入以完成覆盖。",
                "迁入失败，尚未覆盖 PCL-Slash 设置。")
            Throw New IOException(Message & "缓存位置：" & CacheDirectory, ex)
        End Try
    End Sub

    Private Function IsGameSettingsFile(FilePath As String) As Boolean
        For Each Folder In GameFolders.Keys.Select(Function(Source) PathMappings(Source))
            If String.Equals(FilePath, Path.Combine(Folder, "PCL.ini"), StringComparison.OrdinalIgnoreCase) Then Return True
            If Not Path.GetFileName(FilePath).Equals("Setup.ini", StringComparison.OrdinalIgnoreCase) OrElse
               Not Path.GetFileName(Path.GetDirectoryName(FilePath)).Equals("PCL", StringComparison.OrdinalIgnoreCase) Then Continue For
            Dim VersionsFolder = Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(FilePath)))
            If String.Equals(FullFolder(VersionsFolder), FullFolder(Path.Combine(Folder, "versions")), StringComparison.OrdinalIgnoreCase) Then Return True
        Next
        Return False
    End Function

    Private Function AssetCachePath(Target As String) As String
        Return Path.Combine(CacheDirectory, "Source\Assets", Target.Substring(TargetBase.Length))
    End Function

    Private Function RemapPaths(Value As String) As String
        For Each Pair In PathMappings.OrderByDescending(Function(Item) Item.Key.Length)
            For Each Separator In {"\\", "\", "/"}
                Dim Source = Pair.Key.Replace("\", Separator)
                Dim Target = Pair.Value.Replace("\", Separator)
                Value = Regex.Replace(Value, Regex.Escape(Source), Function(Match) Target, RegexOptions.IgnoreCase Or RegexOptions.CultureInvariant)
            Next
        Next
        Return Value
    End Function

    Private Shared Function ReadSettings(FilePath As String) As Dictionary(Of String, String)
        Dim Values As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
        If Not File.Exists(PathUtils.ForApi(FilePath)) Then Return Values
        EnsureNoLinks(FilePath)
        For Each Line In File.ReadAllLines(PathUtils.ForApi(FilePath), Utf8)
            Dim Separator = Line.IndexOf(":"c)
            If Separator > 0 Then Values(Line.Substring(0, Separator)) = Line.Substring(Separator + 1)
        Next
        Return Values
    End Function

    Private Shared Sub WriteSettings(FilePath As String, Values As Dictionary(Of String, String))
        EnsureNoLinks(FilePath)
        Directory.CreateDirectory(PathUtils.ForApi(Path.GetDirectoryName(FilePath)))
        File.WriteAllLines(PathUtils.ForApi(FilePath), Values.Select(Function(Pair) Pair.Key & ":" & Pair.Value), Utf8)
    End Sub

    Private Shared Sub WriteJson(FilePath As String, Value As Object)
        EnsureNoLinks(FilePath)
        Directory.CreateDirectory(PathUtils.ForApi(Path.GetDirectoryName(FilePath)))
        File.WriteAllText(PathUtils.ForApi(FilePath), JsonConvert.SerializeObject(Value, Newtonsoft.Json.Formatting.Indented), Utf8)
    End Sub

    Private Shared Sub CopyReadOnly(Source As String, Target As String, Optional Progress As Action(Of Integer) = Nothing)
        EnsureNoLinks(Source)
        EnsureNoLinks(Target)
        Directory.CreateDirectory(PathUtils.ForApi(Path.GetDirectoryName(Target)))
        '使用同目录新文件原子替换，避免目标文件恰好与源文件互为硬链接时改写源内容。
        '临时文件名不拼接原文件名，避免长依赖文件名超过路径或单个文件名长度限制。
        Dim Temporary = Path.Combine(Path.GetDirectoryName(Target), Path.GetRandomFileName())
        Dim TemporaryCreated As Boolean = False
        Try
            Using Input As New FileStream(PathUtils.ForApi(Source), FileMode.Open, FileAccess.Read, FileShare.Read)
                Using Output As New FileStream(PathUtils.ForApi(Temporary), FileMode.CreateNew, FileAccess.Write, FileShare.None)
                    TemporaryCreated = True
                    Dim Buffer(1024 * 1024 - 1) As Byte
                    Dim Count As Integer
                    Do
                        Count = Input.Read(Buffer, 0, Buffer.Length)
                        If Count = 0 Then Exit Do
                        Output.Write(Buffer, 0, Count)
                        Progress?.Invoke(Count)
                    Loop
                    If Input.Length <> Output.Length Then Throw New IOException("文件在复制过程中发生变化：" & Source)
                End Using
            End Using
            If File.Exists(PathUtils.ForApi(Target)) Then
                File.Replace(PathUtils.ForApi(Temporary), PathUtils.ForApi(Target), Nothing)
            Else
                File.Move(PathUtils.ForApi(Temporary), PathUtils.ForApi(Target))
            End If
        Finally
            If TemporaryCreated AndAlso File.Exists(PathUtils.ForApi(Temporary)) Then File.Delete(PathUtils.ForApi(Temporary))
        End Try
    End Sub

    Private Shared Function FullFolder(Value As String) As String
        Return PathUtils.RemoveExtendedPrefix(Path.GetFullPath(PathUtils.ForApi(Value))).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) & Path.DirectorySeparatorChar
    End Function
    Private Shared Function IsInside(Value As String, Folder As String) As Boolean
        Return FullFolder(Value).StartsWith(FullFolder(Folder), StringComparison.OrdinalIgnoreCase)
    End Function
    Private Shared Function Overlaps(First As String, Second As String) As Boolean
        Return IsInside(First, Second) OrElse IsInside(Second, First)
    End Function

    ''' <summary>拒绝目录联接和符号链接，防止缓存或目标目录绕回源目录。</summary>
    Private Shared Sub EnsureNoLinks(Value As String)
        Value = Path.GetFullPath(PathUtils.ForApi(Value)).TrimEnd(Path.DirectorySeparatorChar)
        While Not String.IsNullOrEmpty(Value)
            If (Directory.Exists(Value) OrElse File.Exists(Value)) AndAlso (File.GetAttributes(Value) And FileAttributes.ReparsePoint) <> 0 Then
                Throw New IOException("迁入路径包含符号链接或目录联接，请改用实际目录：" & Value)
            End If
            Value = Path.GetDirectoryName(Value)
        End While
    End Sub

    Private Sub CheckSourceClosed()
        '正式版与开源版配置在各自安装之间共享；独立注册表的迁入只需检查其源目录。
        Dim SharedRegistry = String.Equals(SourceRegistry, "Software\PCL", StringComparison.OrdinalIgnoreCase) OrElse
                             String.Equals(SourceRegistry, "Software\PCLDebug", StringComparison.OrdinalIgnoreCase)
        EnsureSourceClosed(SourceBase, SharedRegistry)
    End Sub

    Public Shared Sub EnsureSourceClosed(SourceFolder As String, Optional CheckSharedRegistry As Boolean = True)
        For Each Item In Process.GetProcesses()
            Using Item
                If Item.Id = Process.GetCurrentProcess().Id Then Continue For
                Try
                    Dim Executable = Item.MainModule.FileName
                    Dim Name = Path.GetFileNameWithoutExtension(Executable)
                    If Name.IndexOf("Slash", StringComparison.OrdinalIgnoreCase) >= 0 Then Continue For
                    If String.Equals(FullFolder(Path.GetDirectoryName(Executable)), FullFolder(SourceFolder), StringComparison.OrdinalIgnoreCase) OrElse
                       (CheckSharedRegistry AndAlso (Name.IndexOf("PCL2", StringComparison.OrdinalIgnoreCase) >= 0 OrElse Name.IndexOf("Plain Craft Launcher", StringComparison.OrdinalIgnoreCase) >= 0)) Then
                        Throw New IOException("检测到 PCL2 或源目录中的程序仍在运行。请关闭 PCL2 及其启动的游戏后重试。")
                    End If
                Catch ex As System.ComponentModel.Win32Exception
                    If CheckSharedRegistry AndAlso Item.ProcessName.IndexOf("PCL", StringComparison.OrdinalIgnoreCase) >= 0 AndAlso Item.ProcessName.IndexOf("Slash", StringComparison.OrdinalIgnoreCase) < 0 Then Throw New IOException("无法确认 PCL2 已关闭，请关闭 PCL2 后重试。", ex)
                Catch ex As InvalidOperationException
                    '进程恰好结束。
                End Try
            End Using
        Next
    End Sub
End Class
