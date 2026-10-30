const { execFileSync } = require('node:child_process');
const { writeFileSync, mkdirSync } = require('node:fs');
const { parseSubject, readCommits } = require('./commit-policy.cjs');
const tagPattern = /^v\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$/;
function validateTag(tag) {
  if (!tagPattern.test(tag)) throw new Error(`版本标签无效：${tag}；请使用 v1.2.3 或 v1.2.3.4，可附加 -beta.1 等预发布后缀。`);
  return tag;
}
function previousTag(tag, cwd) {
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  const stable = !tag.split('+')[0].includes('-');
  const candidates = git(['tag', '--merged', tag]).split('\n').filter(value => value !== tag && tagPattern.test(value) && (!stable || !value.split('+')[0].includes('-')));
  if (!candidates.length) return null;
  try { return git(['describe', '--tags', '--abbrev=0', ...candidates.map(value => `--match=${value}`), `${tag}^`]); }
  catch { return null; } // 首个版本或根提交没有更早的版本标签。
}
const headings = { feat: '新增功能', fix: '问题修复', perf: '性能优化', refactor: '代码重构', docs: '文档', style: '代码格式', test: '测试', build: '构建', ci: '持续集成', chore: '维护', revert: '回退', legacy: '其他变更' };
function escape(text) { return text.replace(/[\\`*_[\]<>]/g, value => `\\${value}`); }
function renderNotes({ tag, previous, commits, repository }) {
  const groups = new Map();
  for (const { sha, message } of commits) {
    const [subject, ...body] = message.split(/\r?\n/);
    const parsed = parseSubject(subject);
    const breaking = parsed?.breaking || /^BREAKING[ -]CHANGE:/m.test(message);
    const key = breaking ? 'breaking' : parsed?.type || 'legacy';
    const description = parsed ? `${parsed.scope ? `[${parsed.scope}] ` : ''}${parsed.description}` : subject;
    const details = body.join('\n').trim();
    const entry = `- ${escape(description)} ([${sha.slice(0, 7)}](https://github.com/${repository}/commit/${sha}))` +
      (details ? '\n\n' + details.split('\n').map(line => `    ${line}`).join('\n') : '');
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(entry);
  }
  const sections = ['> 此内容由提交记录自动整理，请仓库管理员核对并编辑后手动发布。', '', `# ${tag}`, '', previous ? `变更范围：${previous} → ${tag}` : '首个版本：包含此标签之前的全部非合并提交。'];
  for (const key of ['breaking', ...Object.keys(headings)]) {
    if (groups.has(key)) sections.push('', `## ${key === 'breaking' ? '不兼容变更' : headings[key]}`, '', groups.get(key).join('\n\n'));
  }
  if (!commits.length) sections.push('', '此范围内没有非合并提交。');
  const url = previous ? `https://github.com/${repository}/compare/${encodeURIComponent(previous)}...${encodeURIComponent(tag)}` : `https://github.com/${repository}/commits/${encodeURIComponent(tag)}`;
  sections.push('', `[查看完整提交记录](${url})`, '');
  return sections.join('\n');
}
function draftBody(notes) {
  if (notes.length <= 100000) return notes;
  return notes.slice(0, 99000).replace(/\n[^\n]*$/, '') + '\n\n历史记录较长，完整内容见附件 CHANGELOG.md。\n';
}
if (require.main === module) {
  const tag = validateTag(process.env.RELEASE_TAG || process.env.GITHUB_REF_NAME || '');
  if (process.argv[2] !== 'validate-tag') {
    const previous = previousTag(tag);
    const notes = renderNotes({ tag, previous, commits: readCommits(previous ? `${previous}..${tag}` : tag), repository: process.env.GITHUB_REPOSITORY });
    mkdirSync('release-assets', { recursive: true });
    writeFileSync('release-assets/CHANGELOG.md', notes);
    writeFileSync('release-assets/draft-body.md', draftBody(notes));
  }
}
module.exports = { validateTag, previousTag, renderNotes, draftBody };
