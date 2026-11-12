const { versionContents } = require('./stamp-version.cjs');
const { releasePlan } = require('./release-channel.cjs');
const BASE = 'Plain Craft Launcher 2/Modules/Base/ModBase.vb';
const ASSEMBLY = 'Plain Craft Launcher 2/My Project/AssemblyInfo.vb';
const MANIFEST = '.github/release-bot.json';
const FILES = [BASE, ASSEMBLY, MANIFEST];
const PREFIX = 'codex/release/';

function codes(base) {
  const match = base.match(/#If RELEASE Then\r?\n[ \t]*Public Const VersionCode As Integer = (\d+)[^\r\n]*\r?\n#Else\r?\n[ \t]*Public Const VersionCode As Integer = (\d+)[^\r\n]*\r?\n#End If/);
  if (!match) throw new Error('无法识别正式版和快照版 VersionCode，拒绝修改');
  return { release: Number(match[1]), snapshot: Number(match[2]), block: match[0] };
}

function prepare(base, assembly, channel, version) {
  if (!['release', 'snapshot'].includes(channel)) throw new Error('通道必须是 release 或 snapshot');
  if (typeof version !== 'string' || version !== version.trim() || version.startsWith('v')) throw new Error('版本号不应包含 v 前缀或空白');
  const tag = `v${version}`;
  const plan = releasePlan(tag);
  if (plan.channel !== channel) throw new Error('通道与版本号不一致：快照需预发布后缀，正式版不能有预发布后缀');
  const old = codes(base);
  const code = Math.max(old.release, old.snapshot) + 1;
  if (!Number.isSafeInteger(code) || code > 2147483647) throw new Error('VersionCode 超出 Integer 范围');
  let index = 0;
  const block = old.block.replace(/(Public Const VersionCode As Integer = )\d+/g, (text, prefix) =>
    index++ === (channel === 'release' ? 0 : 1) ? `${prefix}${code}` : text);
  const updated = versionContents(base.replace(old.block, block), assembly, tag);
  const manifest = { schema: 1, tag, channel, versionCode: code };
  return { tag, code, manifest, files: {
    [BASE]: updated.base, [ASSEMBLY]: updated.assembly, [MANIFEST]: JSON.stringify(manifest, null, 2) + '\n'
  } };
}

async function optional(call) {
  try { return await call(); } catch (error) { if (error.status === 404) return null; throw error; }
}

async function run({ github, context, core, channel, version, appSlug }) {
  const repo = context.repo;
  const defaultBranch = context.payload.repository.default_branch;
  if (!appSlug) throw new Error('缺少 GitHub App 身份');
  const login = `${appSlug}[bot]`;
  const read = async (path, ref) => {
    const { data } = await github.rest.repos.getContent({ ...repo, path, ref });
    if (data.type !== 'file' || data.encoding !== 'base64') throw new Error(`无法读取 ${path}`);
    return Buffer.from(data.content, 'base64').toString('utf8');
  };
  const tagRef = tag => optional(() => github.rest.git.getRef({ ...repo, ref: `tags/${tag}` }));
  const report = async text => { core.info(text); await core.summary.addRaw(text).write(); };

  if (context.eventName === 'workflow_dispatch') {
    if (context.ref !== `refs/heads/${defaultBranch}`) throw new Error('请在默认分支运行 Version Bot');
    const { data: branch } = await github.rest.repos.getBranch({ ...repo, branch: defaultBranch });
    const sha = branch.commit.sha;
    const result = prepare(await read(BASE, sha), await read(ASSEMBLY, sha), channel, version);
    const head = `${PREFIX}${result.tag}`;
    if (await tagRef(result.tag)) throw new Error('该版本标签已存在，请使用新版本号');
    const pulls = await github.paginate(github.rest.pulls.list, { ...repo, state: 'open', base: defaultBranch, per_page: 100 });
    const pending = pulls.filter(pr => pr.head.repo?.full_name === context.payload.repository.full_name && pr.head.ref.startsWith(PREFIX));
    if (pending.length) {
      if (pending.length === 1 && pending[0].head.ref === head && pending[0].user.login === login) {
        await report(`版本 PR 已存在：${pending[0].html_url}`); return;
      }
      throw new Error('已有待合并的版本 PR，请先合并或关闭，避免重复 VersionCode');
    }
    const last = await optional(() => read(MANIFEST, sha));
    if (last && !(await tagRef(JSON.parse(last).tag))) throw new Error('上一个版本尚未成功打标签，请先重跑它的 Version Bot 合并任务');
    const existingBranch = await optional(() => github.rest.git.getRef({ ...repo, ref: `heads/${head}` }));
    const { data: parent } = await github.rest.git.getCommit({ ...repo, commit_sha: sha });
    const { data: tree } = await github.rest.git.createTree({ ...repo, base_tree: parent.tree.sha,
      tree: Object.entries(result.files).map(([path, content]) => ({ path, content, mode: '100644', type: 'blob' })) });
    const title = `chore(release): prepare ${result.tag}`;
    if (existingBranch) {
      const { data: commit } = await github.rest.git.getCommit({ ...repo, commit_sha: existingBranch.data.object.sha });
      if (commit.tree.sha !== tree.sha || commit.parents.length !== 1 || commit.parents[0].sha !== sha) {
        throw new Error('版本分支已存在但内容或基线不匹配，请恢复原 PR 或使用新的版本号');
      }
    } else {
      const { data: commit } = await github.rest.git.createCommit({ ...repo, message: title, tree: tree.sha, parents: [sha] });
      await github.rest.git.createRef({ ...repo, ref: `refs/heads/${head}`, sha: commit.sha });
    }
    const { data: pr } = await github.rest.pulls.create({ ...repo, head, base: defaultBranch, title,
      body: `发布通道：${channel}\n\n目标标签：${result.tag}\n\nVersionCode：${result.code}（两个通道最大值 + 1）。\n\n验证：版本字段与通道已校验；请等待 Build 和提交规范检查通过后审核合并。合并后 Bot 自动打标签，构建只创建发布草稿，仍需管理员手动发布。\n\n请勿改动版本字段或混入其他文件；如基线编号变化，请关闭此 PR 并使用新版本重新创建。` });
    await report(`版本 PR：${pr.html_url}`);
    return;
  }

  if (context.eventName !== 'pull_request_target') throw new Error('不支持的事件');
  const { data: pr } = await github.rest.pulls.get({ ...repo, pull_number: context.payload.pull_request.number });
  if (!pr.merged || pr.base.ref !== defaultBranch || pr.head.repo?.full_name !== context.payload.repository.full_name ||
      pr.user.login !== login || !pr.head.ref.startsWith(PREFIX)) throw new Error('仅允许已合并的本仓库 Bot 版本 PR 打标签');
  const files = await github.paginate(github.rest.pulls.listFiles, { ...repo, pull_number: pr.number, per_page: 100 });
  if (files.length !== FILES.length || files.some(file => !FILES.includes(file.filename) || !['added', 'modified'].includes(file.status))) throw new Error('版本 PR 包含额外文件或重命名，拒绝打标签');
  const sha = pr.merge_commit_sha;
  const manifest = JSON.parse(await read(MANIFEST, sha));
  if (manifest.schema !== 1 || pr.head.ref !== `${PREFIX}${manifest.tag}`) throw new Error('版本清单与 PR 分支不一致');
  const { data: merged } = await github.rest.git.getCommit({ ...repo, commit_sha: sha });
  const parent = merged.parents[0]?.sha;
  if (!parent) throw new Error('合并提交没有父提交');
  const expected = prepare(await read(BASE, parent), await read(ASSEMBLY, parent), manifest.channel, manifest.tag.slice(1));
  for (const path of FILES) {
    if ((await read(path, sha)) !== expected.files[path]) throw new Error(`合并后的版本内容不匹配：${path}；请检查编号是否过期或 PR 被修改`);
  }
  const existing = await tagRef(expected.tag);
  if (existing) {
    if (existing.data.object.type !== 'commit' || existing.data.object.sha !== sha) throw new Error('标签已指向其他提交，拒绝覆盖');
    await report(`${expected.tag} 已指向合并提交，无需重复创建`); return;
  }
  // 使用 App 安装令牌创建轻量标签，继续触发 Build 的标签 push 流程。
  await github.rest.git.createRef({ ...repo, ref: `refs/tags/${expected.tag}`, sha });
  await report(`已创建 ${expected.tag} → ${sha}，请等待 Build 生成发布草稿。`);
}
module.exports = { prepare, codes, run, BASE, ASSEMBLY, MANIFEST };
