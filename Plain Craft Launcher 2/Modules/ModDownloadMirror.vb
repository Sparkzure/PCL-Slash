
''' <summary>镜像地址独立于下载优先级，保留原有 BMCLAPI / MCIM 路径协议。</summary>
Public Module ModDownloadMirror
    Public Const MinecraftMirrorPreset As String = "https://bmclapi2.bangbang93.com"
    Public Const CommunityMirrorPreset As String = "https://mod.mcimirror.top"

    Public Function ValidateDownloadMirrorAddress(Address As String) As String
        Dim Value As Uri = Nothing
        Address = If(Address, "").Trim()
        If Address = "" Then Return "请填写镜像根地址。"
        If Address.Any(Function(C) Char.IsWhiteSpace(C) OrElse Char.IsControl(C)) OrElse Address.Contains("\") OrElse
            Not Uri.TryCreate(Address, UriKind.Absolute, Value) OrElse
            (Value.Scheme <> Uri.UriSchemeHttp AndAlso Value.Scheme <> Uri.UriSchemeHttps) OrElse String.IsNullOrEmpty(Value.Host) Then
            Return "请输入完整的 HTTP 或 HTTPS 镜像根地址。"
        End If
        If Value.UserInfo <> "" OrElse Address.Contains("?") OrElse Address.Contains("#") Then Return "镜像根地址不能包含用户名、密码、查询参数或片段。"
        Return ""
    End Function

    Private Function GetMirrorBase(SelectionKey As String, AddressKey As String, Preset As String) As String
        If Settings.Get(Of Integer)(SelectionKey) <> 1 Then Return Preset
        Dim Address = Settings.Get(Of String)(AddressKey).Trim()
        '编辑中的空值或无效备份配置不能中断全部下载，界面仍显示具体校验提示。
        If ValidateDownloadMirrorAddress(Address) <> "" Then Return Preset
        Return New Uri(Address).AbsoluteUri.TrimEnd("/"c)
    End Function

    Public ReadOnly Property MinecraftMirrorBase As String
        Get
            Return GetMirrorBase("ToolDownloadMinecraftMirror", "ToolDownloadMinecraftMirrorCustom", MinecraftMirrorPreset)
        End Get
    End Property
    Public ReadOnly Property CommunityMirrorBase As String
        Get
            Return GetMirrorBase("ToolDownloadCommunityMirror", "ToolDownloadCommunityMirrorCustom", CommunityMirrorPreset)
        End Get
    End Property

    Private Function IsUnderBase(Address As Uri, Root As Uri) As Boolean
        If Not String.Equals(Address.Scheme, Root.Scheme, StringComparison.OrdinalIgnoreCase) OrElse
            Not String.Equals(Address.Host, Root.Host, StringComparison.OrdinalIgnoreCase) OrElse Address.Port <> Root.Port Then Return False
        Dim Prefix = Root.AbsolutePath.TrimEnd("/"c)
        Return Prefix = "" OrElse Address.AbsolutePath = Prefix OrElse Address.AbsolutePath.StartsWith(Prefix & "/", StringComparison.Ordinal)
    End Function

    Private Function ReplacePreset(Address As Uri, Root As String) As String
        If IsUnderBase(Address, New Uri(Root)) Then Return Address.AbsoluteUri
        Return Root & Address.PathAndQuery & Address.Fragment
    End Function

    ''' <summary>在请求与文件下载入口处理旧预设地址，覆盖安装器、Java 及版本列表等原有调用。</summary>
    Public Function ResolveDownloadMirrorUrl(Address As String) As String
        Dim Value As Uri = Nothing
        If Not Uri.TryCreate(Address, UriKind.Absolute, Value) OrElse
            (Value.Scheme <> Uri.UriSchemeHttp AndAlso Value.Scheme <> Uri.UriSchemeHttps) OrElse Value.UserInfo <> "" OrElse Not Value.IsDefaultPort Then Return Address
        Select Case Value.Host.ToLowerInvariant()
            Case "bmclapi2.bangbang93.com" : Return ReplacePreset(Value, MinecraftMirrorBase)
            Case "mod.mcimirror.top" : Return ReplacePreset(Value, CommunityMirrorBase)
            Case Else : Return Address
        End Select
    End Function

    Public Function IsMinecraftDownloadMirror(Address As String) As Boolean
        Dim Value As Uri = Nothing
        If Not Uri.TryCreate(Address, UriKind.Absolute, Value) OrElse Value.UserInfo <> "" Then Return False
        Return IsUnderBase(Value, New Uri(MinecraftMirrorPreset)) OrElse IsUnderBase(Value, New Uri(MinecraftMirrorBase))
    End Function

    Public Function GetCommunityMirrorUrl(Address As String) As String
        Dim Value As Uri = Nothing
        If Not Uri.TryCreate(Address, UriKind.Absolute, Value) OrElse
            (Value.Scheme <> Uri.UriSchemeHttp AndAlso Value.Scheme <> Uri.UriSchemeHttps) OrElse Value.UserInfo <> "" OrElse Not Value.IsDefaultPort Then Return Address
        Dim Prefix As String
        Select Case Value.Host.ToLowerInvariant()
            Case "api.modrinth.com", "staging-api.modrinth.com" : Prefix = "/modrinth"
            Case "api.curseforge.com" : Prefix = "/curseforge"
            Case "cdn.modrinth.com", "edge.forgecdn.net", "mediafilez.forgecdn.net", "media.forgecdn.net" : Prefix = ""
            Case Else : Return ResolveDownloadMirrorUrl(Address)
        End Select
        Return CommunityMirrorBase & Prefix & Value.PathAndQuery & Value.Fragment
    End Function
End Module
