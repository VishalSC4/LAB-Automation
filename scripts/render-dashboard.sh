#!/bin/bash

set -euo pipefail

source /root/lab.env

ENABLE_ADMIN_DASHBOARD=${enable_admin_dashboard:-true}
ADMIN_DASHBOARD_PORT=${admin_dashboard_port:-8080}

if [[ "$ENABLE_ADMIN_DASHBOARD" != "true" ]]; then
  exit 0
fi

mkdir -p /opt/cloud-lab/dashboard/data
/opt/cloud-lab/generate-report.sh >/dev/null 2>&1 || true
/opt/cloud-lab/collect-usage.sh >/dev/null 2>&1 || true

cat <<EOF > /opt/cloud-lab/dashboard/index.html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cloud Lab Dashboard</title>
  <style>
    :root {
      --bg: #f3efe7;
      --card: #fffdf8;
      --line: #d8ccb6;
      --ink: #1f2933;
      --accent: #b85c38;
      --accent-soft: #f5d7c7;
      --good: #2e7d32;
      --warn: #b26a00;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, #f7d9b7 0, transparent 25%),
        linear-gradient(135deg, #f4efe7, #e8dcc9);
      min-height: 100vh;
    }
    .wrap { max-width: 1100px; margin: 0 auto; padding: 32px 20px 48px; }
    .hero, .card {
      background: rgba(255, 253, 248, 0.92);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: 0 12px 35px rgba(31, 41, 51, 0.08);
    }
    .hero { padding: 28px; margin-bottom: 20px; }
    h1 { margin: 0 0 8px; font-size: clamp(2rem, 4vw, 3.4rem); }
    p { line-height: 1.5; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 16px;
      margin-bottom: 20px;
    }
    .card { padding: 18px; }
    .students {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 16px;
    }
    .student-card {
      border: 1px solid var(--line);
      border-radius: 16px;
      background: var(--card);
      padding: 18px;
    }
    .pill {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 999px;
      background: var(--accent-soft);
      color: var(--accent);
      font-size: 0.85rem;
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .muted { color: #5d6975; }
    .good { color: var(--good); }
    .warn { color: var(--warn); }
    .row { margin-top: 10px; }
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <div class="pill">Admin dashboard</div>
      <h1>Cloud Lab Control Room</h1>
      <p class="muted">This page refreshes every 30 seconds and shows student links, host backup state, and live container usage.</p>
    </section>
    <section class="grid">
      <div class="card"><strong>Host IP</strong><div id="public-ip" class="row muted">Loading...</div></div>
      <div class="card"><strong>Students</strong><div id="student-count" class="row muted">Loading...</div></div>
      <div class="card"><strong>Last Backup</strong><div id="last-backup" class="row muted">Loading...</div></div>
      <div class="card"><strong>Generated</strong><div id="generated-at" class="row muted">Loading...</div></div>
    </section>
    <section class="card">
      <strong>Students</strong>
      <div id="students" class="students" style="margin-top:16px;"></div>
    </section>
  </div>
  <script>
    async function loadData() {
      const [reportRes, usageRes] = await Promise.all([
        fetch('./data/report.json?ts=' + Date.now()),
        fetch('./data/usage.json?ts=' + Date.now()).catch(() => null)
      ]);
      const report = await reportRes.json();
      const usage = usageRes && usageRes.ok ? await usageRes.json() : [];
      const usageMap = new Map(usage.map(item => [item.student_id, item]));

      document.getElementById('public-ip').textContent = report.public_ip || 'pending';
      document.getElementById('student-count').textContent = report.students.length;
      document.getElementById('last-backup').textContent = report.backups.last_backup || 'No backup yet';
      document.getElementById('generated-at').textContent = report.generated_at;

      const root = document.getElementById('students');
      root.innerHTML = '';
      for (const student of report.students) {
        const live = usageMap.get(student.student_id) || {};
        const card = document.createElement('article');
        card.className = 'student-card';
        card.innerHTML = `
          <div class="pill">${student.student_id}</div>
          <div class="row"><strong>SSH</strong>: <span class="muted">ssh -p ${student.ssh_port} student@${report.public_ip}</span></div>
          <div class="row"><strong>Static</strong>: ${student.static_url ? `<a href="${student.static_url}" target="_blank">${student.static_url}</a>` : '<span class="muted">Disabled</span>'}</div>
          <div class="row"><strong>Dynamic</strong>: ${student.dynamic_url ? `<a href="${student.dynamic_url}" target="_blank">${student.dynamic_url}</a>` : '<span class="muted">Disabled</span>'}</div>
          <div class="row"><strong>Status</strong>: <span class="${live.status === 'running' ? 'good' : 'warn'}">${live.status || 'unknown'}</span></div>
          <div class="row"><strong>CPU</strong>: <span class="muted">${live.cpu_percent || 'n/a'}</span></div>
          <div class="row"><strong>Memory</strong>: <span class="muted">${live.memory_usage || 'n/a'}</span></div>
        `;
        root.appendChild(card);
      }
    }

    loadData();
    setInterval(loadData, 30000);
  </script>
</body>
</html>
EOF
