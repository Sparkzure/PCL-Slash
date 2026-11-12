const fs = require('node:fs');
const path = require('node:path');
const { releasePlan } = require('./release-channel.cjs');

module.exports = async function updateDraft({ github, context, core, directory = 'release-assets', tag = process.env.RELEASE_TAG }) {
  const plan = releasePlan(tag);
  const { owner, repo } = context.repo;
  const releases = await github.paginate(github.rest.repos.listReleases, { owner, repo, per_page: 100 });
  let release = releases.find(item => item.tag_name === tag);
  if (release && !release.draft) {
    core.info(`${tag} 已发布，跳过所有修改。`);
    return release;
  }
  const archive = `PCL-Slash-${tag}-${plan.configuration}-windows.zip`;
  const files = [archive, `${archive}.sha256`, 'CHANGELOG.md'];
  if (files.some(name => !fs.existsSync(path.join(directory, name)))) throw new Error(`缺少 ${plan.configuration} 安装压缩包、校验文件或变更记录，拒绝创建空草稿。`);
  if (!release) {
    ({ data: release } = await github.rest.repos.createRelease({ owner, repo, tag_name: tag,
      name: `PCL-Slash ${tag}`, body: fs.readFileSync(path.join(directory, 'draft-body.md'), 'utf8'),
      draft: true, prerelease: plan.prerelease }));
  }
  // 重跑只更新附件，管理员编辑过的标题和正文始终保留。
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { owner, repo, release_id: release.id, per_page: 100 });
  for (const name of files) {
    // 管理员可能在上传过程中发布草稿；每次写入前重新检查。
    const { data: current } = await github.rest.repos.getRelease({ owner, repo, release_id: release.id });
    if (!current.draft) { core.info('版本已发布，停止上传。'); return current; }
    const existing = assets.find(item => item.name === name);
    if (existing) await github.rest.repos.deleteReleaseAsset({ owner, repo, asset_id: existing.id });
    await github.rest.repos.uploadReleaseAsset({ owner, repo, release_id: release.id, name,
      data: fs.readFileSync(path.join(directory, name)), headers: { 'content-type': 'application/octet-stream' } });
  }
  core.info(`Release 草稿已准备：${release.html_url}`);
  return release;
};
