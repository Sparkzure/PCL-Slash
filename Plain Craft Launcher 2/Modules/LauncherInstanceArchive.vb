
''' <summary>配置备份中的实例使用 Modrinth 整合包布局，只携带 overrides 和版本元数据。</summary>
Friend NotInheritable Class LauncherInstanceArchive
    Private Shared ReadOnly Utf8 As New UTF8Encoding(False, True)
    Friend Const PendingFile As String = "PCL\SettingsImportPending.json"

    'Forge/NeoForge 的处理器产物无法只通过 libraries 下载补齐，首次启动复用正常组件安装流程。
    Friend Shared Function PendingInstall(Instance As McInstance) As McInstallRequest
        Dim FileName = Instance.PathVersion & PendingFile
        If Not File.Exists(FileName) Then Return Nothing
        Dim Components = ReadJson(FileName).ToObject(Of McComponents)()
        If Components Is Nothing OrElse String.IsNullOrWhiteSpace(Components.MinecraftVersion) Then Throw New InvalidDataException("导入实例的安装记录无效。")
        Dim Request As New McInstallRequest With {.Components = Components}
        If Components.ModLoaderVersions.ContainsKey(ModLoaders.LiteLoader) Then
            Dim Libraries As New JArray(If(TryCast(Instance.JsonObject("libraries"), JArray), New JArray()).
                Where(Function(Item) Not CStr(Item("name")).StartsWith("com.mumfrey:liteloader:", StringComparison.Ordinal)).Select(Function(Item) Item.DeepClone()))
            Request.LiteLoaderEntry = New DlLiteLoaderListEntry With {
                .Inherit = Components.MinecraftVersion,
                .ReleaseTime = Instance.Version.ReleaseTime.ToString("yyyy/MM/dd HH:mm", Globalization.CultureInfo.InvariantCulture),
                .JsonToken = New JObject From {{"version", Components.ModLoaderVersions(ModLoaders.LiteLoader)},
                    {"libraries", Libraries}, {"tweakClass", "com.mumfrey.liteloader.launch.LiteLoaderTweaker"}}}
        End If
        Return Request
    End Function
    '与整合包导出的默认内容一致：配置、Mod、脚本、资源包等；不包含存档和运行资源。
    Private Shared ReadOnly ContentFolders As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
        "mods", "coremods", "lib", "config", "defaultconfigs", "configureddefaults", "resourcepacks", "texturepacks", "shaderpacks",
        "scripts", "resources", "kubejs", "kubejs-client", "kubejs-server", "datapacks", "global_packs", "global_resource_packs",
        "global_data_packs", "optional_data_packs", "moonlight-global-datapacks", "openloader", "patchouli_books", "structures",
        "fontfiles", "oresources", "packmenu", "craftpresence", "pointblanks", "mods-resourcepacks", "resource_assorts",
        "hotai", "bansoukou", "addons", "multiblocked", "modpack-update-checker", "matmos", "worldshape", "tacz"}
    Private Shared ReadOnly ContentFiles As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase) From {
        "options.txt", "optionsof.txt", "optionsshaders.txt", "icon.png", "resource_assorts.json", "TrashSlotSaveState.json",
        "customfov.txt", "paragliderSettings.nbt", "liteloader.properties", "default_reference.xml"}

    Friend Shared Function IsContent(Name As String) As Boolean
        Dim Parts = Name.Split("/"c)
        If Parts.Any(Function(Part) Part.Equals("java", StringComparison.OrdinalIgnoreCase) OrElse
            Part.Equals("runtime", StringComparison.OrdinalIgnoreCase) OrElse Part.Equals("jre", StringComparison.OrdinalIgnoreCase) OrElse
            Part.Equals("jvm", StringComparison.OrdinalIgnoreCase) OrElse Part.Equals("jdk", StringComparison.OrdinalIgnoreCase) OrElse Part.StartsWith("jre-", StringComparison.OrdinalIgnoreCase) OrElse
            Part.StartsWith("jdk-", StringComparison.OrdinalIgnoreCase)) Then Return False
        If Name.StartsWith("PCL/", StringComparison.OrdinalIgnoreCase) Then Return Name.Equals("PCL/Logo.png", StringComparison.OrdinalIgnoreCase)
        If Parts.Any(Function(Part) {".git", ".connector", ".fabric", "logs", "crash-reports", "cache", "caches"}.Contains(Part.ToLowerInvariant())) Then Return False
        If Name.EndsWith(".log", StringComparison.OrdinalIgnoreCase) OrElse Name.EndsWith(".dat_old", StringComparison.OrdinalIgnoreCase) Then Return False
        Return If(Parts.Length = 1, ContentFiles.Contains(Name), ContentFolders.Contains(Parts(0)))
    End Function

    Private Shared Function Roots() As IEnumerable(Of String)
        Dim Result As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
        Dim AddRoot As Action(Of String) =
            Sub(Value)
                If String.IsNullOrWhiteSpace(Value) Then Return
                Dim Full = Path.GetFullPath(Value.Replace("$", Paths.Base)).TrimEnd("\"c, "/"c) & "\"
                If Not Directory.Exists(Full & "versions") Then Return
                LauncherSettingsArchive.EnsureNoLinks(Full)
                Result.Add(Full)
            End Sub
        AddRoot(Paths.Base)
        For Each Folder In Directory.EnumerateDirectories(Paths.Base)
            '内部数据目录只读取已注册的实例，避免再次打包迁入缓存。
            If (Not Path.GetFileName(Folder).Equals("PCL", StringComparison.OrdinalIgnoreCase) AndAlso Not Path.GetFileName(Folder).StartsWith(".")) OrElse
                Path.GetFileName(Folder).Equals(".minecraft", StringComparison.OrdinalIgnoreCase) Then AddRoot(Folder)
        Next
        AddRoot(Settings.Get(Of String)("LaunchFolderSelect"))
        For Each Item In Settings.Get(Of String)("LaunchFolders").Split("|"c)
            Dim Separator = Item.IndexOf(">"c)
            If Separator >= 0 Then AddRoot(Item.Substring(Separator + 1))
        Next
        Return Result.OrderBy(Function(Value) Value, StringComparer.OrdinalIgnoreCase)
    End Function

    Private Shared Function ReadJson(FileName As String) As JObject
        LauncherSettingsArchive.EnsureNoLinks(FileName)
        If New FileInfo(FileName).Length > LauncherSettingsArchive.MaxManifestBytes Then Throw New InvalidDataException("实例版本信息过大：" & FileName)
        Return JObject.Parse(File.ReadAllText(FileName, Utf8))
    End Function

    Private Shared Function VersionJson(Root As String, Name As String, Seen As HashSet(Of String)) As JObject
        LauncherSettingsArchive.ValidateName(Name)
        If Name.Contains("/") OrElse Not Seen.Add(Name) Then Throw New InvalidDataException("实例版本继承无效：" & Name)
        Dim Value = ReadJson(Path.Combine(Root, "versions", Name, Name & ".json"))
        Dim Parent = CStr(Value("inheritsFrom"))
        If Not String.IsNullOrEmpty(Parent) Then
            Dim Base = VersionJson(Root, Parent, Seen)
            Dim Libraries = If(TryCast(Value("libraries"), JArray), New JArray()).DeepClone()
            For Each Library In If(TryCast(Base("libraries"), JArray), New JArray())
                CType(Libraries, JArray).Add(Library.DeepClone())
            Next
            Base.Merge(Value)
            Base("libraries") = Libraries
            Value = Base
        End If
        Value.Remove("inheritsFrom")
        Value.Remove("jar")
        For Each Key In {"javaDir", "javaPath", "javaExecutable"}
            Value.Remove(Key)
        Next
        Return Value
    End Function

    Private Shared Function InstanceSettings(Folder As String) As JObject
        Dim Result As New JObject
        Dim FileName = Path.Combine(Folder, "PCL\Setup.ini")
        LauncherSettingsArchive.EnsureNoLinks(FileName)
        If File.Exists(FileName) Then
            For Each Line In File.ReadAllLines(FileName, Encoding.UTF8)
                Dim Separator = Line.IndexOf(":"c)
                If Separator < 1 Then Continue For
                Dim Key = Line.Substring(0, Separator)
                Dim Entry As Settings.Setting = Nothing
                If Settings.Entries.TryGetValue(Key, Entry) AndAlso Entry.Source = Settings.Sources.Instance AndAlso
                    Not Entry.Encrypted AndAlso Not LauncherSettingsArchive.JavaLocationKeys.Contains(Key) Then Result(Key) = Line.Substring(Separator + 1)
            Next
        End If
        Return Result
    End Function

    Private Shared Function GameDirectory(Root As String, Folder As String, Values As JObject, Version As McVersion) As String
        If Values("VersionArgumentIndieV2") IsNot Nothing Then Return If(Boolean.Parse(CStr(Values("VersionArgumentIndieV2"))), Folder, Root)
        Dim Old As Integer
        If Integer.TryParse(CStr(Values("VersionArgumentIndie")), Old) AndAlso Old > 0 Then Return If(Old = 1, Folder, Root)
        If Directory.Exists(Folder & "mods") AndAlso Directory.EnumerateFiles(Folder & "mods").Any() Then Return Folder
        If Directory.Exists(Folder & "saves") AndAlso Directory.EnumerateDirectories(Folder & "saves").Any() Then Return Folder
        Dim IsRelease = Not Version.IsSnapshot AndAlso Not Version.IsFool AndAlso Version.VanillaName <> "Old"
        Dim Modable = Version.ModLoaders.Flags.Any()
        Select Case Settings.Get(Of Integer)("LaunchArgumentIndieV2")
            Case 0 : Return Root
            Case 1 : Return If(Modable, Folder, Root)
            Case 2 : Return If(Not IsRelease, Folder, Root)
            Case 3 : Return If(Not IsRelease OrElse Modable, Folder, Root)
            Case Else : Return Folder
        End Select
    End Function

    Friend NotInheritable Class ExportBatch
        Implements IDisposable
        Private ReadOnly Work As String = Paths.Base & "PCL\Temp\SettingsExport-" & Guid.NewGuid().ToString("N")
        Friend ReadOnly Packs As New List(Of String)
        Friend Bytes As Long
        Friend Entries As Integer

        Friend Sub Build()
            LauncherSettingsArchive.EnsureNoLinks(Work)
            Directory.CreateDirectory(Work)
            For Each Root In Roots()
                LauncherSettingsArchive.EnsureNoLinks(Root & "versions")
                For Each Folder In Directory.EnumerateDirectories(Root & "versions").OrderBy(Function(Value) Value, StringComparer.OrdinalIgnoreCase)
                    LauncherSettingsArchive.EnsureNoLinks(Folder)
                    Dim Name = Path.GetFileName(Folder)
                    If Not File.Exists(Path.Combine(Folder, Name & ".json")) Then Continue For
                    Dim Json = VersionJson(Root, Name, New HashSet(Of String)(StringComparer.OrdinalIgnoreCase))
                    Dim Version As New McVersion(Name, Json)
                    If Version.VanillaName = "Unknown" Then Throw New InvalidDataException("无法识别实例的 Minecraft 版本：" & Name)
                    Json("clientVersion") = Version.VanillaName
                    Dim Values = InstanceSettings(Folder)
                    Dim Game = GameDirectory(Root, Folder & "\", Values, Version)
                    Dim Dependencies As New JObject From {{"minecraft", Version.VanillaName}}
                    For Each Pair In Version.ModLoaderVersions
                        If String.IsNullOrWhiteSpace(Pair.Value) OrElse Pair.Value = "未知版本" Then Throw New InvalidDataException("无法识别实例的 Mod Loader 版本：" & Name)
                        Dim Key As String = Nothing
                        Select Case Pair.Key
                            Case ModLoaders.Forge : Key = "forge"
                            Case ModLoaders.NeoForge : Key = "neoforge"
                            Case ModLoaders.Fabric : Key = "fabric-loader"
                            Case ModLoaders.LiteLoader : Key = "liteloader"
                        End Select
                        If Key IsNot Nothing Then Dependencies(Key) = Pair.Value
                    Next
                    Dim Index As New JObject From {{"game", "minecraft"}, {"formatVersion", 1}, {"versionId", "1.0.0"},
                        {"name", Name}, {"files", New JArray()}, {"dependencies", Dependencies}}
                    Dim Components As New JObject From {{"MinecraftVersion", Version.VanillaName}, {"ModLoaderVersions", JObject.FromObject(Version.ModLoaderVersions)}}
                    If Version.HasOptiFine AndAlso Not Version.ModLoaderVersions.Any() Then
                        Dim ConfigFile = Path.Combine(Folder, "PCL\config.json")
                        Dim OptiFine As JToken = Nothing
                        If File.Exists(ConfigFile) Then OptiFine = ReadJson(ConfigFile)("MinecraftInstallManifest")?("Components")?("OptiFineEntry")
                        If OptiFine Is Nothing Then Throw New InvalidDataException("独立 OptiFine 实例缺少安装清单，请先修复或重新安装该实例后导出：" & Name)
                        Components("OptiFineEntry") = OptiFine.DeepClone()
                    End If
                    Dim Metadata As New JObject From {{"format", "PCL-Slash.Instance"}, {"version", 1}, {"versionJson", Json}, {"settings", Values}, {"components", Components}}
                    Dim Pack = Path.Combine(Work, (Packs.Count + 1).ToString("D4") & ".mrpack")
                    Using Output As New FileStream(Pack, FileMode.CreateNew, FileAccess.Write, FileShare.None), Zip As New ZipArchive(Output, ZipArchiveMode.Create)
                        AddText(Zip, "modrinth.index.json", Index.ToString(Formatting.Indented))
                        AddText(Zip, "pcl-slash.instance.json", Metadata.ToString(Formatting.Indented))
                        For Each Item In Directory.EnumerateFileSystemEntries(Game)
                            Dim Relative = Path.GetFileName(Item)
                            If Directory.Exists(Item) Then
                                If ContentFolders.Contains(Relative) Then AddFolder(Zip, Item, Relative)
                            ElseIf IsContent(Relative) Then
                                AddFile(Zip, Item, Relative)
                            End If
                        Next
                        Dim Logo = Path.Combine(Folder, "PCL\Logo.png")
                        If File.Exists(Logo) Then AddFile(Zip, Logo, "PCL/Logo.png")
                    End Using
                    Packs.Add(Pack)
                Next
            Next
        End Sub

        Private Sub Count(Length As Long)
            If Length < 0 OrElse Length > LauncherSettingsArchive.MaxBytes - Bytes Then Throw New IOException("配置与实例内容总大小超过 2 GB。")
            Bytes += Length
            Entries += 1
            If Entries > LauncherSettingsArchive.MaxEntries Then Throw New IOException("配置与实例中的文件过多。")
        End Sub
        Private Sub AddText(Zip As ZipArchive, Name As String, Text As String)
            Dim Data = Utf8.GetBytes(Text)
            If Data.LongLength > LauncherSettingsArchive.MaxManifestBytes Then Throw New IOException("实例版本信息过大。")
            Count(Data.LongLength)
            Using Stream = Zip.CreateEntry(Name).Open()
                Stream.Write(Data, 0, Data.Length)
            End Using
        End Sub
        Private Sub AddFile(Zip As ZipArchive, Source As String, Relative As String)
            If Not IsContent(Relative) Then Return
            LauncherSettingsArchive.ValidateName(Relative)
            LauncherSettingsArchive.EnsureNoLinks(Source)
            Using Input As New FileStream(Source, FileMode.Open, FileAccess.Read, FileShare.Read), Output = Zip.CreateEntry("overrides/" & Relative, CompressionLevel.Optimal).Open()
                Count(Input.Length)
                Input.CopyTo(Output)
            End Using
        End Sub
        Private Sub AddFolder(Zip As ZipArchive, Source As String, Relative As String)
            LauncherSettingsArchive.EnsureNoLinks(Source)
            For Each Child In Directory.EnumerateFileSystemEntries(Source)
                Dim Name = Relative & "/" & Path.GetFileName(Child)
                If Directory.Exists(Child) Then
                    '用虚拟子文件判断目录是否属于允许范围，及早跳过缓存与 Java。
                    If IsContent(Name & "/_") Then AddFolder(Zip, Child, Name)
                Else
                    AddFile(Zip, Child, Name)
                End If
            Next
        End Sub
        Public Sub Dispose() Implements IDisposable.Dispose
            If Directory.Exists(Work) Then
                LauncherSettingsArchive.EnsureNoLinks(Work)
                Directory.Delete(Work, True)
            End If
        End Sub
    End Class

    Friend Shared Sub Prepare(PackFile As String, Stage As String, Name As String, Writes As Dictionary(Of String, String),
                              ByRef Total As Long, ByRef EntryCount As Integer)
        Using Input As New FileStream(PackFile, FileMode.Open, FileAccess.Read, FileShare.Read), Zip As New ZipArchive(Input, ZipArchiveMode.Read)
            Dim Names As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)
            For Each Entry In Zip.Entries
                LauncherSettingsArchive.ValidateName(Entry.FullName)
                If Not Names.Add(Entry.FullName) Then Throw New InvalidDataException("实例包包含重复文件。")
                If Entry.FullName <> "modrinth.index.json" AndAlso Entry.FullName <> "pcl-slash.instance.json" AndAlso
                    (Not Entry.FullName.StartsWith("overrides/", StringComparison.Ordinal) OrElse Not IsContent(Entry.FullName.Substring(10))) Then
                    Throw New InvalidDataException("实例包包含支持范围外的文件：" & Entry.FullName)
                End If
                If Entry.Length < 0 OrElse Entry.Length > LauncherSettingsArchive.MaxBytes - Total Then Throw New InvalidDataException("配置与实例展开后超过 2 GB。")
                Total += Entry.Length
                EntryCount += 1
                If EntryCount > LauncherSettingsArchive.MaxEntries Then Throw New InvalidDataException("配置与实例文件过多。")
            Next
            Dim Index = ReadDocument(Zip.GetEntry("modrinth.index.json"))
            Dim Metadata = ReadDocument(Zip.GetEntry("pcl-slash.instance.json"))
            If CStr(Index("game")) <> "minecraft" OrElse CInt(Index("formatVersion")) <> 1 OrElse
                TryCast(Index("files"), JArray) Is Nothing OrElse CType(Index("files"), JArray).Count <> 0 OrElse
                String.IsNullOrWhiteSpace(CStr(Index("dependencies")?("minecraft"))) OrElse
                CStr(Metadata("format")) <> "PCL-Slash.Instance" OrElse CInt(Metadata("version")) <> 1 Then Throw New InvalidDataException("实例整合包格式不受支持。")
            Dim Json = TryCast(Metadata("versionJson"), JObject)
            Dim Values = TryCast(Metadata("settings"), JObject)
            If Json Is Nothing OrElse Json("mainClass")?.Type <> JTokenType.String OrElse Values Is Nothing Then Throw New InvalidDataException("实例包缺少版本信息。")
            Dim Components = Metadata("components")?.ToObject(Of McComponents)()
            If Components Is Nothing OrElse Components.ModLoaderVersions Is Nothing OrElse
                Components.MinecraftVersion <> CStr(Index("dependencies")("minecraft")) Then Throw New InvalidDataException("实例安装组件与整合包清单不一致。")
            For Each Version In Components.ModLoaderVersions.Values.Concat({Components.MinecraftVersion})
                LauncherSettingsArchive.ValidateName(Version)
                If Version.Contains("/") Then Throw New InvalidDataException("实例安装组件版本无效。")
            Next
            Json("id") = Name
            Json.Remove("inheritsFrom")
            Json.Remove("jar")
            For Each Key In {"javaDir", "javaPath", "javaExecutable"}
                Json.Remove(Key)
            Next
            Dim Setup As New List(Of String)
            For Each Pair In Values.Properties()
                Dim Entry As Settings.Setting = Nothing
                If Not Settings.Entries.TryGetValue(Pair.Name, Entry) OrElse Entry.Source <> Settings.Sources.Instance OrElse Entry.Encrypted OrElse
                    LauncherSettingsArchive.JavaLocationKeys.Contains(Pair.Name) Then Continue For
                Dim Value = LauncherSettingsArchive.ValidateValue(Pair, Entry)
                If Pair.Name <> "VersionArgumentIndieV2" Then Setup.Add(Pair.Name & ":" & Value)
            Next
            Setup.Add("VersionArgumentIndieV2:True")
            Directory.CreateDirectory(Stage)
            Dim JsonFile = Path.Combine(Stage, "version.json")
            File.WriteAllText(JsonFile, Json.ToString(Formatting.Indented), Utf8)
            Writes.Add(Name & ".json", JsonFile)
            Dim SetupFile = Path.Combine(Stage, "Setup.ini")
            File.WriteAllLines(SetupFile, Setup, Utf8)
            Writes.Add("PCL/Setup.ini", SetupFile)
            If Components.ModLoaderVersions.Any() OrElse Components.OptiFineEntry IsNot Nothing Then
                Dim Pending = Path.Combine(Stage, "pending.json")
                File.WriteAllText(Pending, JObject.FromObject(Components).ToString(Formatting.Indented), Utf8)
                Writes.Add(PendingFile.Replace("\", "/"), Pending)
            End If
            For Each Entry In Zip.Entries.Where(Function(Item) Item.FullName.StartsWith("overrides/", StringComparison.Ordinal))
                Dim Relative = Entry.FullName.Substring(10)
                Dim Target = Path.Combine(Stage, "overrides", Relative.Replace("/", "\"))
                Directory.CreateDirectory(Path.GetDirectoryName(Target))
                Using Stream = Entry.Open(), Output As New FileStream(Target, FileMode.CreateNew, FileAccess.Write, FileShare.None)
                    LauncherSettingsArchive.CopyEntry(Stream, Output, Entry.Length)
                End Using
                Writes.Add(Relative, Target)
            Next
            If Writes.ContainsKey("PCL/Logo.png") Then File.AppendAllText(SetupFile, "Logo:PCL\Logo.png" & vbCrLf & "LogoCustom:True" & vbCrLf, Utf8)
        End Using
    End Sub

    Friend Shared Function ReadDocument(Entry As ZipArchiveEntry) As JObject
        If Entry Is Nothing OrElse Entry.Length > LauncherSettingsArchive.MaxManifestBytes Then Throw New InvalidDataException("实例整合包缺少清单或清单过大。")
        Using Input = Entry.Open(), Buffer As New MemoryStream()
            LauncherSettingsArchive.CopyEntry(Input, Buffer, Entry.Length)
            Buffer.Position = 0
            Using Text As New StreamReader(Buffer, Utf8), Reader As New JsonTextReader(Text)
                Reader.MaxDepth = 64
                Reader.DateParseHandling = DateParseHandling.None
                Dim Value = JObject.Load(Reader, New JsonLoadSettings With {.DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error})
                If Reader.Read() Then Throw New InvalidDataException("实例清单末尾包含额外内容。")
                Return Value
            End Using
        End Using
    End Function
End Class
