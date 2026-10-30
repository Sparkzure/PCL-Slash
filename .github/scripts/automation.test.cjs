const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { validateMessage, readCommits, readPolicyCommits } = require('./commit-policy.cjs');
const { validateTag, previousTag, renderNotes, draftBody } = require('./release-notes.cjs');
const updateDraft = require('./update-draft-release.cjs');
const { releasePlan, buildPlan } = require('./release-channel.cjs');
const { stampVersion } = require('./stamp-version.cjs');
function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pcl-automation-'));
  t.after(() => {
    assert.equal(path.resolve(path.dirname(directory)), path.resolve(os.tmpdir()));
    assert.ok(path.basename(directory).startsWith('pcl-automation-'));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  return directory;
}
test('commit policy accepts Chinese, scoped and breaking messages', () => {
  for (const message of ['feat: 新增主题', 'fix(theme): 修复切换\n\n保留原有选择。', 'refactor!: 修改接口\n\nBREAKING CHANGE: 接口调整']) assert.doesNotThrow(() => validateMessage(message));
  for (const message of ['更新主题', 'Feat: Theme', 'fix: ', 'fix: trailing space ', 'fix: no blank line\nbody', `feat: ${'字'.repeat(100)}`]) assert.throws(() => validateMessage(message));
});
test('three/four-part tags and prereleases are accepted; malformed tags rejected', () => {
  for (const tag of ['v1.2.3', 'v2.14.0.0', 'v1.2.3-beta.1', 'v1.2.3+build.4']) assert.equal(validateTag(tag), tag);
  for (const tag of ['1.2.3', 'v1.2', 'v1.2.3/evil', 'v1.2.3;echo', 'v1.2.3-']) assert.throws(() => validateTag(tag));
});
test('snapshot and stable tags select the corresponding build configuration', () => {
  assert.equal(releasePlan('v2.14.1.0-snapshot.1').configuration, 'Snapshot');
  assert.equal(releasePlan('v2.14.1-beta.2').prerelease, true);
  assert.equal(releasePlan('v2.14.1.0').configuration, 'Release');
  assert.equal(releasePlan('v2.14.1.0+build.1').prerelease, false);
  assert.deepEqual(buildPlan('tag', 'v1.2.3-rc.1').matrix.configuration, ['Snapshot']);
  assert.deepEqual(buildPlan('tag', 'v1.2.3').matrix.configuration, ['Release']);
  assert.deepEqual(buildPlan('branch', 'main').matrix.configuration, ['Debug', 'Snapshot', 'Release']);
  assert.throws(() => releasePlan('v1.2.99999'), /65534/);
});
test('tagged builds synchronize display and assembly versions, retaining VersionCode', t => {
  const root = fixture(t);
  const base = path.join(root, 'Plain Craft Launcher 2/Modules/Base/ModBase.vb');
  const assembly = path.join(root, 'Plain Craft Launcher 2/My Project/AssemblyInfo.vb');
  fs.mkdirSync(path.dirname(base), { recursive: true });
  fs.mkdirSync(path.dirname(assembly), { recursive: true });
  fs.writeFileSync(base, 'Public Const VersionBaseName As String = "2.14.0.0"\nPublic Const VersionCode As Integer = 411\n');
  fs.writeFileSync(assembly, '<Assembly: AssemblyVersion("2.14.0.0")>\n<Assembly: AssemblyFileVersion("2.14.0.0")>\n');
  stampVersion(root, 'v2.14.1-snapshot.3');
  assert.match(fs.readFileSync(base, 'utf8'), /VersionBaseName As String = "2.14.1-snapshot.3"/);
  assert.match(fs.readFileSync(base, 'utf8'), /VersionCode As Integer = 411/);
  assert.match(fs.readFileSync(assembly, 'utf8'), /AssemblyFileVersion\("2.14.1.0"\)/);
  assert.match(fs.readFileSync(assembly, 'utf8'), /AssemblyInformationalVersion\("2.14.1-snapshot.3"\)/);
  stampVersion(root, 'v2.14.1.0');
  assert.equal((fs.readFileSync(assembly, 'utf8').match(/AssemblyInformationalVersion/g) || []).length, 1);
  assert.match(fs.readFileSync(base, 'utf8'), /VersionBaseName As String = "2.14.1.0"/);
});
test('release range uses reachable previous tags and retains full commit bodies', t => {
  const cwd = fixture(t);
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  const commit = message => git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', message]);
  git(['init', '--initial-branch=main']);
  commit('chore: initial');
  git(['tag', 'v1.0.0']);
  assert.equal(previousTag('v1.0.0', cwd), null);
  git(['checkout', '-b', 'unrelated']);
  commit('feat: unrelated');
  git(['tag', 'v99.0.0']);
  git(['checkout', 'main']);
  commit('feat(theme): 苍绿色\n\n使用 #39C5BB。\n\n验证：构建通过。');
  git(['tag', 'v1.1.0-snapshot.1']);
  commit('fix: 修正快照问题');
  git(['tag', 'v1.1.0-snapshot.2']);
  assert.equal(previousTag('v1.1.0-snapshot.2', cwd), 'v1.1.0-snapshot.1');
  commit('chore: prepare stable');
  git(['tag', 'v1.1.0']);
  assert.equal(previousTag('v1.1.0', cwd), 'v1.0.0');
  const commits = readCommits('v1.0.0..v1.1.0', cwd);
  assert.equal(commits.length, 3);
  const notes = renderNotes({ tag: 'v1.1.0', previous: 'v1.0.0', commits, repository: 'sparkzure/PCL-Slash' });
  assert.match(notes, /新增功能/);
  assert.match(notes, /#39C5BB/);
  assert.match(notes, /验证：构建通过/);
  assert.doesNotMatch(notes, /unrelated/);
  assert.match(notes, /compare\/v1.0.0\.\.\.v1.1.0/);
});
test('first-release history, legacy messages, breaking changes and long notes', () => {
  const notes = renderNotes({ tag: 'v1.0.0', previous: null, repository: 'sparkzure/PCL-Slash', commits: [
    { sha: 'a'.repeat(40), message: '旧版更新\n\n历史详情' },
    { sha: 'b'.repeat(40), message: 'fix!: 修改接口\n\nBREAKING CHANGE: 需要迁移' }
  ] });
  assert.match(notes, /其他变更/);
  assert.match(notes, /不兼容变更/);
  assert.match(notes, /历史详情/);
  assert.equal(draftBody(notes), notes);
  const full = (notes + '\n').repeat(3000);
  assert.ok(draftBody(full).length < 100000);
  assert.match(draftBody(full), /CHANGELOG.md/);
});
test('commit policy exempts baseline and ancestors, but rejects later invalid commits', t => {
  const cwd = fixture(t);
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  const commit = message => {
    git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', message]);
    return git(['rev-parse', 'HEAD']);
  };
  git(['init', '--initial-branch=main']);
  const old = commit('历史提交');
  const baseline = commit('历史版本发布');
  const valid = commit('chore(build): 忽略本地工具链');
  assert.deepEqual(readPolicyCommits(old, valid, cwd, baseline).map(item => item.sha), [valid]);
  assert.deepEqual(readPolicyCommits(old, baseline, cwd, baseline), []);
  for (const entry of readPolicyCommits(old, valid, cwd, baseline)) assert.doesNotThrow(() => validateMessage(entry.message));
  const invalid = commit('新增但不规范的提交');
  const entries = readPolicyCommits(old, invalid, cwd, baseline);
  assert.equal(entries.length, 2);
  assert.throws(() => validateMessage(entries[1].message));
  // 已经在 PR 目标分支上的提交不再检查。
  assert.deepEqual(readPolicyCommits(valid, invalid, cwd, baseline).map(item => item.sha), [invalid]);
  assert.throws(() => readPolicyCommits(old, invalid, cwd, '0'.repeat(40)), /无法读取规范基线/);
});
function apiFixture(t, existing, publishDuringUpload = false, tag = 'v1.2.3-beta.1') {
  const directory = fixture(t);
  const archive = `PCL-Slash-${tag}-${releasePlan(tag).configuration}-windows.zip`;
  fs.writeFileSync(path.join(directory, archive), 'zip');
  fs.writeFileSync(path.join(directory, `${archive}.sha256`), 'hash');
  fs.writeFileSync(path.join(directory, 'CHANGELOG.md'), 'complete notes');
  fs.writeFileSync(path.join(directory, 'draft-body.md'), 'generated notes');
  const calls = [];
  const api = Object.fromEntries(['listReleases', 'listReleaseAssets', 'createRelease', 'getRelease', 'deleteReleaseAsset', 'uploadReleaseAsset'].map(method => [method, async args => {
    calls.push([method, args]);
    if (method === 'createRelease') return { data: { id: 1, tag_name: args.tag_name, draft: true, html_url: 'https://example.invalid/draft' } };
    if (method === 'getRelease') return { data: { draft: !publishDuringUpload } };
    return { data: {} };
  }]));
  const github = { rest: { repos: api }, paginate: async method => method === api.listReleases ? (existing ? [existing] : []) : [{ id: 7, name: archive }] };
  return { directory, archive, calls, github, context: { repo: { owner: 'sparkzure', repo: 'PCL-Slash' } }, core: { info() {} }, tag };
}
test('new releases are always drafts with release packages and full changelog', async t => {
  const fixture = apiFixture(t);
  await updateDraft(fixture);
  const create = fixture.calls.find(([method]) => method === 'createRelease')[1];
  assert.equal(create.draft, true);
  assert.equal(create.prerelease, true);
  assert.equal(create.body, 'generated notes');
  assert.deepEqual(fixture.calls.filter(([m]) => m === 'uploadReleaseAsset').map(([, args]) => args.name).sort(), ['CHANGELOG.md', fixture.archive, `${fixture.archive}.sha256`].sort());
});
test('stable releases use normal Release drafts with Release packages', async t => {
  const fixture = apiFixture(t, null, false, 'v1.2.3');
  await updateDraft(fixture);
  const create = fixture.calls.find(([method]) => method === 'createRelease')[1];
  assert.equal(create.draft, true);
  assert.equal(create.prerelease, false);
  assert.ok(fixture.calls.some(([method, args]) => method === 'uploadReleaseAsset' && args.name.endsWith('-Release-windows.zip')));
});
test('reruns preserve administrator-edited draft title/body and replace only matching assets', async t => {
  const fixture = apiFixture(t, { id: 1, tag_name: 'v1.2.3-beta.1', draft: true, name: 'edited', body: 'edited' });
  const result = await updateDraft(fixture);
  assert.equal(result.body, 'edited');
  assert.equal(result.name, 'edited');
  assert.ok(!fixture.calls.some(([m]) => m === 'createRelease'));
  assert.equal(fixture.calls.filter(([m]) => m === 'deleteReleaseAsset').length, 1);
});
test('published releases and drafts published during a rerun are untouched', async t => {
  for (const during of [false, true]) {
    const fixture = apiFixture(t, { id: 1, tag_name: 'v1.2.3-beta.1', draft: during }, during);
    await updateDraft(fixture);
    assert.ok(!fixture.calls.some(([m]) => ['createRelease', 'uploadReleaseAsset', 'deleteReleaseAsset'].includes(m)));
  }
});
test('missing packages fail before creating a draft', async t => {
  const fixture = apiFixture(t);
  fs.unlinkSync(path.join(fixture.directory, fixture.archive));
  await assert.rejects(updateDraft(fixture), /缺少 Snapshot/);
  assert.equal(fixture.calls.length, 0);
});
