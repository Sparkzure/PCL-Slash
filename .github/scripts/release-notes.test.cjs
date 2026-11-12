const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { previousTag, readRange, collectCommits, renderNotes, generateNotes } = require('./release-notes.cjs');
const feedback = require('./pr-feedback.cjs');
const commit = (sha, message = `chore: ${sha}`, extra = {}) => ({ sha, commit: { message, author: { name: 'Lecyn', email: 'test@example.invalid' } },
  author: { login: 'lecyn' }, parents: [{ sha: 'parent' }], ...extra });

test('beta starts at the previous beta; snapshot starts at any previous version; stable ignores prereleases', async t => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'pcl-notes-'));
  t.after(() => {
    assert.equal(path.dirname(cwd), os.tmpdir());
    assert.ok(path.basename(cwd).startsWith('pcl-notes-'));
    fs.rmSync(cwd, { recursive: true, force: true });
  });
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  git(['init', '--initial-branch=main']);
  git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', 'chore: baseline']);
  const baseline = git(['rev-parse', 'HEAD']);
  const shas = [];
  for (const tag of ['v1.0.0', 'v1.1.0-snapshot.1', 'v1.1.0-beta.1', 'v1.1.0', 'v1.2.0-snapshot.1', 'v1.2.0-beta.1', 'v1.2.0-snapshot.2', 'v1.2.0']) {
    git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', `chore: ${tag}`]);
    shas.push(git(['rev-parse', 'HEAD']));
    git(['tag', tag]);
  }
  assert.equal(previousTag('v1.1.0-beta.1', cwd), null);
  assert.equal(previousTag('v1.2.0-beta.1', cwd), 'v1.1.0-beta.1');
  assert.equal(previousTag('v1.2.0-snapshot.1', cwd), 'v1.1.0');
  assert.equal(previousTag('v1.2.0-snapshot.2', cwd), 'v1.2.0-beta.1');
  assert.equal(previousTag('v1.2.0', cwd), 'v1.1.0');
  assert.deepEqual(readRange('v1.2.0-beta.1', 'v1.1.0-beta.1', cwd, baseline), shas.slice(3, 6));
  assert.deepEqual(readRange('v1.1.0-beta.1', null, cwd, baseline), shas.slice(0, 3));
  const calls = [];
  const github = { rest: { repos: {
    async compareCommitsWithBasehead(args) { calls.push(args); return { data: { commits: shas.slice(2, 6).reverse().map(sha => commit(sha)) } }; },
    async listCommits(args) { calls.push(args); return { data: [commit(shas[0], 'feat: initial', { parents: [] })] }; }
  } } };
  const directory = path.join(cwd, 'assets');
  await generateNotes({ github, context: { repo: { owner: 'Sparkzure', repo: 'PCL-Slash' } }, core: { info() {} },
    tag: 'v1.2.0-beta.1', cwd, directory, baseline });
  const notes = fs.readFileSync(path.join(directory, 'draft-body.md'), 'utf8');
  assert.ok(!notes.includes(shas[2]));
  assert.ok(notes.includes(shas[3]) && notes.includes(shas[5]));
  assert.ok(notes.indexOf(shas[3]) < notes.indexOf(shas[5]));
  assert.equal(notes, fs.readFileSync(path.join(directory, 'CHANGELOG.md'), 'utf8'));
  assert.equal(calls[0].per_page, 100);
  assert.equal(calls[0].basehead, 'v1.1.0-beta.1...v1.2.0-beta.1');
  await generateNotes({ github, context: { repo: { owner: 'Sparkzure', repo: 'PCL-Slash' } }, core: { info() {} },
    tag: 'v1.0.0', cwd, directory, baseline });
  assert.equal(calls[1].sha, 'v1.0.0');
  assert.match(fs.readFileSync(path.join(directory, 'CHANGELOG.md'), 'utf8'), /## 新增功能/);
});

