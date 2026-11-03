const { execFileSync } = require('node:child_process');
const { writeFileSync, mkdirSync } = require('node:fs');
const tagPattern = /^v\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$/;
function validateTag(tag) {
  if (!tagPattern.test(tag)) throw new Error(`版本标签无效：${tag}；请使用 v1.2.3 或 v1.2.3.4，可附加 -beta.1 等预发布后缀。`);
  return tag;
}
function previousTag(tag, cwd) {
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  const channel = tagChannel(tag);
  const candidates = git(['tag', '--merged', tag]).split('\n').filter(value => value !== tag && tagPattern.test(value) &&
    (channel === 'release' ? tagChannel(value) === 'release' : channel === 'beta' ? tagChannel(value) === 'beta' : true));
  if (!candidates.length) return null;
  try { return git(['describe', '--tags', '--abbrev=0', ...candidates.map(value => `--match=${value}`), `${tag}^`]); }
  catch { return null; } // 首个版本或根提交没有更早的版本标签。
}
function tagChannel(tag) {
  return tag.split('+')[0].match(/-([0-9A-Za-z]+)/)?.[1].toLowerCase() || 'release';
}
function readRange(tag, previous, cwd) {
  return execFileSync('git', ['rev-list', '--reverse', previous ? `${previous}..${tag}` : tag, '--'],
    { cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }).trim().split('\n').filter(Boolean);
}
async function collectPullRequests({ github, owner, repo, commits }) {
  const included = new Set(commits);
  const pulls = new Map();
  // 合并结果 SHA 同时覆盖 merge、squash 和 rebase，分页读取避免逐 commit 请求。
  const closed = await github.paginate(github.rest.pulls.list,
    { owner, repo, state: 'closed', sort: 'created', direction: 'asc', per_page: 100 });
  for (const pr of closed) {
    if (pr.merged_at && included.has(pr.merge_commit_sha) &&
        pr.base.repo.full_name.toLowerCase() === `${owner}/${repo}`.toLowerCase()) pulls.set(pr.number, pr);
  }
  const order = new Map(commits.map((sha, index) => [sha, index]));
  return [...pulls.values()].sort((a, b) => order.get(a.merge_commit_sha) - order.get(b.merge_commit_sha) || a.number - b.number);
}
function escape(text) { return text.replace(/[\r\n]+/g, ' ').replace(/[\\`*_[\]<>~!]/g, value => `\\${value}`); }
function renderNotes({ pulls, repository }) {
  if (!pulls.length) return '此范围内没有已合并的 PR。\n';
  return pulls.map(pr => `- ${escape(pr.title)} ([#${pr.number}](https://github.com/${repository}/pull/${pr.number}))` +
    (pr.user?.login ? ` by [@${escape(pr.user.login)}](https://github.com/${pr.user.login.endsWith('[bot]')
      ? `apps/${encodeURIComponent(pr.user.login.slice(0, -5))}` : encodeURIComponent(pr.user.login)})` : '（提出者账号已删除）')).join('\n') + '\n';
}
function draftBody(notes) {
  if (notes.length <= 100000) return notes;
  return notes.slice(0, 99000).replace(/\n[^\n]*$/, '') + '\n\n历史记录较长，完整内容见附件 CHANGELOG.md。\n';
}
async function generateNotes({ github, context, core, tag = process.env.RELEASE_TAG, cwd, directory = 'release-assets' }) {
  validateTag(tag);
  const previous = previousTag(tag, cwd);
  const { owner, repo } = context.repo;
  const pulls = await collectPullRequests({ github, owner, repo, commits: readRange(tag, previous, cwd) });
  const notes = renderNotes({ pulls, repository: `${owner}/${repo}` });
  mkdirSync(directory, { recursive: true });
  const { join } = require('node:path');
  writeFileSync(join(directory, 'CHANGELOG.md'), notes);
  writeFileSync(join(directory, 'draft-body.md'), draftBody(notes));
  core.info(`发行说明范围：${previous || '全部历史'} → ${tag}，共 ${pulls.length} 个已合并 PR。`);
}
if (require.main === module) {
  validateTag(process.env.RELEASE_TAG || process.env.GITHUB_REF_NAME || '');
  if (process.argv[2] !== 'validate-tag') throw new Error('请通过 actions/github-script 调用 generateNotes，以读取 PR 元数据。');
}
module.exports = { validateTag, previousTag, tagChannel, readRange, collectPullRequests, renderNotes, draftBody, generateNotes };
