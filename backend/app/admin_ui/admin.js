/* SQUIZ admin dashboard. Vanilla JS, no inline scripts, every piece of data is rendered with textContent (never innerHTML).
   This UI is a convenience: every action is authorised again by the server (role checked on every /admin/* request). */
(function () {
  'use strict';
  const API = '';                                   // same origin as the backend
  const app = document.getElementById('app');
  const S = { access: null, refresh: null, user: null, grades: [], subjects: [] };

  /* ---------- helpers ---------- */
  function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (k === 'value' || k === 'checked' || k === 'disabled' || k === 'selected') el[k] = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat(Infinity)) if (k != null && k !== false) el.append(k.nodeType ? k : document.createTextNode(String(k)));
    return el;
  }
  const clear = el => {
    while (el.firstChild) el.removeChild(el.firstChild);
    // native append() would stringify arrays and null; accept both like h() does
    el.append = (...k) => { for (const c of k.flat(Infinity)) if (c != null && c !== false) Element.prototype.append.call(el, c.nodeType ? c : document.createTextNode(String(c))); };
    return el;
  };
  const fmt = d => d ? new Date(d).toLocaleString() : '–';
  const qs = o => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(o)) if (v !== '' && v != null) p.set(k, v); const s = p.toString(); return s ? '?' + s : ''; };
  function toast(msg) { const t = h('div', { class: 'toast', role: 'status' }, msg); document.body.append(t); setTimeout(() => t.remove(), 3500); }

  function saveTokens(t) {
    S.access = t.access_token; S.refresh = t.refresh_token; S.user = t.user;
    try { sessionStorage.setItem('sq.admin', JSON.stringify({ r: t.refresh_token })); } catch (e) { /* storage blocked: stay in memory */ }
  }
  function signOut() {
    const r = S.refresh; S.access = S.refresh = S.user = null;
    try { sessionStorage.removeItem('sq.admin'); } catch (e) { }
    if (r) fetch(API + '/auth/logout', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: r }) }).catch(() => { });
    location.hash = '#/login'; render();
  }
  async function refreshTokens() {
    let r = S.refresh;
    if (!r) { try { r = (JSON.parse(sessionStorage.getItem('sq.admin')) || {}).r; } catch (e) { } }
    if (!r) return false;
    const res = await fetch(API + '/auth/refresh', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: r }) });
    if (!res.ok) return false;
    saveTokens(await res.json());
    return S.user && S.user.role === 'admin';
  }
  class ApiError extends Error { constructor(status, body) { super((body && body.error && body.error.message) || 'Request failed'); this.status = status; this.body = body; } }
  async function api(method, path, body, opts = {}) {
    for (let attempt = 0; attempt < 2; attempt++) {
      const headers = { Authorization: 'Bearer ' + S.access };
      let payload;
      if (body instanceof FormData) payload = body; else if (body !== undefined) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
      const res = await fetch(API + path, { method, headers, body: payload });
      if (res.status === 401 && attempt === 0 && await refreshTokens()) continue;
      if (res.status === 401) { signOut(); throw new ApiError(401, null); }
      if (opts.raw) { if (!res.ok) throw new ApiError(res.status, await res.json().catch(() => null)); return res; }
      const data = res.status === 204 ? null : await res.json().catch(() => null);
      if (!res.ok) throw new ApiError(res.status, data);
      return data;
    }
  }
  const guard = fn => async (...a) => { try { return await fn(...a); } catch (e) { if (e.status !== 401) toast(e.message); } };

  function confirmDialog(title, body, okLabel, danger) {
    return new Promise(res => {
      const d = h('dialog', null, h('h2', null, title), h('p', null, body),
        h('div', { class: 'row' }, h('button', { class: danger ? 'danger' : 'primary', onclick: () => { d.close(); d.remove(); res(true); } }, okLabel || 'Confirm'),
          h('button', { onclick: () => { d.close(); d.remove(); res(false); } }, 'Cancel')));
      d.addEventListener('cancel', () => { d.remove(); res(false); });
      document.body.append(d); d.showModal();
    });
  }
  function pager(p, go) {
    const pages = Math.max(1, Math.ceil(p.total / p.size));
    return h('div', { class: 'row between' }, h('span', { class: 'mute small' }, `${p.total} total · page ${p.page} of ${pages}`),
      h('span', { class: 'row' }, h('button', { disabled: p.page <= 1, onclick: () => go(p.page - 1) }, 'Previous'), h('button', { disabled: p.page >= pages, onclick: () => go(p.page + 1) }, 'Next')));
  }
  const badge = s => h('span', { class: 'badge b-' + s }, s);
  const field = (label, input) => h('div', null, h('label', null, label), input);
  const sel = (opts, value, onchange) => { const s = h('select', { onchange }, opts.map(([v, t]) => h('option', { value: v, selected: String(v) === String(value) }, t))); return s; };

  /* ---------- shell / routing ---------- */
  const NAV = [['dashboard', 'Dashboard'], ['questions', 'Questions'], ['import', 'Import / Export'], ['content', 'Grades & subjects'], ['students', 'Students'], ['analytics', 'Analytics'], ['audit', 'Audit log'], ['settings', 'Settings']];
  const routes = {};
  function parseHash() { const [path, q] = (location.hash.slice(1) || '/dashboard').split('?'); return { parts: path.split('/').filter(Boolean), q: Object.fromEntries(new URLSearchParams(q || '')) }; }
  async function render() {
    if (!S.access && !(await refreshTokens())) { return renderLogin(); }
    const { parts, q } = parseHash();
    if (parts[0] === 'login') { location.hash = '#/dashboard'; return; }
    const name = parts[0] || 'dashboard';
    const main = h('main', { id: 'main' }, h('p', { class: 'mute' }, 'Loading…'));
    clear(app).append(h('div', { class: 'shell' },
      h('nav', { 'aria-label': 'Admin' }, h('div', { class: 'brand' }, 'SQUIZ Admin'),
        NAV.map(([k, t]) => h('a', { href: '#/' + k, 'aria-current': k === name ? 'page' : null }, t)),
        h('div', { class: 'who' }, h('div', null, S.user.full_name), h('button', { onclick: signOut }, 'Sign out'))), main));
    try { if (!S.grades.length) { S.grades = await api('GET', '/admin/grades'); } await (routes[name] || routes.dashboard)(main, parts.slice(1), q); }
    catch (e) { if (e.status !== 401) clear(main).append(h('p', { class: 'err', role: 'alert' }, e.message)); }
  }
  const reload = () => render();

  /* ---------- login ---------- */
  function renderLogin(msg) {
    const err = h('div', { class: 'err', role: 'alert' }, msg || '');
    const id = h('input', { id: 'id', autocomplete: 'username', required: true }), pw = h('input', { id: 'pw', type: 'password', autocomplete: 'current-password', required: true });
    const form = h('form', { class: 'card', onsubmit: async e => {
      e.preventDefault(); err.textContent = '';
      const res = await fetch(API + '/admin/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ identifier: id.value, password: pw.value }) });
      const data = await res.json().catch(() => null);
      if (!res.ok) { err.textContent = (data && data.error && data.error.message) || 'Sign-in failed'; return; }
      saveTokens(data); location.hash = '#/dashboard'; render();
    } }, h('h1', null, 'SQUIZ Admin'), h('p', { class: 'mute' }, 'Administrator sign-in'),
      h('label', { for: 'id' }, 'Phone number or full name'), id, h('label', { for: 'pw' }, 'Password'), pw, err,
      h('p', null, h('button', { class: 'primary', type: 'submit' }, 'Sign in')));
    clear(app).append(h('div', { class: 'login' }, form));
  }

  /* ---------- dashboard ---------- */
  routes.dashboard = async main => {
    const d = await api('GET', '/admin/dashboard');
    const stat = (v, l) => h('div', { class: 'card stat' }, h('b', null, v), h('span', null, l));
    clear(main).append(h('h1', null, 'Dashboard'),
      h('div', { class: 'grid' }, stat(d.students, 'Students'), stat(d.questions, 'Questions'), stat(d.published_questions, 'Published'), stat(d.subjects, 'Subjects'), stat(d.units, 'Units'), stat(d.completed_quizzes, 'Completed quizzes')),
      h('div', { class: 'card' }, h('h2', null, 'Recent student activity'), d.recent_activity.length ? h('div', { class: 'tw' }, h('table', null, h('thead', null, h('tr', null, ['Student', 'Quiz', 'Mode', 'Score', 'When'].map(x => h('th', null, x)))),
        h('tbody', null, d.recent_activity.map(a => h('tr', null, h('td', null, a.student), h('td', null, a.title), h('td', null, a.mode), h('td', null, a.percentage + '%'), h('td', null, fmt(a.at))))))) : h('p', { class: 'mute' }, 'No quizzes completed yet.')),
      h('div', { class: 'card' }, h('h2', null, 'Recent administrator actions'), d.recent_admin_actions.length ? h('ul', null, d.recent_admin_actions.map(a => h('li', null, `${fmt(a.at)} · ${a.admin} · ${a.action}${a.entity ? ' (' + a.entity + ' ' + (a.entity_id ?? '') + ')' : ''}`))) : h('p', { class: 'mute' }, 'Nothing yet.')));
  };

  /* ---------- questions list ---------- */
  routes.questions = async (main, rest, q) => {
    if (rest[0] === 'new') return questionEditor(main, null);
    if (rest[0]) return questionEditor(main, +rest[0]);
    if (!S.subjects.length) S.subjects = await api('GET', '/admin/subjects');
    const f = { q: q.q || '', status: q.status || '', grade_id: q.grade_id || '', subject_id: q.subject_id || '', sort: q.sort || 'updated', order: q.order || 'desc', page: +q.page || 1 };
    const data = await api('GET', '/admin/questions' + qs({ ...f, size: 20 }));
    const go = patch => { location.hash = '#/questions' + qs({ ...f, ...patch }); };
    const search = h('input', { type: 'search', placeholder: 'Search question text', value: f.q, 'aria-label': 'Search questions', onkeydown: e => { if (e.key === 'Enter') go({ q: e.target.value, page: 1 }); } });
    const act = (label, fn, cls) => h('button', { class: cls || '', onclick: guard(async () => { await fn(); reload(); }) }, label);
    const rows = data.items.map(x => h('tr', null,
      h('td', null, h('a', { href: '#/questions/' + x.id }, x.text.length > 110 ? x.text.slice(0, 110) + '…' : x.text)),
      h('td', null, `Grade ${x.grade_number ?? '?'} · ${x.subject ?? ''}`, h('div', { class: 'mute small' }, x.unit_title)), h('td', null, badge(x.status)), h('td', null, fmt(x.updated_at)),
      h('td', { class: 'row' }, x.status === 'published' ? act('Unpublish', () => api('POST', `/admin/questions/${x.id}/unpublish`)) : act('Publish', () => api('POST', `/admin/questions/${x.id}/publish`), 'primary'),
        x.status !== 'archived' ? act('Archive', () => api('POST', `/admin/questions/${x.id}/archive`)) : null,
        h('button', { class: 'danger', onclick: guard(async () => { if (await confirmDialog('Delete question?', 'It disappears for students. Past quiz results are kept as they were.', 'Delete', true)) { await api('DELETE', `/admin/questions/${x.id}?confirm=true`); toast('Deleted'); reload(); } }) }, 'Delete'))));
    clear(main).append(h('div', { class: 'row between' }, h('h1', null, 'Questions'), h('a', { class: 'btn primary', href: '#/questions/new' }, 'New question')),
      h('div', { class: 'card row' }, search,
        sel([['', 'All statuses'], ['published', 'Published'], ['draft', 'Draft'], ['archived', 'Archived']], f.status, e => go({ status: e.target.value, page: 1 })),
        sel([['', 'All grades'], ...S.grades.map(g => [g.id, g.name])], f.grade_id, e => go({ grade_id: e.target.value, page: 1 })),
        sel([['', 'All subjects'], ...S.subjects.map(s => [s.id, s.name])], f.subject_id, e => go({ subject_id: e.target.value, page: 1 })),
        sel([['updated', 'Sort: updated'], ['created', 'Sort: created'], ['text', 'Sort: text']], f.sort, e => go({ sort: e.target.value })),
        sel([['desc', 'Descending'], ['asc', 'Ascending']], f.order, e => go({ order: e.target.value })),
        h('button', { onclick: () => go({ q: search.value, page: 1 }) }, 'Search')),
      h('div', { class: 'card tw' }, rows.length ? h('table', null, h('thead', null, h('tr', null, ['Question', 'Where', 'Status', 'Updated', 'Actions'].map(x => h('th', null, x)))), h('tbody', null, rows)) : h('p', { class: 'mute' }, 'No questions match.'), pager(data, p => go({ page: p }))));
  };

  /* ---------- question editor ---------- */
  async function questionEditor(main, id) {
    if (!S.subjects.length) S.subjects = await api('GET', '/admin/subjects');
    const units = await api('GET', '/admin/units');
    const q = id ? await api('GET', '/admin/questions/' + id) : { text: '', explanation: '', difficulty: null, image_url: null, status: 'draft', unit_id: units[0] && units[0].id, options: [{ text: '', is_correct: true }, { text: '' }, { text: '' }, { text: '' }] };
    const subName = Object.fromEntries(S.subjects.map(s => [s.id, s.name])), gradeNum = Object.fromEntries(S.grades.map(g => [g.id, g.number]));
    const unitSel = sel(units.map(u => [u.id, `Grade ${gradeNum[u.grade_id] ?? '?'} · ${subName[u.subject_id] ?? ''} · ${u.title}`]), q.unit_id, () => { });
    const text = h('textarea', { id: 'qt', value: q.text }), expl = h('textarea', { id: 'qe', value: q.explanation || '' });
    const diff = sel([['', 'Not set'], ['easy', 'Easy'], ['medium', 'Medium'], ['hard', 'Hard']], q.difficulty || '', () => { });
    let image = q.image_url;
    const imgInfo = h('span', { class: 'mute small' }, image ? 'Image attached: ' + image : 'No image');
    const file = h('input', { type: 'file', accept: 'image/png,image/jpeg,image/webp', onchange: guard(async e => {
      const fd = new FormData(); fd.append('file', e.target.files[0]); const r = await api('POST', '/admin/uploads', fd); image = r.url; imgInfo.textContent = 'Image attached: ' + image; toast('Image uploaded');
    }) });
    const opts = q.options.map(o => ({ text: o.text, is_correct: !!o.is_correct }));
    const optBox = h('div');
    const drawOpts = () => clear(optBox).append(opts.map((o, i) => h('div', { class: 'opt' },
      h('input', { type: 'radio', name: 'correct', checked: o.is_correct, 'aria-label': 'Correct answer ' + (i + 1), onchange: () => opts.forEach((x, j) => x.is_correct = i === j) }),
      h('input', { type: 'text', value: o.text, maxlength: 1000, 'aria-label': 'Option ' + (i + 1), oninput: e => { o.text = e.target.value; } }),
      h('button', { type: 'button', disabled: opts.length <= 2, onclick: () => { const was = o.is_correct; opts.splice(i, 1); if (was) opts[0].is_correct = true; drawOpts(); } }, 'Remove'))));
    drawOpts();
    const msg = h('div', { class: 'err', role: 'alert' });
    const payload = () => ({ unit_id: +unitSel.value, text: text.value, explanation: expl.value || null, difficulty: diff.value || null, image_url: image || null, options: opts.map(o => ({ text: o.text, is_correct: o.is_correct })) });
    const save = status => guard(async () => {
      msg.textContent = '';
      try {
        let saved;
        if (id) { const p = payload(); if (!p.explanation) { p.clear_explanation = true; delete p.explanation; } if (!p.difficulty) { p.clear_difficulty = true; delete p.difficulty; } if (!p.image_url) { p.clear_image = true; delete p.image_url; } saved = await api('PATCH', '/admin/questions/' + id, p); if (status) saved = await api('POST', `/admin/questions/${id}/${status}`); }
        else { saved = await api('POST', '/admin/questions', { ...payload(), status: status === 'publish' ? 'published' : 'draft' }); }
        toast('Saved'); location.hash = '#/questions';
      } catch (e) { msg.textContent = e.message + (e.body && e.body.error && e.body.error.details ? ' ' + JSON.stringify(e.body.error.details) : ''); }
    });
    const preview = h('div', { class: 'card' }, h('h2', null, 'Student preview'), h('p', { class: 'mute small' }, 'Shows the question the way a student sees it. Answers are not marked.'));
    const showPreview = () => { preview.querySelectorAll('.pv').forEach(n => n.remove()); preview.append(h('div', { class: 'pv' }, h('p', null, text.value || '(empty)'), image ? h('img', { src: image, alt: '', width: 220 }) : null, h('ol', { type: 'A' }, opts.map(o => h('li', null, o.text || '(empty)'))))); };
    clear(main).append(h('p', null, h('a', { href: '#/questions' }, '← All questions')), h('h1', null, id ? `Edit question #${id}` : 'New question'), id ? h('p', null, badge(q.status), ` version ${q.version}`) : null,
      h('div', { class: 'card' }, field('Unit', unitSel), h('label', { for: 'qt' }, 'Question'), text, h('label', null, 'Answer options (select the correct one)'), optBox,
        h('button', { type: 'button', disabled: false, onclick: () => { if (opts.length < 8) { opts.push({ text: '', is_correct: false }); drawOpts(); } } }, 'Add option'),
        h('label', { for: 'qe' }, 'Explanation (optional — leave empty if there is none)'), expl, field('Difficulty', diff), h('label', null, 'Image (optional)'), file, imgInfo, msg,
        h('div', { class: 'row' }, h('button', { class: 'primary', onclick: save(id ? null : 'draft') }, id ? 'Save changes' : 'Save as draft'), h('button', { onclick: save('publish') }, 'Save and publish'), h('button', { onclick: showPreview }, 'Preview'))), preview);
  }

  /* ---------- import / export ---------- */
  routes.import = async main => {
    const file = h('input', { type: 'file', accept: '.csv,.json' }), create = h('input', { type: 'checkbox', id: 'cm' });
    const out = h('div');
    const send = path => { const fd = new FormData(); fd.append('file', file.files[0]); fd.append('create_missing', create.checked ? 'true' : 'false'); return api('POST', path, fd); };
    const showResult = r => {
      clear(out).append(h('div', { class: 'card' }, h('h2', null, 'Result'), h('p', null, `Rows: ${r.summary.total} · ready: ${r.summary.ok} · errors: ${r.summary.errors} · duplicates: ${r.summary.duplicates}`), r.created ? h('p', { class: 'okmsg' }, `Created ${r.created.questions} questions, ${r.created.units} units, ${r.created.subjects} subjects.`) : null,
        h('div', { class: 'tw' }, h('table', null, h('thead', null, h('tr', null, ['Row', 'Status', 'Question', 'Problem'].map(x => h('th', null, x)))), h('tbody', null, r.rows.filter(x => x.status !== 'ok' || !r.created).slice(0, 200).map(x => h('tr', null, h('td', null, x.row), h('td', null, x.status), h('td', null, (x.text || '').slice(0, 90)), h('td', null, [].concat(x.errors || x.message || '').join('; ')))))))));
    };
    const download = fmt => guard(async () => { const res = await api('GET', '/admin/questions/export' + qs({ format: fmt }), undefined, { raw: true }); const blob = await res.blob(); const a = h('a', { href: URL.createObjectURL(blob), download: 'squiz-questions.' + fmt }); document.body.append(a); a.click(); a.remove(); });
    clear(main).append(h('h1', null, 'Import / Export'),
      h('div', { class: 'card' }, h('h2', null, 'Import questions'), h('p', { class: 'mute small' }, 'CSV columns: grade, subject, unit, question, option_a … option_h, answer (letter or option text), explanation (optional), difficulty (optional). JSON: a list of objects with the same keys. Nothing is saved until you press Import.'),
        file, h('div', { class: 'row' }, create, h('label', { for: 'cm', class: 'small' }, 'Create missing subjects and units')),
        h('div', { class: 'row' }, h('button', { onclick: guard(async () => { if (!file.files[0]) return toast('Choose a file first'); showResult(await send('/admin/questions/import/validate')); }) }, 'Validate (preview)'),
          h('button', { class: 'primary', onclick: guard(async () => { if (!file.files[0]) return toast('Choose a file first'); if (await confirmDialog('Import questions?', 'Valid, non-duplicate rows will be added as published questions.', 'Import')) showResult(await send('/admin/questions/import/commit')); }) }, 'Import')), out),
      h('div', { class: 'card' }, h('h2', null, 'Export'), h('p', { class: 'mute small' }, 'Exports all non-deleted questions with answers and status.'), h('div', { class: 'row' }, h('button', { onclick: download('csv') }, 'Download CSV'), h('button', { onclick: download('json') }, 'Download JSON'))));
  };

  /* ---------- grades / subjects / units ---------- */
  routes.content = async main => {
    S.subjects = await api('GET', '/admin/subjects'); S.grades = await api('GET', '/admin/grades');
    const units = await api('GET', '/admin/units');
    const ask = (title, label, initial) => new Promise(res => { const i = h('input', { value: initial || '', 'aria-label': label }); const d = h('dialog', null, h('h2', null, title), i, h('div', { class: 'row' }, h('button', { class: 'primary', onclick: () => { d.close(); d.remove(); res(i.value.trim() || null); } }, 'Save'), h('button', { onclick: () => { d.close(); d.remove(); res(null); } }, 'Cancel'))); document.body.append(d); d.showModal(); });
    const act = fn => guard(async () => { await fn(); reload(); });
    const gradeCards = S.grades.map(g => {
      const gu = units.filter(u => u.grade_id === g.id);
      const bySub = S.subjects.map(s => [s, gu.filter(u => u.subject_id === s.id).sort((a, b) => a.position - b.position)]).filter(([, l]) => l.length);
      return h('div', { class: 'card' }, h('div', { class: 'row between' }, h('h2', null, g.name, ' ', h('span', { class: 'badge ' + (g.published ? 'b-published' : 'b-draft') }, g.published ? 'visible' : 'hidden')),
        h('span', { class: 'row' }, h('button', { onclick: act(async () => { const n = await ask('Rename grade', 'Name', g.name); if (n) await api('PATCH', '/admin/grades/' + g.id, { name: n }); }) }, 'Rename'),
          h('button', { onclick: act(() => api('PATCH', '/admin/grades/' + g.id, { published: !g.published })) }, g.published ? 'Hide from students' : 'Show to students'))),
        bySub.length ? bySub.map(([s, list]) => h('div', null, h('h3', null, s.name), h('table', null, h('tbody', null, list.map((u, i) => h('tr', null, h('td', null, u.title, ' ', h('span', { class: 'badge' }, u.kind), u.published ? null : h('span', { class: 'badge b-draft' }, 'hidden')),
          h('td', { class: 'row' }, h('button', { disabled: i === 0, 'aria-label': 'Move up', onclick: act(() => reorder(g.id, s.id, list, i, -1)) }, '↑'), h('button', { disabled: i === list.length - 1, 'aria-label': 'Move down', onclick: act(() => reorder(g.id, s.id, list, i, 1)) }, '↓'),
            h('button', { onclick: act(async () => { const n = await ask('Rename unit', 'Title', u.title); if (n) await api('PATCH', '/admin/units/' + u.id, { title: n }); }) }, 'Rename'),
            h('button', { onclick: act(() => api('PATCH', '/admin/units/' + u.id, { published: !u.published })) }, u.published ? 'Hide' : 'Show'),
            h('button', { class: 'danger', onclick: guard(async () => { if (await confirmDialog('Delete unit?', 'Only possible when the unit has no questions.', 'Delete', true)) { await api('DELETE', '/admin/units/' + u.id); reload(); } }) }, 'Delete')))))))) : h('p', { class: 'mute' }, 'No units yet.'));
    });
    async function reorder(gid, sid, list, i, d) { const ids = list.map(u => u.id); [ids[i], ids[i + d]] = [ids[i + d], ids[i]]; await api('POST', '/admin/units/reorder', { grade_id: gid, subject_id: sid, unit_ids: ids }); }
    const subTable = h('table', null, h('thead', null, h('tr', null, ['Subject', 'Key', 'Visible', ''].map(x => h('th', null, x)))), h('tbody', null, S.subjects.map(s => h('tr', null, h('td', null, s.name), h('td', null, s.key), h('td', null, s.published ? 'yes' : 'no'),
      h('td', { class: 'row' }, h('button', { onclick: act(async () => { const n = await ask('Rename subject', 'Name', s.name); if (n) await api('PATCH', '/admin/subjects/' + s.id, { name: n }); }) }, 'Rename'), h('button', { onclick: act(() => api('PATCH', '/admin/subjects/' + s.id, { published: !s.published })) }, s.published ? 'Hide' : 'Show'),
        h('button', { class: 'danger', onclick: guard(async () => { if (await confirmDialog('Delete subject?', 'Only possible when it has no units.', 'Delete', true)) { await api('DELETE', '/admin/subjects/' + s.id); reload(); } }) }, 'Delete'))))));
    const nk = h('input', { placeholder: 'key (e.g. biology)', 'aria-label': 'Subject key' }), nn = h('input', { placeholder: 'Name', 'aria-label': 'Subject name' });
    const ug = sel(S.grades.map(g => [g.id, g.name]), S.grades[0] && S.grades[0].id, () => { }), us = sel(S.subjects.map(s => [s.id, s.name]), S.subjects[0] && S.subjects[0].id, () => { }), ut = h('input', { placeholder: 'Unit title', 'aria-label': 'Unit title' });
    clear(main).append(h('h1', null, 'Grades, subjects and units'),
      h('div', { class: 'card' }, h('h2', null, 'Subjects'), h('div', { class: 'tw' }, subTable), h('div', { class: 'row' }, nk, nn, h('button', { class: 'primary', onclick: act(() => api('POST', '/admin/subjects', { key: nk.value.trim().toLowerCase(), name: nn.value.trim() })) }, 'Add subject'))),
      h('div', { class: 'card' }, h('h2', null, 'Add unit'), h('div', { class: 'row' }, ug, us, ut, h('button', { class: 'primary', onclick: act(() => api('POST', '/admin/units', { grade_id: +ug.value, subject_id: +us.value, title: ut.value.trim() })) }, 'Add unit'))), gradeCards);
  };

  /* ---------- students ---------- */
  routes.students = async (main, rest, q) => {
    const f = { q: q.q || '', status: q.status || '', page: +q.page || 1 };
    const data = await api('GET', '/admin/students' + qs({ ...f, size: 20 }));
    const go = patch => { location.hash = '#/students' + qs({ ...f, ...patch }); };
    const search = h('input', { type: 'search', placeholder: 'Name or phone', value: f.q, 'aria-label': 'Search students', onkeydown: e => { if (e.key === 'Enter') go({ q: e.target.value, page: 1 }); } });
    const reset = s => guard(async () => {
      if (!await confirmDialog('Reset password?', `A one-time temporary password will be created for ${s.full_name}. They are signed out everywhere and must choose a new password at next sign-in.`, 'Reset password', true)) return;
      const r = await api('POST', `/admin/students/${s.id}/reset-password`);
      const d = h('dialog', null, h('h2', null, 'Temporary password'), h('p', null, 'Shown only once. Give it to the student privately.'), h('p', null, h('code', { class: 'temp' }, r.temporary_password)), h('button', { class: 'primary', onclick: () => { d.close(); d.remove(); } }, 'Done'));
      document.body.append(d); d.showModal();
    });
    clear(main).append(h('h1', null, 'Students'), h('div', { class: 'card row' }, search, sel([['', 'All'], ['active', 'Active'], ['inactive', 'Inactive']], f.status, e => go({ status: e.target.value, page: 1 })), h('button', { onclick: () => go({ q: search.value, page: 1 }) }, 'Search')),
      h('div', { class: 'card tw' }, h('table', null, h('thead', null, h('tr', null, ['Name', 'Phone', 'Grade', 'Status', 'Joined', 'Last active', ''].map(x => h('th', null, x)))),
        h('tbody', null, data.items.map(s => h('tr', null, h('td', null, s.full_name), h('td', null, s.phone), h('td', null, s.selected_grade ?? '–'), h('td', null, badge(s.status)), h('td', null, fmt(s.created_at)), h('td', null, fmt(s.last_active_at)),
          h('td', { class: 'row' }, h('button', { onclick: guard(async () => { const next = s.status === 'active' ? 'inactive' : 'active'; if (await confirmDialog(next === 'inactive' ? 'Deactivate account?' : 'Activate account?', next === 'inactive' ? 'They are signed out and cannot sign in until reactivated.' : 'They can sign in again.', next === 'inactive' ? 'Deactivate' : 'Activate', next === 'inactive')) { await api('PATCH', `/admin/students/${s.id}/status`, { status: next }); reload(); } }) }, s.status === 'active' ? 'Deactivate' : 'Activate'), h('button', { onclick: reset(s) }, 'Reset password')))))),
        data.items.length ? null : h('p', { class: 'mute' }, 'No students found.'), pager(data, p => go({ page: p }))));
  };

  /* ---------- analytics ---------- */
  routes.analytics = async main => {
    const [a, qa, act] = await Promise.all([api('GET', '/admin/analytics'), api('GET', '/admin/questions-analytics?min_answers=5'), api('GET', '/admin/activity?size=15')]);
    const max = Math.max(1, ...a.attempts_per_day_30d.map(d => d.attempts));
    const table = (cols, rows) => h('div', { class: 'tw' }, h('table', null, h('thead', null, h('tr', null, cols.map(c => h('th', null, c)))), h('tbody', null, rows.map(r => h('tr', null, r.map(c => h('td', null, c)))))));
    clear(main).append(h('h1', null, 'Analytics'),
      h('div', { class: 'card' }, h('h2', null, 'Attempts per day (last 30 days)'), a.attempts_per_day_30d.length ? table(['Date', 'Attempts', ''], a.attempts_per_day_30d.map(d => [d.date, d.attempts, h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round(d.attempts * 100 / max) + '%' }))])) : h('p', { class: 'mute' }, 'No quiz activity yet.')),
      h('div', { class: 'card' }, h('h2', null, 'Average score by subject'), a.by_subject.length ? table(['Subject', 'Attempts', 'Average'], a.by_subject.map(s => [s.subject, s.attempts, s.average_percentage + '%'])) : h('p', { class: 'mute' }, 'No data yet.')),
      h('div', { class: 'card' }, h('h2', null, 'Questions students rarely get right'), h('p', { class: 'mute small' }, 'Answered at least 5 times with under 25% correct — the answer key or wording may need checking.'), qa.may_need_correction.length ? table(['Question', 'Answers', 'Correct'], qa.may_need_correction.map(x => [h('a', { href: '#/questions/' + x.question_id }, x.text.slice(0, 100)), x.answers, x.correct_rate + '%'])) : h('p', { class: 'mute' }, 'None.')),
      h('div', { class: 'card' }, h('h2', null, 'Most used questions'), qa.most_used.length ? table(['Question', 'Answers', 'Correct'], qa.most_used.map(x => [x.text.slice(0, 100), x.answers, x.correct_rate + '%'])) : h('p', { class: 'mute' }, 'None yet.')),
      h('div', { class: 'card' }, h('h2', null, 'Recent quiz activity'), act.items && act.items.length ? table(['Student', 'Quiz', 'Mode', 'Score', 'When'], act.items.map(x => [x.student, x.title, x.mode, x.percentage + '%', fmt(x.at || x.submitted_at)])) : h('p', { class: 'mute' }, 'None yet.')));
  };

  /* ---------- audit ---------- */
  routes.audit = async (main, rest, q) => {
    const page = +q.page || 1, action = q.action || '';
    const data = await api('GET', '/admin/audit' + qs({ page, action, size: 30 }));
    const go = patch => { location.hash = '#/audit' + qs({ action, page, ...patch }); };
    const af = h('input', { placeholder: 'Filter by action, e.g. question.publish', value: action, onkeydown: e => { if (e.key === 'Enter') go({ action: e.target.value, page: 1 }); } });
    clear(main).append(h('h1', null, 'Audit log'), h('div', { class: 'card row' }, af, h('button', { onclick: () => go({ action: af.value, page: 1 }) }, 'Filter')),
      h('div', { class: 'card tw' }, h('table', null, h('thead', null, h('tr', null, ['When', 'Admin', 'Action', 'Target', 'Details', 'IP'].map(x => h('th', null, x)))),
        h('tbody', null, data.items.map(a => h('tr', null, h('td', null, fmt(a.at)), h('td', null, a.admin), h('td', null, a.action), h('td', null, (a.entity || '') + ' ' + (a.entity_id ?? '')), h('td', null, a.details ? JSON.stringify(a.details) : ''), h('td', null, a.ip || ''))))), pager(data, p => go({ page: p }))));
  };

  /* ---------- settings ---------- */
  routes.settings = async main => {
    const s = await api('GET', '/admin/settings');
    const name = h('input', { value: s.app_name || '' }), tag = h('input', { value: s.tagline || '' }), dg = sel([['', 'None'], ...S.grades.map(g => [g.number, g.name])], s.default_grade || '', () => { });
    const an = h('input', { type: 'checkbox', id: 'an', checked: s.allow_name_change !== false });
    clear(main).append(h('h1', null, 'System settings'), h('div', { class: 'card' }, field('App name', name), field('Tagline', tag), field('Default grade for new students', dg),
      h('div', { class: 'row' }, an, h('label', { for: 'an' }, 'Students may change their own name')),
      h('p', null, h('button', { class: 'primary', onclick: guard(async () => { const b = { app_name: name.value, tagline: tag.value, allow_name_change: an.checked }; if (dg.value) b.default_grade = +dg.value; await api('PUT', '/admin/settings', b); toast('Settings saved'); }) }, 'Save settings'))));
  };

  window.addEventListener('hashchange', render);
  render();
})();