test('release ranges exclude the baseline and all its ancestors, including merged branches', async t => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'pcl-notes-'));
  t.after(() => {
    assert.equal(path.dirname(cwd), os.tmpdir());
    assert.ok(path.basename(cwd).startsWith('pcl-notes-'));
    fs.rmSync(cwd, { recursive: true, force: true });
  });
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  const commit = message => {
    git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', message]);
    return git(['rev-parse', 'HEAD']);
  };
  git(['init', '--initial-branch=main']);
  const root = commit('历史提交');
  git(['tag', 'v1.0.0']);
  git(['checkout', '-b', 'legacy']);
  commit('旧分支提交');
  git(['checkout', 'main']);
  commit('基线前的主线提交');
  git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'merge', '--no-ff', 'legacy', '-m', '历史合并']);
  const baseline = git(['rev-parse', 'HEAD']);
  const current = commit('feat: 基线后的新功能');
  git(['tag', 'v1.1.0']);
  assert.deepEqual(readRange('v1.1.0', null, cwd, baseline), [current]);
  assert.deepEqual(readRange('v1.1.0', 'v1.0.0', cwd, baseline), [current]);
  assert.deepEqual(readRange(baseline, root, cwd, baseline), []);
  assert.deepEqual(readRange(root, null, cwd, baseline), []);
  assert.throws(() => readRange('v1.1.0', null, cwd, '0'.repeat(40)), /无法读取修改日志基线/);
  const directory = path.join(cwd, 'assets');
  // 完全位于基线之前的版本不访问 GitHub，也不会把旧记录写入附件。
  await generateNotes({ github: {}, context: { repo: { owner: 'o', repo: 'r' } }, core: { info() {} },
    tag: 'v1.0.0', cwd, directory, baseline });
  assert.equal(fs.readFileSync(path.join(directory, 'CHANGELOG.md'), 'utf8'), '此范围内没有可记录的提交。\n');
});

test('includes direct, squash and rebased commits once, skipping merges and out-of-range commits', async () => {
  const entries = [commit('rebase'), commit('merge', 'Merge branch', { parents: [{ sha: 'a' }, { sha: 'b' }] }),
    commit('squash'), commit('direct'), commit('direct'), commit('old'), commit('future')];
  const github = { rest: { repos: { async compareCommitsWithBasehead() { return { data: { commits: entries } }; } } } };
  const result = await collectCommits({ github, owner: 'sparkzure', repo: 'PCL-Slash', tag: 'v1.1.0', previous: 'v1.0.0',
    commits: ['merge', 'direct', 'squash', 'rebase', 'direct'] });
  assert.deepEqual(result.map(entry => entry.sha), ['direct', 'squash', 'rebase']);
});

test('reads more than 250 commits for both comparisons and first releases, preserving local order', async () => {
  const commits = Array.from({ length: 305 }, (_, i) => i.toString(16).padStart(40, '0'));
  for (const previous of [null, 'v1.0.0']) {
    const calls = [];
    const page = args => {
      calls.push(args);
      return [...commits].reverse().slice((args.page - 1) * args.per_page, args.page * args.per_page).map(sha => commit(sha));
    };
    const github = { rest: { repos: {
      async compareCommitsWithBasehead(args) { return { data: { commits: page(args) } }; },
      async listCommits(args) { return { data: page(args) }; }
    } } };
    const result = await collectCommits({ github, owner: 'o', repo: 'r', tag: 'v1.1.0', previous, commits });
    assert.deepEqual(result.map(entry => entry.sha), commits);
    assert.deepEqual(calls.map(args => args.page), [1, 2, 3, 4]);
    assert.ok(calls.every(args => args.per_page === 100));
  }
});

