const test = require('node:test');
const assert = require('node:assert/strict');
const { prepare, run, BASE, ASSEMBLY, MANIFEST } = require('./release-bot.cjs');
const base = `Public Const VersionBaseName As String = "2.14.0.0"
#If RELEASE Then
    Public Const VersionCode As Integer = 411 '正式版
#Else
    Public Const VersionCode As Integer = 412 '快照版
#End If
`;
const assembly = '<Assembly: AssemblyVersion("2.14.0.0")>\n<Assembly: AssemblyFileVersion("2.14.0.0")>\n';

test('bot increments the global maximum, preserving the other channel and syncing versions', () => {
  const snapshot = prepare(base, assembly, 'snapshot', '2.14.1.0-beta.1');
  assert.equal(snapshot.code, 413);
  assert.match(snapshot.files[BASE], /411 '正式版/);
  assert.match(snapshot.files[BASE], /413 '快照版/);
  assert.match(snapshot.files[ASSEMBLY], /AssemblyInformationalVersion\("2.14.1.0-beta.1"\)/);
  const release = prepare(snapshot.files[BASE], snapshot.files[ASSEMBLY], 'release', '2.14.1.0');
  assert.equal(release.code, 414);
  assert.match(release.files[BASE], /414 '正式版/);
  assert.match(release.files[BASE], /413 '快照版/);
  assert.equal((release.files[ASSEMBLY].match(/AssemblyInformationalVersion/g) || []).length, 1);
  assert.equal(prepare(base.replaceAll('\n', '\r\n'), assembly, 'release', '2.14.1').code, 413);
});

test('bot rejects mismatched channels, malformed input, unknown source layout and overflow', () => {
  for (const [channel, version] of [['release', '2.14.1-beta.1'], ['snapshot', '2.14.1'], ['evil', '2.14.1'],
    ['release', 'v2.14.1'], ['release', '2.14.1\n'], ['release', '2.14.1;echo'], ['release', '2.14.99999']]) {
    assert.throws(() => prepare(base, assembly, channel, version));
  }
  assert.throws(() => prepare(base.replace('#If RELEASE Then', '#If OTHER Then'), assembly, 'release', '2.14.1'));
  assert.throws(() => prepare(base.replace('412', '2147483647'), assembly, 'release', '2.14.1'), /Integer/);
});

function fixture(eventName = 'workflow_dispatch') {
  const result = prepare(base, assembly, 'snapshot', '2.14.1.0-snapshot.1');
  const repository = { default_branch: 'main', full_name: 'sparkzure/PCL-Slash' };
  const pr = { number: 5, merged: true, base: { ref: 'main' },
    head: { ref: `codex/release/${result.tag}`, repo: { full_name: repository.full_name } },
    user: { login: 'release-bot[bot]' }, merge_commit_sha: 'merged', html_url: 'https://example.invalid/pr/5' };
  const state = { calls: [], refs: {}, pulls: [], pr, files: Object.keys(result.files).map(filename => ({ filename, status: 'modified' })),
    contents: { before: { [BASE]: base, [ASSEMBLY]: assembly }, merged: { ...result.files } } };
  const missing = () => { throw Object.assign(new Error('not found'), { status: 404 }); };
  const repos = {
    getBranch: async () => ({ data: { commit: { sha: 'before' } } }),
    getContent: async ({ path, ref }) => {
      const content = state.contents[ref]?.[path];
      if (content === undefined) return missing();
      return { data: { type: 'file', encoding: 'base64', content: Buffer.from(content).toString('base64') } };
    }
  };
  const git = {
    getRef: async ({ ref }) => state.refs[ref] ? { data: state.refs[ref] } : missing(),
    getCommit: async ({ commit_sha }) => ({ data: { tree: { sha: commit_sha === 'orphan' ? 'new-tree' : 'tree' }, parents: [{ sha: 'before' }] } }),
    createTree: async args => { state.calls.push(['tree', args]); return { data: { sha: 'new-tree' } }; },
    createCommit: async args => { state.calls.push(['commit', args]); return { data: { sha: 'new-commit' } }; },
    createRef: async args => { state.calls.push(['ref', args]); return { data: {} }; }
  };
  const pulls = {
    list() {}, listFiles() {}, get: async () => ({ data: state.pr }),
    create: async args => { state.calls.push(['pr', args]); return { data: pr }; }
  };
  const github = { rest: { repos, git, pulls }, paginate: async method => method === pulls.list ? state.pulls : state.files };
  const summary = { addRaw() { return this; }, async write() {} };
  const args = { github, context: { repo: { owner: 'sparkzure', repo: 'PCL-Slash' }, eventName,
    ref: 'refs/heads/main', payload: { repository, pull_request: { number: 5 } } },
    core: { info() {}, summary }, appSlug: 'release-bot', channel: 'snapshot', version: '2.14.1.0-snapshot.1' };
  return { state, args, result };
}

test('dispatch creates exactly the version files and a reviewable PR, without a tag', async () => {
  const { state, args, result } = fixture();
  await run(args);
  assert.deepEqual(state.calls.map(([method]) => method), ['tree', 'commit', 'ref', 'pr']);
  assert.deepEqual(state.calls[0][1].tree.map(item => item.path).sort(), Object.keys(result.files).sort());
  assert.equal(state.calls[2][1].ref, `refs/heads/codex/release/${result.tag}`);
  assert.match(state.calls[3][1].title, /^chore\(release\): /);
});

test('dispatch reuses an existing same-version bot PR and blocks competing versions', async () => {
  const { state, args } = fixture();
  state.pulls = [state.pr];
  await run(args);
  assert.equal(state.calls.length, 0);
  state.pr.head.ref = 'codex/release/v2.14.2';
  await assert.rejects(run(args), /已有待合并/);
});

test('dispatch recovers a branch left behind by a failed PR creation without overwriting it', async () => {
  const { state, args, result } = fixture();
  state.refs[`heads/codex/release/${result.tag}`] = { object: { sha: 'orphan' } };
  await run(args);
  assert.deepEqual(state.calls.map(([method]) => method), ['tree', 'pr']);
});

test('dispatch rejects non-default branch, existing tag/branch and an untagged prior release', async () => {
  for (const kind of ['branch', 'tag', 'head', 'untagged']) {
    const { state, args, result } = fixture();
    if (kind === 'branch') args.context.ref = 'refs/heads/other';
    if (kind === 'tag') state.refs[`tags/${result.tag}`] = {};
    if (kind === 'head') state.refs[`heads/codex/release/${result.tag}`] = { object: { sha: 'unrelated' } };
    if (kind === 'untagged') state.contents.before[MANIFEST] = JSON.stringify({ tag: 'v2.14.0' });
    await assert.rejects(run(args));
    assert.ok(!state.calls.some(([method]) => ['ref', 'commit', 'pr'].includes(method)));
  }
});

test('merged bot PR tags the exact merge commit and reruns are idempotent', async () => {
  const { state, args, result } = fixture('pull_request_target');
  await run(args);
  assert.deepEqual(state.calls.map(([m, a]) => [m, a.ref, a.sha]), [['ref', `refs/tags/${result.tag}`, 'merged']]);
  state.calls.length = 0;
  state.refs[`tags/${result.tag}`] = { object: { type: 'commit', sha: 'merged' } };
  await run(args);
  assert.equal(state.calls.length, 0);
  state.refs[`tags/${result.tag}`].object.sha = 'different';
  await assert.rejects(run(args), /拒绝覆盖/);
});

test('tagging rejects foreign authors/repos, extra files, stale codes and modified version data', async () => {
  const changes = [
    s => { s.pr.user.login = 'human'; },
    s => { s.pr.head.repo.full_name = 'someone/fork'; },
    s => { s.pr.merged = false; },
    s => { s.pr.base.ref = 'other'; },
    s => { s.files.push({ filename: 'unexpected', status: 'added' }); },
    s => { s.contents.before[BASE] = base.replace('412', '413'); },
    s => { s.contents.merged[ASSEMBLY] += 'unexpected edit'; },
    s => { s.contents.merged[MANIFEST] = s.contents.merged[MANIFEST].replace('413', '999'); }
  ];
  for (const change of changes) {
    const { state, args } = fixture('pull_request_target');
    change(state);
    await assert.rejects(run(args));
    assert.equal(state.calls.length, 0);
  }
});
