#!/usr/bin/env node
// File-side half of install.sh (install.sh does git + GitHub). Every write is idempotent and
// reported as create / update / unchanged; --dry-run reports without writing.
//
//   node install-helper.mjs resolve --root R [--branch B] [--repo O/N] [--allow-path P ...]
//       print shell assignments: BRANCH, REPO, PAGES_URL (from an existing .ai-docs.json), PUBLISH_CMD
//   node install-helper.mjs apply --root R --assets A --branch B --repo O/N --pages-url U
//       --world-readable 0|1 [--allow-path P ...] [--dry-run]
//       write .ai-docs.json, the vendored .claude/skills/ai-docs/, .gitignore, package.json alias,
//       the generated-docs section in AGENTS.md / CLAUDE.md and .github/copilot-instructions.md
//   node install-helper.mjs scan --root R [--allow-path P ...]
//       list tracked .md/.html files outside the allowed doc paths, grouped by directory
import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const SKILL_DIR = '.claude/skills/ai-docs';
const PUBLISH_SCRIPT = `${SKILL_DIR}/scripts/publish.sh`;
const START = '<!-- ai-docs:start -->';
const END = '<!-- ai-docs:end -->';

const DEFAULT_TYPES = [
  { dir: 'plans', label: 'Plans & design docs', holds: 'implementation plans, proposals, design docs, decisions' },
  { dir: 'incidents', label: 'Incidents', holds: 'outage timelines, root causes, postmortems' },
  { dir: 'investigations', label: 'Investigations & troubleshooting', holds: 'bug diagnoses, data checks, log triage, troubleshooting' },
  { dir: 'research', label: 'Research', holds: 'vendor, API and approach comparisons' },
  { dir: 'explainers', label: 'Explainers', holds: 'how a system, feature or change works; testing guides' },
  { dir: 'prototypes', label: 'Prototypes', holds: 'throwaway UI prototypes (`<slug>.prototype.html`)' },
];
// Where new .md/.html files may live on code branches. Entries ending in "/" are path prefixes
// from the repo root; the prose entries describe the built-in rules in isDocAllowed().
const BASELINE_PATHS = [
  'docs/',
  '.claude/',
  '.github/',
  'AGENTS.md/CLAUDE.md files',
  'README/CHANGELOG/LICENSE/CONTRIBUTING files',
  'public/ asset folders',
  'test fixtures',
];

// ---------------------------------------------------------------------------------------------
// args + config
// ---------------------------------------------------------------------------------------------

function parseArgs(argv) {
  const a = { allowPaths: [] };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const v = () => {
      if (i + 1 >= argv.length) throw new Error(`${k} needs a value`);
      return argv[++i];
    };
    if (k === '--root') a.root = v();
    else if (k === '--assets') a.assets = v();
    else if (k === '--branch') a.branch = v();
    else if (k === '--repo') a.repo = v();
    else if (k === '--pages-url') a.pagesUrl = v();
    else if (k === '--world-readable') a.worldReadable = v() === '1';
    else if (k === '--allow-path') a.allowPaths.push(v());
    else if (k === '--dry-run') a.dryRun = true;
    else throw new Error(`unknown arg: ${k}`);
  }
  if (!a.root) throw new Error('--root is required');
  return a;
}

const read = (root, rel) => (existsSync(join(root, rel)) ? readFileSync(join(root, rel), 'utf8') : null);

function existingConfig(root) {
  const text = read(root, '.ai-docs.json');
  if (text === null) return {};
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(`.ai-docs.json is not valid JSON: ${e.message}`);
  }
}

