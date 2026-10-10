#!/usr/bin/env node
// Helpers for publish.sh. Installed and managed by the install-ai-docs skill; settings live in
// .ai-docs.json at the repo root (re-run the installer after editing it).
//   node ai-docs.mjs env                  print the config as shell assignments for publish.sh
//   node ai-docs.mjs scan <file...>       exit 1 and list hits when a file looks like it holds a secret
//   node ai-docs.mjs index <root>         rebuild <root>/index.html for an ai-docs checkout
// The config path comes from $AI_DOCS_CONFIG, else <git toplevel>/.ai-docs.json.
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// ---------------------------------------------------------------------------------------------
// config
// ---------------------------------------------------------------------------------------------

const DEFAULT_TYPES = [
  { dir: 'plans', label: 'Plans & design docs' },
  { dir: 'incidents', label: 'Incidents' },
  { dir: 'investigations', label: 'Investigations & troubleshooting' },
  { dir: 'research', label: 'Research' },
  { dir: 'explainers', label: 'Explainers' },
  { dir: 'prototypes', label: 'Prototypes' },
];

function loadConfig() {
  let path = process.env.AI_DOCS_CONFIG;
  if (!path) {
    try {
      const top = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
      path = join(top, '.ai-docs.json');
    } catch {
      path = '.ai-docs.json';
    }
  }
  const raw = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : {};
  const repo = raw.repo || '';
  return {
    branch: raw.branch || 'ai-docs',
    repo,
    pagesUrl: (raw.pagesUrl || '').replace(/\/$/, ''),
    title: raw.title || `${repo.split('/').pop() || 'AI'} docs`,
    types: Array.isArray(raw.types) && raw.types.length ? raw.types : DEFAULT_TYPES,
    prExplainerDir: raw.prExplainerDir ?? 'html-explainers',
  };
}

