
Imports System.Globalization

''' <summary>仅打包显式允许的普通配置和外观资源，绝不复制原始登录配置文件。</summary>
Public NotInheritable Class LauncherSettingsArchive
    Public Shared Property IsRunning As Boolean
    Public Const ScopeDescription As String =
        "支持：普通全局设置、自定义主页变量、背景图、音乐、自定义主页、标题图、离线皮肤，以及游戏实例的 Mod、配置、脚本、材质和光影。" & vbCrLf &
        "游戏实例按整合包导出，不打包 Minecraft 本体、libraries、assets、Java、存档、日志和缓存，也不保存 Java 路径。" & vbCrLf &
        "账号、密码、登录令牌、主题解锁记录等所有加密配置不参与导入导出。实例导入新目录，保留现有实例和本机 Java 选择。游戏运行资源需联网补全；Mod Loader 实例首次启动先安装组件，完成后再次点击启动。"
    Private Const ManifestName As String = "settings.json"
    Private Const FormatName As String = "PCL-Slash.Settings"
    Friend Const MaxBytes As Long = 2L * 1024 * 1024 * 1024
    Friend Const MaxManifestBytes As Long = 4L * 1024 * 1024
    Friend Const MaxEntries As Integer = 10000
    Private Shared ReadOnly Utf8 As New UTF8Encoding(False, True)
    Friend Shared ReadOnly JavaLocationKeys As New HashSet(Of String)(StringComparer.Ordinal) From {
        "LaunchArgumentJavaSelect", "LaunchArgumentJavaAll", "CacheJavaListVersion",
        "VersionArgumentJavaSelect", "VersionArgumentJavaV2"}

    Private Shared Function IsSupported(Entry As Settings.Setting) As Boolean
        Return Not Entry.Encrypted AndAlso Not JavaLocationKeys.Contains(Entry.Key) AndAlso Entry.Source <> Settings.Sources.Instance AndAlso
            Entry.Key <> "LaunchFolders" AndAlso Entry.Key <> "LaunchFolderSelect" AndAlso
            Not Entry.Key.StartsWith("Login", StringComparison.Ordinal) AndAlso
            Not Entry.Key.StartsWith("CacheMs", StringComparison.Ordinal) AndAlso
            Not Entry.Key.StartsWith("CacheNide", StringComparison.Ordinal) AndAlso
            Not Entry.Key.StartsWith("CacheAuth", StringComparison.Ordinal)
    End Function

    Private Shared Function IsVariable(Key As String) As Boolean
        Return Key.StartsWith("CustomEvent", StringComparison.Ordinal) AndAlso Key.Length > "CustomEvent".Length AndAlso
            Not Key.Any(Function(C) Char.IsControl(C))
    End Function

    Private Shared Function IsAsset(Name As String) As Boolean
        Return {"Logo.png", "Custom.xaml", "CustomSkin.png"}.Contains(Name, StringComparer.OrdinalIgnoreCase) OrElse
            Name.StartsWith("Pictures/", StringComparison.OrdinalIgnoreCase) OrElse
            Name.StartsWith("Musics/", StringComparison.OrdinalIgnoreCase)
    End Function

    Friend Shared Sub ValidateName(Name As String)
        If String.IsNullOrEmpty(Name) OrElse Name.Contains("\") Then Throw New InvalidDataException("压缩包包含不支持的文件路径。")
        For Each Part In Name.Split("/"c)
            If String.IsNullOrEmpty(Part) OrElse Part = "." OrElse Part = ".." OrElse
                Part.EndsWith(".", StringComparison.Ordinal) OrElse Part.EndsWith(" ", StringComparison.Ordinal) OrElse
                Part.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 OrElse
                System.Text.RegularExpressions.Regex.IsMatch(Part, "^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase) Then
                Throw New InvalidDataException("压缩包包含不支持的文件路径：" & Name)
            End If
        Next
    End Sub

    Friend Shared Sub EnsureNoLinks(Target As String)
        Target = Path.GetFullPath(Target)
        Do While Not String.IsNullOrEmpty(Target)
            If (File.Exists(Target) OrElse Directory.Exists(Target)) AndAlso (File.GetAttributes(Target) And FileAttributes.ReparsePoint) <> 0 Then
                Throw New IOException("配置路径包含符号链接或目录联接，请改用实际目录：" & Target)
            End If
            Target = Path.GetDirectoryName(Target)
        Loop
    End Sub

    Private Shared Function GetAssetFiles() As List(Of String)
        Dim Root = Paths.Base & "PCL\"
        Dim Result As New List(Of String)
        For Each Name In {"Logo.png", "Custom.xaml", "CustomSkin.png", "Pictures", "Musics"}
            CollectFiles(Path.Combine(Root, Name), Result)
        Next
        Return Result
    End Function

    Private Shared Sub CollectFiles(Target As String, Result As List(Of String))
        EnsureNoLinks(Target)
        If File.Exists(Target) Then
            Result.Add(Target)
            If Result.Count >= MaxEntries Then Throw New IOException("配置资源文件过多，无法打包。")
        ElseIf Directory.Exists(Target) Then
            For Each Child In Directory.EnumerateFileSystemEntries(Target)
                CollectFiles(Child, Result)
            Next
        End If
    End Sub

    Public Shared Sub ExportArchive(ArchivePath As String)
        Using Batch As New LauncherInstanceArchive.ExportBatch()
            Batch.Build()
            Dim Values As New JObject
            For Each Entry In Settings.Entries.Values.Where(AddressOf IsSupported).OrderBy(Function(Item) Item.Key, StringComparer.Ordinal)
                Dim Value = Settings.Get(Entry.Key)
                If Entry.Type.IsEnum Then Value = Convert.ToInt64(Value, CultureInfo.InvariantCulture)
                Dim Text = Convert.ToString(Value, CultureInfo.InvariantCulture)
                '与 Setup.ini 的实际持久化规则一致；自定义主页变量仍保留多行文本。
                If Entry.Source = Settings.Sources.Normal Then Text = Text.Replace(vbCr, "").Replace(vbLf, "")
                Values(Entry.Key) = Text
            Next
            Dim Variables As New JObject
            For Each Pair In PortableSettings.ReadAll().Where(Function(Item) IsVariable(Item.Key))
                Variables(Pair.Key) = If(Pair.Value, "")
            Next
            Dim Manifest As New JObject From {
                {"format", FormatName}, {"version", 2}, {"createdUtc", Date.UtcNow.ToString("O", CultureInfo.InvariantCulture)},
                {"settings", Values}, {"variables", Variables},
                {"instances", New JArray(Batch.Packs.Select(Function(Pack) "instances/" & Path.GetFileName(Pack)))}}
            Dim ManifestBytes = Utf8.GetBytes(Manifest.ToString(Formatting.Indented))
            If ManifestBytes.LongLength > MaxManifestBytes Then Throw New IOException("配置内容过大，无法打包。")
            Dim Assets = GetAssetFiles()
            If Assets.Count + Batch.Entries + Batch.Packs.Count + 1 > MaxEntries Then Throw New IOException("配置与实例中的文件过多。")
            ArchivePath = Path.GetFullPath(ArchivePath)
            EnsureNoLinks(ArchivePath)
            Dim DataRoot = Path.GetFullPath(Paths.Base & "PCL\")
            If ArchivePath.StartsWith(DataRoot, StringComparison.OrdinalIgnoreCase) Then Throw New IOException("请将配置压缩包保存到 PCL 文件夹以外的位置。")
            Dim Temporary = ArchivePath & "." & Guid.NewGuid().ToString("N") & ".tmp"
            Try
                Using Output = New FileStream(Temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None),
                      Archive As New ZipArchive(Output, ZipArchiveMode.Create)
                    Using Stream = Archive.CreateEntry(ManifestName).Open()
                        Stream.Write(ManifestBytes, 0, ManifestBytes.Length)
                    End Using
                    Dim Total As Long = ManifestBytes.LongLength + Batch.Bytes
                    If Total > MaxBytes Then Throw New IOException("配置与实例总大小超过 2 GB。")
                    For Each Pack In Batch.Packs
                        Using Input As New FileStream(Pack, FileMode.Open, FileAccess.Read, FileShare.Read),
                              Stream = Archive.CreateEntry("instances/" & Path.GetFileName(Pack), CompressionLevel.NoCompression).Open()
                            Input.CopyTo(Stream)
                        End Using
                    Next
                    For Each Asset In Assets
                        EnsureNoLinks(Asset)
                        Dim Name = Asset.Substring(DataRoot.Length).Replace("\", "/")
                        ValidateName(Name)
                        Using Input = New FileStream(Asset, FileMode.Open, FileAccess.Read, FileShare.Read),
                              Stream = Archive.CreateEntry("assets/" & Name, CompressionLevel.Optimal).Open()
                            Total += Input.Length
                            If Total > MaxBytes Then Throw New IOException("配置和资源总大小超过 2 GB，请减少背景图或音乐后再导出。")
                            Input.CopyTo(Stream)
                        End Using
                    Next
                End Using
                If File.Exists(ArchivePath) Then
                    File.Replace(Temporary, ArchivePath, Nothing)
                Else
                    File.Move(Temporary, ArchivePath)
                End If
            Finally
                If File.Exists(Temporary) Then File.Delete(Temporary)
            End Try
        End Using
    End Sub

    Public Shared Function PrepareImport(ArchivePath As String) As ImportPackage
        Dim Package As New ImportPackage
        Try
            Using Input = New FileStream(ArchivePath, FileMode.Open, FileAccess.Read, FileShare.Read),
                  Archive As New ZipArchive(Input, ZipArchiveMode.Read)
                If Archive.Entries.Count > MaxEntries Then Throw New InvalidDataException("压缩包文件过多。")
                Dim Names As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
                Dim Total As Long = 0
                Dim Manifest As ZipArchiveEntry = Nothing
                For Each Entry In Archive.Entries
                    Dim Name = Entry.FullName
                    Dim IsDirectory = Name.EndsWith("/", StringComparison.Ordinal)
                    ValidateName(If(IsDirectory, Name.Substring(0, Name.Length - 1), Name))
                    If Not Names.Add(Name.TrimEnd("/"c)) Then Throw New InvalidDataException("压缩包包含重复文件：" & Name)
                    If Name = ManifestName AndAlso Not IsDirectory Then
                        Manifest = Entry
                    ElseIf System.Text.RegularExpressions.Regex.IsMatch(Name, "^instances/[0-9]{4,}\.mrpack$") AndAlso Not IsDirectory Then
                        '实例包在读取清单后单独校验全部内部路径和展开大小。
                    ElseIf Not Name.StartsWith("assets/", StringComparison.Ordinal) OrElse
                           Not (IsAsset(Name.Substring(7)) OrElse (IsDirectory AndAlso {"assets/", "assets/Pictures/", "assets/Musics/"}.Contains(Name))) Then
                        Throw New InvalidDataException("压缩包包含支持范围外的文件：" & Name)
                    End If
                    If Entry.Length < 0 OrElse Entry.Length > MaxBytes - Total Then Throw New InvalidDataException("压缩包展开后超过 2 GB。")
                    Total += Entry.Length
                Next
                If Manifest Is Nothing OrElse Manifest.Length > MaxManifestBytes Then Throw New InvalidDataException("这不是受支持的 PCL-Slash 配置压缩包。")
                Dim Document As JObject
                Using Stream = Manifest.Open(), Buffer As New MemoryStream()
                    CopyEntry(Stream, Buffer, Manifest.Length)
                    Buffer.Position = 0
                    Using Text As New StreamReader(Buffer, Utf8), Reader As New JsonTextReader(Text)
                        Reader.DateParseHandling = DateParseHandling.None
                        Reader.MaxDepth = 16
                        Document = JObject.Load(Reader, New JsonLoadSettings With {.DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error})
                        If Reader.Read() Then Throw New InvalidDataException("配置文件末尾包含额外内容。")
                    End Using
                End Using
                If CStr(Document("format")) <> FormatName OrElse Document("version")?.Type <> JTokenType.Integer OrElse
                    Not {1, 2}.Contains(CInt(Document("version"))) Then
                    Throw New InvalidDataException("配置压缩包格式或版本不受支持。")
                End If
                Package.ReadValues(Document)
                Package.ReadPacks(Archive, Document, Total)
                For Each Entry In Archive.Entries.Where(Function(Item) Item.FullName.StartsWith("assets/", StringComparison.Ordinal) AndAlso Not Item.FullName.EndsWith("/", StringComparison.Ordinal))
                    Dim Name = Entry.FullName.Substring(7)
                    Dim Target = Path.Combine(Package.StageDirectory, "assets", Name.Replace("/", "\"))
                    Directory.CreateDirectory(Path.GetDirectoryName(Target))
                    Using Stream = Entry.Open(), Output = New FileStream(Target, FileMode.CreateNew, FileAccess.Write, FileShare.None)
                        CopyEntry(Stream, Output, Entry.Length)
                    End Using
                    Package.Assets.Add(Name, Target)
                Next
            End Using
            Return Package
        Catch
            Package.Dispose()
            Throw
        End Try
    End Function

    Friend Shared Sub CopyEntry(Input As Stream, Output As Stream, Expected As Long)
        Dim Buffer(81919) As Byte
        Dim Total As Long = 0
        Do
            Dim Count = Input.Read(Buffer, 0, Buffer.Length)
            If Count = 0 Then Exit Do
            Total += Count
            If Total > Expected Then Throw New InvalidDataException("压缩包文件大小与记录不符。")
            Output.Write(Buffer, 0, Count)
        Loop
        If Total <> Expected Then Throw New InvalidDataException("压缩包文件不完整。")
    End Sub

    Friend Shared Function ValidateValue(Pair As JProperty, Entry As Settings.Setting) As String
        If Pair.Value.Type <> JTokenType.String Then Throw New InvalidDataException("设置值格式无效：" & Pair.Name)
        Dim Value = CStr(Pair.Value)
        If Entry.Type = GetType(Boolean) Then
            Dim Parsed As Boolean
            If Not Boolean.TryParse(Value, Parsed) Then Throw New InvalidDataException("布尔设置值无效：" & Pair.Name)
        ElseIf Entry.Type = GetType(Integer) OrElse Entry.Type.IsEnum Then
            Dim Parsed As Integer
            If Not Integer.TryParse(Value, NumberStyles.Integer, CultureInfo.InvariantCulture, Parsed) OrElse
                (Entry.Type.IsEnum AndAlso Not [Enum].IsDefined(Entry.Type, Parsed)) Then Throw New InvalidDataException("整数设置值无效：" & Pair.Name)
        ElseIf Entry.Type = GetType(Long) Then
            Dim Parsed As Long
            If Not Long.TryParse(Value, NumberStyles.Integer, CultureInfo.InvariantCulture, Parsed) Then Throw New InvalidDataException("整数设置值无效：" & Pair.Name)
        ElseIf Entry.Type <> GetType(String) Then
            Throw New InvalidDataException("不支持的设置类型：" & Pair.Name)
        End If
        If Entry.Source <> Settings.Sources.Registry AndAlso (Value.Contains(vbCr) OrElse Value.Contains(vbLf)) Then Throw New InvalidDataException("设置值不能包含换行：" & Pair.Name)
        Return Value
    End Function

    Public NotInheritable Class ImportPackage
        Implements IDisposable
        Friend ReadOnly StageDirectory As String
        Friend ReadOnly Assets As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
        Private ReadOnly Normal As New Dictionary(Of String, String)(StringComparer.Ordinal)
        Private ReadOnly Portable As New Dictionary(Of String, String)(StringComparer.Ordinal)
        Private ReadOnly InstanceWrites As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
        Private ReadOnly InstanceRoot As String = Paths.Base & "PCL\Instances\" & Guid.NewGuid().ToString("N") & "\"
        Private OwnsInstanceRoot As Boolean
        Public Property InstanceCount As Integer
        Private Applied As Boolean
        Public ReadOnly Property SettingCount As Integer
            Get
                Return Normal.Count + Portable.Count
            End Get
        End Property
        Public ReadOnly Property AssetCount As Integer
            Get
                Return Assets.Count
            End Get
        End Property
        Public Property SkippedCount As Integer

        Friend Sub New()
            StageDirectory = Paths.Base & "PCL\Temp\SettingsImport-" & Guid.NewGuid().ToString("N")
            EnsureNoLinks(StageDirectory)
            Directory.CreateDirectory(StageDirectory)
        End Sub

        Friend Sub ReadPacks(Archive As ZipArchive, Document As JObject, Total As Long)
            Dim Listed = If(CInt(Document("version")) = 1, New JArray(), TryCast(Document("instances"), JArray))
            If Listed Is Nothing Then Throw New InvalidDataException("配置包缺少实例清单。")
            Dim PackEntries = Archive.Entries.Where(Function(Entry) Entry.FullName.StartsWith("instances/", StringComparison.Ordinal)).ToList()
            If Listed.Count <> PackEntries.Count Then Throw New InvalidDataException("实例清单与压缩包内容不一致。")
            Dim Files As New HashSet(Of String)(StringComparer.Ordinal)
            Dim Names As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
            Dim Count = Archive.Entries.Count
            For Each Item In Listed
                If Item.Type <> JTokenType.String OrElse Not Files.Add(CStr(Item)) Then Throw New InvalidDataException("实例清单包含无效或重复条目。")
                Dim Entry = PackEntries.SingleOrDefault(Function(Value) Value.FullName = CStr(Item))
                If Entry Is Nothing Then Throw New InvalidDataException("实例清单指定的整合包不存在。")
                Dim PackFile = Path.Combine(StageDirectory, Path.GetFileName(Entry.FullName))
                Using Input = Entry.Open(), Output As New FileStream(PackFile, FileMode.CreateNew, FileAccess.Write, FileShare.None)
                    CopyEntry(Input, Output, Entry.Length)
                End Using
                Dim Original As String
                Using Input As New FileStream(PackFile, FileMode.Open, FileAccess.Read, FileShare.Read), Pack As New ZipArchive(Input, ZipArchiveMode.Read)
                    Original = CStr(LauncherInstanceArchive.ReadDocument(Pack.GetEntry("modrinth.index.json"))("name"))
                End Using
                ValidateName(Original)
                If Original.Contains("/") Then Throw New InvalidDataException("实例名称无效。")
                Dim Name = Original
                Dim Suffix = 1
                While Not Names.Add(Name)
                    Suffix += 1
                    Name = Original & "-" & Suffix
                End While
                Dim Writes As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
                LauncherInstanceArchive.Prepare(PackFile, Path.Combine(StageDirectory, "instance-" & InstanceCount), Name, Writes, Total, Count)
                For Each Pair In Writes
                    InstanceWrites.Add(Path.Combine(InstanceRoot, "versions", Name, Pair.Key.Replace("/", "\")), Pair.Value)
                Next
                InstanceCount += 1
            Next
        End Sub

        Friend Sub ReadValues(Document As JObject)
            Dim Values = TryCast(Document("settings"), JObject)
            Dim Variables = TryCast(Document("variables"), JObject)
            If Values Is Nothing OrElse Variables Is Nothing Then Throw New InvalidDataException("配置压缩包缺少设置清单。")
            For Each Pair In Values.Properties()
                Dim Entry As Settings.Setting = Nothing
                If Not Settings.Entries.TryGetValue(Pair.Name, Entry) OrElse Not IsSupported(Entry) Then
                    SkippedCount += 1
                    Continue For
                End If
                Dim Value = ValidateValue(Pair, Entry)
                If Entry.Source = Settings.Sources.Normal Then
                    If Value.Contains(vbCr) OrElse Value.Contains(vbLf) Then Throw New InvalidDataException("设置值不能包含换行：" & Pair.Name)
                    Normal.Add(Pair.Name, Value)
                Else
                    Portable.Add(Pair.Name, Value)
                End If
            Next
            For Each Pair In Variables.Properties()
                If IsVariable(Pair.Name) Then
                    Portable.Add(Pair.Name, ReadValue(Pair))
                Else
                    SkippedCount += 1
                End If
            Next
        End Sub

        Private Shared Function ReadValue(Pair As JProperty) As String
            If Pair.Value.Type <> JTokenType.String Then Throw New InvalidDataException("设置值格式无效：" & Pair.Name)
            Return CStr(Pair.Value)
        End Function

        ''' <summary>全部校验及解压完成后才覆盖文件；失败时恢复已经覆盖的文件。</summary>
        Public Sub Apply()
            If Applied Then Throw New InvalidOperationException("该配置包已导入。")
            PortableSettings.RunExclusive(
                Sub()
                    Dim SetupPath = Paths.Base & "PCL\Setup.ini"
                    EnsureNoLinks(SetupPath)
                    EnsureNoLinks(PortableSettings.FilePath)
                    Dim Setup As New Dictionary(Of String, String)(StringComparer.Ordinal)
                    If File.Exists(SetupPath) Then
                        For Each Line In File.ReadAllLines(SetupPath, Encoding.UTF8)
                            Dim Index = Line.IndexOf(":"c)
                            If Index > 0 Then Setup(Line.Substring(0, Index)) = Line.Substring(Index + 1)
                        Next
                    End If
                    For Each Pair In Normal
                        Setup(Pair.Key) = Pair.Value
                    Next
                    Dim Current = PortableSettings.ReadAll()
                    For Each Pair In Portable
                        Current(Pair.Key) = Pair.Value
                    Next
                    If InstanceCount > 0 Then
                        EnsureNoLinks(InstanceRoot)
                        If Directory.Exists(InstanceRoot) OrElse File.Exists(InstanceRoot.TrimEnd("\"c)) Then Throw New IOException("实例导入目标已存在，请重新选择配置包后重试。")
                        Directory.CreateDirectory(InstanceRoot)
                        OwnsInstanceRoot = True
                        Current("LaunchFolders") = Current.GetOrDefault("LaunchFolders", "").TrimEnd("|"c) & "|备份导入>" & InstanceRoot
                        Setup("LaunchFolderSelect") = InstanceRoot.Replace(Paths.Base, "$")
                    End If
                    Dim Writes As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
                    Dim StagedSetup = Path.Combine(StageDirectory, "Setup.ini")
                    File.WriteAllLines(StagedSetup, Setup.Select(Function(Pair) Pair.Key & ":" & Pair.Value), Utf8)
                    Writes.Add(SetupPath, StagedSetup)
                    Dim StagedPortable = Path.Combine(StageDirectory, "Portable.json")
                    File.WriteAllText(StagedPortable, JsonConvert.SerializeObject(Current, Formatting.Indented), Utf8)
                    Writes.Add(PortableSettings.FilePath, StagedPortable)
                    For Each Pair In Assets
                        Writes.Add(Paths.Base & "PCL\" & Pair.Key.Replace("/", "\"), Pair.Value)
                    Next
                    For Each Pair In InstanceWrites
                        Writes.Add(Pair.Key, Pair.Value)
                    Next
                    CommitFiles(Writes)
                    Applied = True
                    IniClearCache("Setup")
                    For Each Key In Normal.Keys.Concat(Portable.Keys).Concat({"LaunchFolders", "LaunchFolderSelect"})
                        Dim Entry As Settings.Setting = Nothing
                        If Settings.Entries.TryGetValue(Key, Entry) Then Entry.ValueCache.Clear()
                    Next
                End Sub)
        End Sub

        Private Sub CommitFiles(Writes As Dictionary(Of String, String))
            Dim Completed As New List(Of KeyValuePair(Of String, String))
            '先检查全部目标，避免遇到非法路径时已经覆盖了一部分配置。
            For Each Target In Writes.Keys
                EnsureNoLinks(Target)
                If Directory.Exists(Target) Then Throw New IOException("配置文件位置被文件夹占用：" & Target)
            Next
            Try
                For Each Pair In Writes
                    Directory.CreateDirectory(Path.GetDirectoryName(Pair.Key))
                    Dim Backup As String = Nothing
                    If File.Exists(Pair.Key) Then
                        Backup = Path.Combine(StageDirectory, "backup-" & Completed.Count)
                        File.Replace(Pair.Value, Pair.Key, Backup)
                    Else
                        File.Move(Pair.Value, Pair.Key)
                    End If
                    Completed.Add(New KeyValuePair(Of String, String)(Pair.Key, Backup))
                Next
            Catch ImportError As Exception
                Dim Errors As New List(Of Exception) From {ImportError}
                For Each Pair In Completed.AsEnumerable().Reverse()
                    Try
                        If Pair.Value Is Nothing Then
                            File.Delete(Pair.Key)
                        Else
                            File.Copy(Pair.Value, Pair.Key, True)
                        End If
                    Catch RestoreError As Exception
                        Errors.Add(RestoreError)
                    End Try
                Next
                If Errors.Count > 1 Then
                    '恢复失败时必须保留备份，不能在 Dispose 中清理。
                    KeepBackup = True
                    Throw New IOException("导入失败，部分原文件未能自动恢复。请保留备份目录：" & StageDirectory, New AggregateException(Errors))
                End If
                Throw New IOException("导入失败，已恢复原配置。文件可能正在使用中，请关闭相关程序后重试。", ImportError)
            End Try
        End Sub

        Private KeepBackup As Boolean
        Public Sub Dispose() Implements IDisposable.Dispose
            If KeepBackup OrElse Not Directory.Exists(StageDirectory) Then Return
            Try
                EnsureNoLinks(StageDirectory)
                Directory.Delete(StageDirectory, True)
                If Not Applied AndAlso OwnsInstanceRoot AndAlso Directory.Exists(InstanceRoot) Then
                    EnsureNoLinks(InstanceRoot)
                    Directory.Delete(InstanceRoot, True)
                End If
            Catch ex As IOException
                Logger.Warn(ex, "清理配置导入临时文件失败")
            Catch ex As UnauthorizedAccessException
                Logger.Warn(ex, "清理配置导入临时文件失败")
            End Try
        End Sub
    End Class
End Class
