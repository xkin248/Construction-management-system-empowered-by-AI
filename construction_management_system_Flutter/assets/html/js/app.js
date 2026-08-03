// BuildSmart — shared front-end helpers.
// Most page interactivity (sidebar toggle, charts, etc.) is currently
// inlined directly in each page's own <script> block. This file is kept
// as a place to add shared JS helpers used across multiple pages
// (e.g. a shared apiFetch() wrapper that reads window.API_BASE and the
// bs_token saved in localStorage after login).

function apiFetch(path, options = {}) {
  const base = window.API_BASE || 'http://localhost:8000';
  const token = localStorage.getItem('bs_token');
  const headers = Object.assign(
    { 'Content-Type': 'application/json' },
    token ? { Authorization: `Bearer ${token}` } : {},
    options.headers || {}
  );
  return fetch(`${base}/api${path}`, Object.assign({}, options, { headers }));
}