const sh = (v) => `'${String(v).replace(/'/g, `'\\''`)}'`;

function env() {
  const c = loadConfig();
  console.log(`AI_BRANCH=${sh(c.branch)}`);
  console.log(`REPO_SLUG=${sh(c.repo)}`);
  console.log(`PAGES_BASE=${sh(c.pagesUrl)}`);
  console.log(`TYPES=(${c.types.map((t) => sh(t.dir)).join(' ')})`);
  return 0;
}

// ---------------------------------------------------------------------------------------------
// scan
// ---------------------------------------------------------------------------------------------

const SECRET_PATTERNS = [
  ['private key', /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ['JWT', /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/],
  ['URL with password', /\b[a-z][a-z0-9+.-]*:\/\/[^/\s:@'"]*:([^/\s@'"]{3,})@/i],
  ['AWS access key', /\b(AKIA|ASIA)[0-9A-Z]{16}\b/],
  ['GitHub token', /\b(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})/],
  ['Slack token', /\bxox[abprs]-[A-Za-z0-9-]{10,}/],
  ['Slack webhook', /hooks\.slack\.com\/services\/T[A-Z0-9]+\/B[A-Z0-9]+\/[A-Za-z0-9]+/],
  ['Stripe key', /\b[sr]k_live_[A-Za-z0-9]{10,}/],
  [
    'API key (sk-/phx_/glc_)',
    /\b(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|phx_[A-Za-z0-9]{20,}|glc_[A-Za-z0-9+/=]{20,})/,
  ],
  ['Google API key', /\bAIza[0-9A-Za-z_-]{35}\b/],
  ['Azure key', /\b(AccountKey|SharedAccessKey)=[A-Za-z0-9+/=]{30,}/],
  ['SAS signature', /[?&]sig=[A-Za-z0-9%+/=]{30,}/],
  [
    'assigned secret',
    /\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?key|auth[_-]?token|client[_-]?secret)["']?\s*[:=]\s*["']?[A-Za-z0-9_\-+/=.]{16,}/i,
  ],
];
// Placeholders that look like credentials but are not: user:<password>@, :***@, :${VAR}@, :%s@.
const PLACEHOLDER = /^(<[^>]*>|\*+|\$\{?[A-Za-z_]+\}?|%s|password|pass|secret|x{3,}|\.\.\.)$/i;

function scan(files) {
  const hits = [];
  for (const file of files) {
    readFileSync(file, 'utf8')
      .split('\n')
      .forEach((line, i) => {
        for (const [name, re] of SECRET_PATTERNS) {
          const m = line.match(re);
          if (!m) continue;
          if (name === 'URL with password' && PLACEHOLDER.test(m[1])) continue;
          const shown = m[0].length > 14 ? `${m[0].slice(0, 10)}…` : m[0];
          hits.push(`${file}:${i + 1}: ${name}: ${shown}`);
        }
      });
  }
  if (!hits.length) return 0;
  console.error(`Secret scan found ${hits.length} possible secret(s):`);
  hits.slice(0, 50).forEach((h) => console.error(`  ${h}`));
  return 1;
}

// ---------------------------------------------------------------------------------------------
// index
// ---------------------------------------------------------------------------------------------

const esc = (s) =>
  String(s ?? '').replace(
    /[&<>"]/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]
  );
const decode = (s) =>
  String(s ?? '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&rsquo;/g, '’')
    .replace(/&mdash;/g, '—')
    .replace(/\s+/g, ' ')
    .trim();
const clip = (s, n = 180) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

// First author and date of each file, from the commit that added it.
function firstAdds(root) {
  let out = '';
  try {
    out = execFileSync(
      'git',
      ['-C', root, 'log', '--diff-filter=A', '--name-only', '--format=@@%an|%as'],
      { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] }
    );
  } catch {
    // No commits yet (fresh bootstrap): no authors to show.
  }
  const map = new Map();
  let cur = null;
  for (const line of out.split('\n')) {
    if (line.startsWith('@@')) {
      const [author, date] = line.slice(2).split('|');
      cur = { author, date };
    } else if (line && cur) {
      map.set(line, cur); // log is newest first, so the last write is the oldest add
    }
  }
  return map;
}

function metaOf(path, text) {
  if (path.endsWith('.html')) {
    const head = text.slice(0, 20000);
    const title = head.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1];
    const desc =
      head.match(/<meta\s+name=["']description["']\s+content=["']([^"']*)["']/i)?.[1] ??
      head.match(/<meta\s+content=["']([^"']*)["']\s+name=["']description["']/i)?.[1];
    return { title: decode(title), description: decode(desc) };
  }
  let body = text;
  const fm = text.match(/^---\n([\s\S]*?)\n---\n/);
  const field = (k) => fm?.[1].match(new RegExp(`^${k}:\\s*["']?(.*?)["']?\\s*$`, 'm'))?.[1];
  if (fm) body = text.slice(fm[0].length);
  const title = field('title') ?? body.match(/^#\s+(.+)$/m)?.[1];
  const para = body
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .find((p) => p && !/^(#|```|[-*|>]|!\[|\d+\.\s)/.test(p));
  return {
    title: decode(title),
    description: decode(field('description') ?? para ?? '').replace(/[`*_]/g, ''),
  };
}

function collect(root, adds, c) {
  const sections = c.types.map(({ dir, label }) => {
    const abs = join(root, dir);
    const items = existsSync(abs)
      ? readdirSync(abs)
          .filter((f) => /\.(html|md)$/.test(f))
          .map((f) => {
            const path = `${dir}/${f}`;
            const { title, description } = metaOf(path, readFileSync(join(abs, f), 'utf8'));
            const date = f.match(/^(\d{4}-\d{2}-\d{2})-/)?.[1] ?? adds.get(path)?.date ?? '';
            const slug = f.replace(/^\d{4}-\d{2}-\d{2}-/, '').replace(/\.(html|md)$/, '');
            return {
              path,
              title: title || slug,
              description,
              date,
              author: adds.get(path)?.author ?? '',
              md: f.endsWith('.md'),
            };
          })
          .sort((a, b) => b.date.localeCompare(a.date) || a.title.localeCompare(b.title))
      : [];
    return { dir, label: label || dir, items };
  });

  // PR explainers (install-pr-explainer): one entry per PR (its newest explainer), plus any
  // non-PR pages in the folder.
  const byPr = new Map();
  const other = [];
  const prDir = c.prExplainerDir ? join(root, c.prExplainerDir) : '';
  if (prDir && existsSync(prDir)) {
    for (const f of readdirSync(prDir).filter((f) => f.endsWith('.html'))) {
      const path = `${c.prExplainerDir}/${f}`;
      const added = adds.get(path) ?? { author: '', date: '' };
      const { title, description } = metaOf(path, readFileSync(join(prDir, f), 'utf8'));
      const pr = f.match(/^(\d+)-[0-9a-f]+-explainer\.html$/)?.[1];
      const item = { path, title: title || f, description, date: added.date, author: added.author, md: false, pr };
      if (!pr) other.push(item);
      else if (!byPr.has(pr) || byPr.get(pr).date <= item.date) byPr.set(pr, item);
    }
  }
  const prItems = [...byPr.values()].sort((a, b) => Number(b.pr) - Number(a.pr));
  other.sort((a, b) => b.date.localeCompare(a.date));
  return { sections, prItems: [...other, ...prItems] };
}

function index(root) {
  const c = loadConfig();
  // Markdown opens in GitHub's rendered view; HTML is served next to this page.
  const urlOf = (path) =>
    path.endsWith('.md') && c.repo ? `https://github.com/${c.repo}/blob/${c.branch}/${path}` : path;
  const renderItem = (it) => {
    const search = `${it.title} ${it.description} ${it.author} ${it.path}`.toLowerCase();
    const meta = [it.pr ? `PR #${it.pr}` : '', it.date, it.author, it.md ? 'Markdown' : '']
      .filter(Boolean)
      .join(' · ');
    return `<li data-s="${esc(search)}"><a href="${esc(urlOf(it.path))}">${esc(it.title)}</a>${
      it.description ? `<p>${esc(clip(it.description))}</p>` : ''
    }<div class="m">${esc(meta)}</div></li>`;
  };

  const { sections, prItems } = collect(root, firstAdds(root), c);
  const total = sections.reduce((n, s) => n + s.items.length, 0);
  const body = sections
    .filter((s) => s.items.length)
    .map(
      (s) =>
        `<section><h2>${esc(s.label)} <span>${s.items.length}</span></h2><ul>${s.items.map(renderItem).join('')}</ul></section>`
    )
    .join('\n');
  const prBlock = prItems.length
    ? `<details id="pr"><summary>PR explainers (${prItems.length})</summary><ul>${prItems.map(renderItem).join('')}</ul></details>`
    : '';
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(c.title)}</title>
<meta name="description" content="Generated plans, explainers, incident write-ups, investigations, research and prototypes.">
<style>
:root { --bg:#f6f5f1; --surface:#fff; --ink:#1c1d1f; --ink-2:#4b4e55; --ink-3:#80838a; --line:#dcd9d0; --accent:#2456d6; color-scheme: light; }
@media (prefers-color-scheme: dark) { :root { --bg:#131416; --surface:#1c1d20; --ink:#ecebe6; --ink-2:#b4b5b9; --ink-3:#85878d; --line:#34363b; --accent:#7c9bff; color-scheme: dark; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
main { max-width: 900px; margin: 0 auto; padding: 32px 16px 64px; }
h1 { font-size: 28px; margin: 0 0 4px; letter-spacing: -0.01em; }
.lede { color: var(--ink-2); margin: 0 0 20px; }
input { width: 100%; padding: 10px 12px; font: inherit; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); color: var(--ink); }
section { margin-top: 28px; }
h2 { font-size: 13px; text-transform: uppercase; letter-spacing: 0.07em; color: var(--ink-3); margin: 0 0 8px; }
h2 span { font-weight: 400; }
ul { list-style: none; margin: 0; padding: 0; background: var(--surface); border: 1px solid var(--line); border-radius: 10px; }
li { padding: 11px 14px; border-bottom: 1px solid var(--line); }
li:last-child { border-bottom: 0; }
li a { color: var(--accent); font-weight: 600; text-decoration: none; }
li a:hover { text-decoration: underline; }
li p { margin: 3px 0 0; color: var(--ink-2); font-size: 14px; }
.m { color: var(--ink-3); font-size: 12.5px; margin-top: 3px; }
details { margin-top: 28px; }
summary { cursor: pointer; font-size: 13px; text-transform: uppercase; letter-spacing: 0.07em; color: var(--ink-3); font-weight: 700; margin-bottom: 8px; }
.empty { color: var(--ink-3); margin-top: 24px; display: none; }
</style>
</head>
<body>
<main>
<h1>${esc(c.title)}</h1>
<p class="lede">${total} generated docs${prItems.length ? ` and ${prItems.length} PR explainers` : ''}. Rebuilt on every publish by the <code>ai-docs</code> skill.</p>
<input id="q" type="search" placeholder="Search titles, descriptions, authors…" autofocus>
${body}
${prBlock}
<p class="empty" id="empty">No matches.</p>
</main>
<script>
const q = document.getElementById('q'), pr = document.getElementById('pr'), empty = document.getElementById('empty');
q.addEventListener('input', () => {
  const t = q.value.trim().toLowerCase();
  let shown = 0;
  document.querySelectorAll('li[data-s]').forEach(li => {
    const ok = !t || li.dataset.s.includes(t);
    li.hidden = !ok;
    if (ok) shown++;
  });
  document.querySelectorAll('section').forEach(s => { s.hidden = !s.querySelector('li:not([hidden])'); });
  if (t && pr) pr.open = !!pr.querySelector('li:not([hidden])');
  empty.style.display = shown ? 'none' : 'block';
});
</script>
</body>
</html>
`;
  writeFileSync(join(root, 'index.html'), html);
  console.error(`index.html: ${total} docs, ${prItems.length} PR explainers`);
  return 0;
}

const [cmd, ...args] = process.argv.slice(2);
if (cmd === 'env' && !args.length) process.exit(env());
if (cmd === 'scan' && args.length) process.exit(scan(args));
if (cmd === 'index' && args.length === 1) process.exit(index(args[0]));
console.error('usage: ai-docs.mjs env | scan <file...> | index <root>');
process.exit(2);