test('continues past pages containing only historical commits excluded by the baseline', async () => {
  const history = Array.from({ length: 301 }, (_, i) => commit(`old-${i}`));
  for (const previous of [null, 'v1.0.0']) {
    const calls = [];
    const page = args => {
      calls.push(args.page);
      return [...history, commit('new')].slice((args.page - 1) * 100, args.page * 100);
    };
    const github = { rest: { repos: {
      async compareCommitsWithBasehead(args) { return { data: { commits: page(args) } }; },
      async listCommits(args) { return { data: page(args) }; }
    } } };
    const result = await collectCommits({ github, owner: 'o', repo: 'r', tag: 'v1.1.0', previous, commits: ['new'] });
    assert.deepEqual(result.map(entry => entry.sha), ['new']);
    assert.deepEqual(calls, [1, 2, 3, 4]);
  }
});

test('empty ranges avoid API calls; missing metadata and API failures stop generation', async () => {
  const args = { owner: 'o', repo: 'r', tag: 'v1.1.0', previous: 'v1.0.0' };
  assert.deepEqual(await collectCommits({ ...args, commits: [] }), []);
  const github = { rest: { repos: { async compareCommitsWithBasehead() { return { data: { commits: [commit('other')] } }; } } } };
  await assert.rejects(collectCommits({ ...args, github, commits: ['missing'] }), /缺少 1 个提交/);
  github.rest.repos.compareCommitsWithBasehead = async () => { throw new Error('API failure'); };
  await assert.rejects(collectCommits({ ...args, github, commits: ['a'] }), /API failure/);
});

test('groups all conventional types and legacy subjects, prioritizing breaking markers and footers', () => {
  const types = ['feat', 'fix', 'perf', 'refactor', 'docs', 'style', 'test', 'build', 'ci', 'chore', 'revert'];
  const notes = renderNotes({ repository: 'o/r', commits: [
    ...types.map(type => commit(type, `${type}(scope): ${type}`)),
    commit('legacy', '历史格式的提交'), commit('bang', 'feat(api)!: 删除旧接口'),
    commit('footer', 'refactor: 调整接口\n\nBREAKING CHANGE: 需要修改配置。'),
    commit('hyphen', 'fix: 调整参数\r\n\r\nBREAKING-CHANGE: 旧参数已删除。')
  ] });
  assert.deepEqual([...notes.matchAll(/^## (.+)$/gm)].map(match => match[1]),
    ['破坏性变更', '新增功能', '问题修复', '性能优化', '代码重构', '文档', '代码风格', '测试', '构建', '持续集成', '维护', '回退', '其他']);
  const breaking = notes.split('## 新增功能')[0];
  for (const sha of ['bang', 'footer', 'hyphen']) assert.ok(breaking.includes(`/commit/${sha}`));
  assert.equal((notes.match(/\/commit\//g) || []).length, types.length + 4);
  assert.doesNotMatch(notes, /需要修改配置|旧参数已删除/);
});

test('PR title feedback creates once, updates on correction and never edits human comments', async () => {
  const comments = [{ id: 1, user: { login: 'human' }, body: '<!-- pcl-slash-pr-title -->' }];
  const writes = [];
  const failures = [];
  const github = { paginate: async () => comments, rest: { issues: {
    listComments() {},
    async createComment(args) { writes.push(['create', args]); comments.push({ id: 2, user: { login: 'github-actions[bot]' }, body: args.body }); },
    async updateComment(args) { writes.push(['update', args]); comments[1].body = args.body; }
  } } };
  const context = { repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { number: 4, title: '标题不规范' } } };
  const args = { github, context, core: { setFailed(message) { failures.push(message); } } };
  await feedback(args);
  await feedback(args);
  assert.equal(writes.length, 1);
  assert.equal(failures.length, 2);
  context.payload.pull_request.title = 'feat(theme): 新增主题';
  await feedback(args);
  await feedback(args);
  assert.equal(writes.length, 2);
  assert.equal(writes[1][1].comment_id, 2);
  assert.match(writes[1][1].body, /已符合规范/);
  comments.splice(1);
  await feedback(args);
  assert.equal(writes.length, 2);
});