function mergeConfig(root, a) {
  const old = existingConfig(root);
  const allowed = [...(old.allowedDocPaths ?? BASELINE_PATHS)];
  for (const p of a.allowPaths) if (!allowed.includes(p)) allowed.push(p);
  return {
    branch: a.branch || old.branch || 'ai-docs',
    repo: a.repo ?? old.repo ?? '',
    pagesUrl: a.pagesUrl !== undefined ? a.pagesUrl.replace(/\/$/, '') || null : old.pagesUrl ?? null,
    worldReadable: a.worldReadable ?? old.worldReadable ?? false,
    title: old.title || `${(a.repo ?? old.repo ?? '').split('/').pop() || 'AI'} docs`,
    types: Array.isArray(old.types) && old.types.length ? old.types : DEFAULT_TYPES,
    allowedDocPaths: allowed,
    prExplainerDir: old.prExplainerDir ?? 'html-explainers',
  };
}

function publishCmd(root) {
  if (!existsSync(join(root, 'package.json'))) return `bash ${PUBLISH_SCRIPT}`;
  if (existsSync(join(root, 'pnpm-lock.yaml'))) return 'pnpm ai-docs:publish';
  if (existsSync(join(root, 'yarn.lock'))) return 'yarn ai-docs:publish';
  if (existsSync(join(root, 'bun.lockb')) || existsSync(join(root, 'bun.lock'))) return 'bun run ai-docs:publish';
  return 'npm run ai-docs:publish';
}

const sh = (v) => `'${String(v ?? '').replace(/'/g, `'\\''`)}'`;

function resolve(a) {
  const c = mergeConfig(a.root, a);
  console.log(`BRANCH=${sh(c.branch)}`);
  console.log(`REPO=${sh(c.repo)}`);
  console.log(`PAGES_URL=${sh(c.pagesUrl ?? '')}`);
  console.log(`PUBLISH_CMD=${sh(publishCmd(a.root))}`);
}

// ---------------------------------------------------------------------------------------------
// apply
// ---------------------------------------------------------------------------------------------

function makeWriter(root, dryRun) {
  return (rel, content, { mode } = {}) => {
    const before = read(root, rel);
    const verb = before === null ? 'create' : before === content ? 'unchanged' : 'update';
    if (verb !== 'unchanged' && !dryRun) {
      mkdirSync(dirname(join(root, rel)), { recursive: true });
      writeFileSync(join(root, rel), content);
    }
    if (mode && !dryRun && existsSync(join(root, rel))) chmodSync(join(root, rel), mode);
    console.log(`  ${dryRun && verb !== 'unchanged' ? `would ${verb}` : verb.padEnd(9)} ${rel}`);
  };
}

// Replace the marked section, or append it. Returns the new file content.
function upsertSection(text, section) {
  const block = `${START}\n${section.trim()}\n${END}`;
  if (text === null || text.trim() === '') return `${block}\n`;
  const s = text.indexOf(START);
  const e = text.indexOf(END);
  if (s !== -1 && e > s) return text.slice(0, s) + block + text.slice(e + END.length);
  return `${text.replace(/\s*$/, '')}\n\n${block}\n`;
}

const code = (p) => (/\s/.test(p) ? p : `\`${p}\``);
function list(items) {
  const xs = items.map(code);
  return xs.length < 2 ? xs.join('') : `${xs.slice(0, -1).join(', ')} and ${xs.at(-1)}`;
}

function agentSection(c, cmd) {
  const where = c.pagesUrl ? `, served at ${c.pagesUrl}` : '';
  return `## Generated docs

Plans, explainers, HTML reports, incident write-ups, investigation and troubleshooting notes, research and UI prototypes live on the \`${c.branch}\` branch, the team's knowledge base${where}. Write and publish them with the \`ai-docs\` skill (\`${SKILL_DIR}/SKILL.md\`, publish with \`${cmd}\`) without asking. That destination wins over any other skill's output location and over claude.ai Artifacts (make an Artifact only when asked for one).

New \`.html\` and \`.md\` files on code branches belong only in ${list(c.allowedDocPaths)}. Code review flags any other new \`.html\` or \`.md\` file unless the PR description says why it belongs in the repo.`;
}

function copilotSection(c, cmd) {
  return `- Flag every newly added \`.html\` or \`.md\` file outside ${list(c.allowedDocPaths)}, unless the PR description explains why it belongs in the repo. Plans, explainers, reports, incident write-ups, investigation notes, research and prototypes belong on the \`${c.branch}\` branch, published with \`${cmd}\` (see \`${SKILL_DIR}/SKILL.md\`).`;
}

