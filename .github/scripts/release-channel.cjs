const fs = require('node:fs');
const { validateTag } = require('./release-notes.cjs');

function releasePlan(tag) {
  validateTag(tag);
  const version = tag.slice(1);
  const numeric = version.split(/[+-]/)[0].split('.').map(Number);
  if (numeric.some(part => part > 65534)) throw new Error('程序集版本的每一段不能超过 65534');
  while (numeric.length < 4) numeric.push(0);
  const prerelease = version.split('+')[0].includes('-');
  return { tag, version, assemblyVersion: numeric.join('.'), prerelease,
    configuration: prerelease ? 'Snapshot' : 'Release', channel: prerelease ? 'snapshot' : 'release' };
}
function buildPlan(refType, refName) {
  if (refType !== 'tag') return { matrix: { configuration: ['Debug', 'Snapshot', 'Release'] }, configuration: '', channel: '' };
  const release = releasePlan(refName);
  return { ...release, matrix: { configuration: [release.configuration] } };
}
if (require.main === module) {
  const plan = buildPlan(process.env.GITHUB_REF_TYPE, process.env.GITHUB_REF_NAME);
  if (!process.env.GITHUB_OUTPUT) throw new Error('Missing GITHUB_OUTPUT');
  for (const [key, value] of Object.entries({ matrix: JSON.stringify(plan.matrix), configuration: plan.configuration, channel: plan.channel })) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
  }
}
module.exports = { releasePlan, buildPlan };
