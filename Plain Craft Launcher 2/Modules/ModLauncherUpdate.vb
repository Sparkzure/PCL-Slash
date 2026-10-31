Imports System.Text.RegularExpressions

'只读取发布信息和打开网页，程序更新由用户手动完成。
Public Module ModLauncherUpdate
    Public Const LauncherReleasesUrl As String = SourceRepository & "/releases"
    Private LatestReleaseTag As String
    Private ReadOnly ReleaseLock As New Object

    Public LauncherReleaseLoader As New LoaderTask(Of Integer, Integer)("启动器更新通知", AddressOf CheckLauncherReleases,
        Priority:=ThreadPriority.BelowNormal) With {.ReloadTimeout = 1000 * 60 * 60}

    Public Sub ShowLauncherUpdateDialog(Optional NewVersion As String = Nothing)
        Dim Message = If(String.IsNullOrEmpty(NewVersion), "", $"发现新版本：{NewVersion}{vbCrLf}{vbCrLf}") &
            $"请前往 Releases 页面自行下载新版，解压后退出启动器，将新版 EXE 替换当前的 {LauncherFileName}，再重新打开即可完成更新。{vbCrLf}{vbCrLf}请保留原有的 PCL 文件夹和游戏文件夹，以继续使用已有设置与游戏。"
        If MyMsgBox(Message, "启动器更新", "前往 Releases", "取消") = 1 Then OpenWebsite(LauncherReleasesUrl)
    End Sub

    Private Sub CheckLauncherReleases()
        If Not Settings.Get(Of Boolean)("SystemLauncherUpdateNotify") Then
            HintLauncherUpdateStatus("更新通知已关闭")
            Return
        End If
        HintLauncherUpdateStatus("正在获取……")
        Try
            Dim Channel = GetLauncherUpdateChannel(VersionBaseName, BuildType = BuildTypes.Release)
            Dim ApiUrl = SourceRepository.Replace("https://github.com/", "https://api.github.com/repos/") & "/releases"
            ApiUrl &= If(Channel = "release", "/latest", "?per_page=100")
            Dim Response = NetRequestByClient(ApiUrl, Accept:="application/vnd.github+json", Timeout:=15000,
                Headers:={{"X-GitHub-Api-Version", "2022-11-28"}}, RequireJson:=True)
            Dim Releases = If(Channel = "release", New JArray(JObject.Parse(Response)), JArray.Parse(Response))
            Dim Latest = FindLatestLauncherRelease(Releases, Channel)
            If Latest Is Nothing Then
                HintLauncherUpdateStatus("暂无可用发布")
                Return
            End If
            Dim Tag = Latest("tag_name").ToString()
            Dim Comparison = CompareLauncherVersions(Tag, VersionBaseName)
            If Not Comparison.HasValue Then
                HintLauncherUpdateStatus("无法识别版本信息", HintType.Red)
                Return
            End If
            SyncLock ReleaseLock
                LatestReleaseTag = Tag
            End SyncLock
            If Comparison.Value <= 0 Then
                HintLauncherUpdateStatus("未发现新版本", HintType.Green)
                Return
            End If
            HintLauncherUpdateStatus($"发现新版 {Tag}", HintType.Green)
            RunInUi(Sub()
                        If IsProgramEnding OrElse Not Settings.Get(Of Boolean)("SystemLauncherUpdateNotify") Then Return
                        If Settings.Get(Of String)("HintLauncherReleaseTag") = Tag Then Return
                        Settings.Set("HintLauncherReleaseTag", Tag)
                        ShowLauncherUpdateDialog(Tag)
                    End Sub)
        Catch ex As Exception
            '网络错误、API 限流或尚无正式发布时，不影响启动，也不误报为最新版。
            If TypeOf ex Is HttpRequestCodeException AndAlso CType(ex, HttpRequestCodeException).StatusCode = Net.HttpStatusCode.NotFound Then
                HintLauncherUpdateStatus("暂无可用发布")
            Else
                HintLauncherUpdateStatus("获取失败", HintType.Red)
            End If
            Logger.Warn(ex, "获取 GitHub Releases 更新通知失败")
        End Try
    End Sub

    Private Sub HintLauncherUpdateStatus(Message As String, Optional Type As HintType = HintType.Blue)
        If IsProgramEnding Then Return
        Hint(If(Settings.Get(Of Boolean)("SystemLauncherUpdateNotify"), "更新信息：" & Message, "更新通知已关闭"), Type)
    End Sub

    Public Function IsLauncherLatestRelease() As Boolean?
        SyncLock ReleaseLock
            Dim Comparison = CompareLauncherVersions(VersionBaseName, LatestReleaseTag)
            If Not Comparison.HasValue Then Return Nothing
            Return Comparison.Value >= 0
        End SyncLock
    End Function

    Friend Function GetLauncherUpdateChannel(CurrentVersion As String, IsReleaseBuild As Boolean) As String
        If IsReleaseBuild Then Return "release"
        Dim Channel = GetLauncherTagChannel(CurrentVersion)
        '本地未打标签的 Snapshot / Debug 构建默认使用快照通知通道。
        Return If(Channel Is Nothing OrElse Channel = "release", "snapshot", Channel)
    End Function

    Private Function GetLauncherTagChannel(Tag As String) As String
        If Not CompareLauncherVersions(Tag, Tag).HasValue Then Return Nothing
        Dim Version = Tag.Split("+"c)(0)
        Dim Dash = Version.IndexOf("-"c)
        If Dash < 0 Then Return "release"
        Return Version.Substring(Dash + 1).Split("."c)(0).ToLowerInvariant()
    End Function

    Friend Function FindLatestLauncherRelease(Releases As JArray, Channel As String) As JObject
        Dim Latest As JObject = Nothing
        For Each Entry In Releases.OfType(Of JObject)()
            Dim Draft, Prerelease As Boolean
            If Not Boolean.TryParse(Entry("draft")?.ToString(), Draft) OrElse Draft Then Continue For
            If Not Boolean.TryParse(Entry("prerelease")?.ToString(), Prerelease) Then Continue For
            If Entry("published_at") Is Nothing OrElse Entry("published_at").Type = JTokenType.Null Then Continue For
            Dim Tag = Entry("tag_name")?.ToString()
            Dim TagChannel = GetLauncherTagChannel(Tag)
            If TagChannel Is Nothing Then Continue For
            If TagChannel = "release" Then
                If Prerelease Then Continue For
            ElseIf TagChannel <> Channel Then
                Continue For
            End If
            If Latest Is Nothing OrElse CompareLauncherVersions(Tag, Latest("tag_name").ToString()).Value > 0 Then Latest = Entry
        Next
        Return Latest
    End Function

    '兼容项目的三段 / 四段数字版本；正式版高于同版本的预发布版，元数据不参与排序。
    Friend Function CompareLauncherVersions(LeftTag As String, RightTag As String) As Integer?
        Const Pattern As String = "^v?(\d+\.\d+\.\d+(?:\.\d+)?)(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$"
        Dim LeftMatch = Regex.Match(If(LeftTag, ""), Pattern)
        Dim RightMatch = Regex.Match(If(RightTag, ""), Pattern)
        If Not LeftMatch.Success OrElse Not RightMatch.Success Then Return Nothing
        Dim LeftVersion As Version = Nothing, RightVersion As Version = Nothing
        Dim LeftNumber = LeftMatch.Groups(1).Value
        Dim RightNumber = RightMatch.Groups(1).Value
        If Not Version.TryParse(LeftNumber & If(LeftNumber.Split("."c).Length = 3, ".0", ""), LeftVersion) OrElse
           Not Version.TryParse(RightNumber & If(RightNumber.Split("."c).Length = 3, ".0", ""), RightVersion) Then Return Nothing
        Dim Result = LeftVersion.CompareTo(RightVersion)
        If Result <> 0 Then Return Result
        Dim LeftPre = LeftMatch.Groups(2).Value
        Dim RightPre = RightMatch.Groups(2).Value
        If LeftPre = RightPre Then Return 0
        If LeftPre = "" Then Return 1
        If RightPre = "" Then Return -1
        Dim LeftParts = LeftPre.Split("."c), RightParts = RightPre.Split("."c)
        For Index = 0 To Math.Min(LeftParts.Length, RightParts.Length) - 1
            Dim LeftNumeric = Regex.IsMatch(LeftParts(Index), "^\d+$")
            Dim RightNumeric = Regex.IsMatch(RightParts(Index), "^\d+$")
            If LeftNumeric AndAlso RightNumeric Then
                Dim L = LeftParts(Index).TrimStart("0"c), R = RightParts(Index).TrimStart("0"c)
                Result = L.Length.CompareTo(R.Length)
                If Result = 0 Then Result = String.CompareOrdinal(L, R)
            ElseIf LeftNumeric <> RightNumeric Then
                Result = If(LeftNumeric, -1, 1)
            Else
                Result = String.CompareOrdinal(LeftParts(Index), RightParts(Index))
            End If
            If Result <> 0 Then Return Result
        Next
        Return LeftParts.Length.CompareTo(RightParts.Length)
    End Function
End Module