function renderSkill(template, c, cmd) {
  const table = [
    '| type | holds |',
    '| --- | --- |',
    ...c.types.map((t) => `| \`${t.dir}\` | ${t.holds || t.label || ''} |`),
  ].join('\n');
  const audience = c.worldReadable ? 'anyone on the internet' : 'everyone with repo access';
  const where = c.pagesUrl
    ? `served at ${c.pagesUrl} (GitHub Pages, readable by ${audience})`
    : `readable by ${audience} on GitHub (no Pages site)`;
  const note = c.pagesUrl
    ? " HTML links go to Pages and Markdown to GitHub's rendered view; Pages goes live 1–2 minutes after the push."
    : ' Markdown renders on GitHub; HTML shows as source there, so also give the local preview path the script prints.';
  return template
    .replaceAll('__BRANCH__', c.branch)
    .replaceAll('__WHERE__', where)
    .replaceAll('__TYPES_TABLE__', table)
    .replaceAll('__PUBLISH_CMD__', cmd)
    .replaceAll('__PAGES_NOTE__', note)
    .replaceAll('__AUDIENCE__', audience[0].toUpperCase() + audience.slice(1));
}

function sameFile(root, a, b) {
  try {
    return realpathSync(join(root, a)) === realpathSync(join(root, b));
  } catch {
    return false;
  }
}

function applyInstructions(root, write, c, cmd) {
  const section = agentSection(c, cmd);
  const hasAgents = existsSync(join(root, 'AGENTS.md'));
  const claudeRel = existsSync(join(root, 'CLAUDE.md'))
    ? 'CLAUDE.md'
    : existsSync(join(root, '.claude/CLAUDE.md'))
      ? '.claude/CLAUDE.md'
      : null;

  if (!hasAgents && claudeRel) {
    write(claudeRel, upsertSection(read(root, claudeRel), section));
    return;
  }
  // AGENTS.md exists, or neither file does: AGENTS.md holds the rule and CLAUDE.md imports it,
  // because Claude Code loads CLAUDE.md, not AGENTS.md.
  write('AGENTS.md', upsertSection(read(root, 'AGENTS.md'), section));
  const target = claudeRel ?? 'CLAUDE.md';
  if (claudeRel && sameFile(root, 'AGENTS.md', claudeRel)) return;
  const importLine = target === 'CLAUDE.md' ? '@AGENTS.md' : '@../AGENTS.md';
  const text = read(root, target);
  if (text === null) write(target, `${importLine}\n`);
  else if (/^@(\.\.?\/)*AGENTS\.md\s*$/m.test(text)) write(target, text);
  else write(target, `${importLine}\n\n${text}`);
}

