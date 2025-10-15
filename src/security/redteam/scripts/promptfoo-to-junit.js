import fs from 'fs';
import path from 'path';

const [, , inPath, outPath] = process.argv;
if (!inPath || !outPath) {
  console.error(
    'Usage: node pipelines/scripts/promptfoo-to-junit.js <inputJson> <outputXml>'
  );
  process.exit(2);
}

const text = fs.readFileSync(inPath, 'utf8');
const data = JSON.parse(text);

const esc = (s = '') =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
const trunc = (s, n = 2000) => {
  if (s == null) {
    return '';
  }
  const v = String(s);
  return v.length <= n
    ? v
    : `${v.slice(0, n)}\n... [truncated ${v.length - n} chars]`;
};

let cases = [];
if (Array.isArray(data?.results?.results)) {
  cases = data.results.results;
} else if (Array.isArray(data?.results?.outputs)) {
  cases = data.results.outputs;
} else if (Array.isArray(data?.outputs)) {
  cases = data.outputs;
} else {
  cases = [];
}

let failures = 0;
let errors = 0;

const mkName = (o, idx) => {
  const pluginId = o?.metadata?.pluginId || 'unknown-plugin';
  const strategy = o?.metadata?.strategyId ? ` ${o.metadata.strategyId}` : '';
  const enc = o?.metadata?.encodingType ? ` ${o.metadata.encodingType}` : '';
  const prompt = (
    o?.testCase?.vars?.prompt ||
    o?.vars?.prompt ||
    o?.prompt?.raw ||
    ''
  )
    .toString()
    .replace(/\s+/g, ' ')
    .slice(0, 80)
    .trim();
  return (
    [pluginId, strategy, enc, prompt].filter(Boolean).join(' ').trim() ||
    `case-${idx + 1}`
  );
};

const testcasesXml = cases
  .map((o, idx) => {
    const name = mkName(o, idx);
    const pluginId = (o?.metadata?.pluginId || 'unknown').replace(
      /[^a-zA-Z0-9_.-]/g,
      '-'
    );
    const classname = `promptfoo.redteam.${pluginId}`;
    const time = '0';

    const passed = o?.success === true && o?.gradingResult?.pass !== false;

    if (passed) {
      return `<testcase name="${esc(name)}" classname="${esc(classname)}" time="${time}"/>`;
    }

    const errMsg = o?.error;
    const infra =
      errMsg &&
      /(transport|timeout|network|5\d\d|rate limit|too many requests|ETIMEDOUT|ECONNRESET)/i.test(
        errMsg
      );
    if (infra) {
      errors += 1;
    } else {
      failures += 1;
    }
    const tag = infra ? 'error' : 'failure';
    const msg = trunc(errMsg || 'Assertion failed', 256);

    const bits = [];
    if (o?.gradingResult?.reason)
      bits.push(`Reason:\n${o.gradingResult.reason}`);
    if (o?.response?.output) {
      const outText =
        typeof o.response.output === 'string'
          ? o.response.output
          : JSON.stringify(o.response.output, null, 2);
      bits.push(`Output:\n${trunc(outText, 2000)}`);
    }
    if (errMsg) bits.push(`Error:\n${trunc(errMsg, 2000)}`);
    const body = esc(bits.join('\n\n'));

    return [
      `<testcase name="${esc(name)}" classname="${esc(classname)}" time="${time}">`,
      `<${tag} type="${infra ? 'InfrastructureError' : 'AssertionFailure'}" message="${esc(msg)}">`,
      `${body}`,
      `</${tag}>`,
      `</testcase>`,
    ].join('');
  })
  .join('');

const hasCases = cases.length > 0;
const suiteBody = hasCases
  ? testcasesXml
  : `<testcase name="promptfoo.redteam.placeholder" classname="promptfoo.redteam" time="0"><skipped message="No cases found"/></testcase>`;

const total = hasCases ? cases.length : 1;
const timestamp = new Date().toISOString();

const xml =
  `<?xml version="1.0" encoding="UTF-8"?>` +
  `<testsuite name="promptfoo.redteam" tests="${total}" failures="${failures}" errors="${errors}" time="0" timestamp="${esc(timestamp)}">` +
  `${suiteBody}` +
  `</testsuite>\n`;

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, xml, 'utf8');

console.log(
  `Cases discovered (strict): ${cases.length}, failures=${failures}, errors=${errors}`
);
console.log(`Wrote JUnit: ${outPath}`);