function apply(a) {
  if (!a.assets) throw new Error('--assets is required');
  const root = a.root;
  const c = mergeConfig(root, a);
  const cmd = publishCmd(root);
  const write = makeWriter(root, a.dryRun);

  write('.ai-docs.json', `${JSON.stringify(c, null, 2)}\n`);

  const tmpl = readFileSync(join(a.assets, 'ai-docs/SKILL.md.tmpl'), 'utf8');
  write(`${SKILL_DIR}/SKILL.md`, renderSkill(tmpl, c, cmd));
  write(PUBLISH_SCRIPT, readFileSync(join(a.assets, 'ai-docs/scripts/publish.sh'), 'utf8'), { mode: 0o755 });
  write(`${SKILL_DIR}/scripts/ai-docs.mjs`, readFileSync(join(a.assets, 'ai-docs/scripts/ai-docs.mjs'), 'utf8'));

  const gi = read(root, '.gitignore');
  if (gi !== null && /^\/?ai-docs\/?\s*$/m.test(gi)) write('.gitignore', gi);
  else
    write(
      '.gitignore',
      `${gi ? `${gi.replace(/\s*$/, '')}\n\n` : ''}# Generated docs staged for the ${c.branch} branch (ai-docs skill)\n/ai-docs/\n`
    );

  const pkgText = read(root, 'package.json');
  if (pkgText !== null) {
    let pkg;
    try {
      pkg = JSON.parse(pkgText);
    } catch {
      console.log(`  ⚠ package.json is not valid JSON; add "ai-docs:publish": "bash ${PUBLISH_SCRIPT}" by hand`);
    }
    if (pkg) {
      const want = `bash ${PUBLISH_SCRIPT}`;
      if (pkg.scripts?.['ai-docs:publish'] === want) write('package.json', pkgText);
      else {
        pkg.scripts = { ...(pkg.scripts ?? {}), 'ai-docs:publish': want };
        const indent = pkgText.match(/^\{\s*\n([ \t]+)"/)?.[1] ?? '  ';
        write('package.json', `${JSON.stringify(pkg, null, indent)}\n`);
      }
    }
  }

  applyInstructions(root, write, c, cmd);

  const cp = '.github/copilot-instructions.md';
  const cpText = read(root, cp) ?? '# Review instructions\n';
  write(cp, upsertSection(cpText, copilotSection(c, cmd)));
}

// ---------------------------------------------------------------------------------------------
// scan
// ---------------------------------------------------------------------------------------------

const ALWAYS_OK_NAMES = /^(AGENTS|CLAUDE|README|CHANGELOG|CHANGES|HISTORY|LICENSE|LICENCE|CONTRIBUTING|SECURITY|CODE_OF_CONDUCT|SUPPORT)([.-].*)?\.(md|html?)$/i;
const ALWAYS_OK_SEGMENTS = new Set(['public', 'fixtures', '__fixtures__', 'testdata', 'test-fixtures', '__snapshots__', 'node_modules']);

function isDocAllowed(path, prefixes) {
  const parts = path.split('/');
  if (ALWAYS_OK_NAMES.test(parts.at(-1))) return true;
  if (parts.slice(0, -1).some((p) => ALWAYS_OK_SEGMENTS.has(p))) return true;
  return prefixes.some((p) => (p.endsWith('/') ? path.startsWith(p) : path === p));
}

function scan(a) {
  const c = mergeConfig(a.root, a);
  const prefixes = c.allowedDocPaths.filter((p) => !/\s/.test(p));
  const files = execFileSync('git', ['-C', a.root, 'ls-files', '-z', '--', '*.md', '*.html', '*.htm'], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  })
    .split('\0')
    .filter(Boolean);
  const outside = files.filter((f) => !isDocAllowed(f, prefixes));
  console.log(`Allowed doc paths: ${c.allowedDocPaths.join(' | ')}`);
  if (!outside.length) {
    console.log(`No tracked .md/.html files outside the allowed paths (${files.length} checked).`);
    return;
  }
  const byDir = new Map();
  for (const f of outside) {
    const d = f.includes('/') ? f.slice(0, f.lastIndexOf('/') + 1) : './';
    byDir.set(d, [...(byDir.get(d) ?? []), f]);
  }
  console.log(`${outside.length} tracked .md/.html file(s) outside the allowed paths, by directory:`);
  for (const [d, fs] of [...byDir].sort((x, y) => y[1].length - x[1].length || x[0].localeCompare(y[0]))) {
    console.log(`  ${d} (${fs.length})`);
    fs.slice(0, 15).forEach((f) => console.log(`    ${f}`));
    if (fs.length > 15) console.log(`    … ${fs.length - 15} more`);
  }
}

// ---------------------------------------------------------------------------------------------

try {
  const [cmd, ...rest] = process.argv.slice(2);
  const a = parseArgs(rest);
  if (cmd === 'resolve') resolve(a);
  else if (cmd === 'apply') apply(a);
  else if (cmd === 'scan') scan(a);
  else throw new Error('usage: install-helper.mjs resolve|apply|scan --root R ...');
} catch (e) {
  console.error(`install-helper: ${e.message}`);
  process.exit(1);
}
