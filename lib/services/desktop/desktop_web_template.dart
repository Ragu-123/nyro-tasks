class DesktopWebTemplate {
  static String render({
    required String localIp,
    required int port,
    required String version,
  }) {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NYRO Study Studio - Desktop Companion</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --primary: #1a73e8;
      --primary-hover: #1557b0;
      --surface: #ffffff;
      --background: #f8fafd;
      --text-main: #202124;
      --text-secondary: #5f6368;
      --border: #dadce0;
      --danger: #d93025;
      --success: #188038;
      --warning: #f29900;
      --card-radius: 12px;
      --font-sans: 'Inter', system-ui, -apple-system, sans-serif;
      --font-mono: 'JetBrains Mono', monospace;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: var(--font-sans);
      background-color: var(--background);
      color: var(--text-main);
      display: flex;
      height: 100vh;
      overflow: hidden;
      font-size: 14px;
    }

    /* Auth Shield Modal */
    #auth-shield {
      position: fixed;
      inset: 0;
      background: rgba(32, 33, 36, 0.7);
      backdrop-filter: blur(8px);
      z-index: 1000;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .auth-card {
      background: var(--surface);
      border-radius: 16px;
      padding: 36px 32px;
      width: 100%;
      max-width: 420px;
      box-shadow: 0 12px 32px rgba(0,0,0,0.18);
      text-align: center;
    }
    .auth-card h2 { font-size: 20px; font-weight: 700; margin-bottom: 8px; }
    .auth-card p { color: var(--text-secondary); font-size: 13px; line-height: 1.5; margin-bottom: 24px; }
    .pin-input {
      font-family: var(--font-mono);
      font-size: 26px;
      letter-spacing: 8px;
      text-align: center;
      width: 100%;
      padding: 12px;
      border: 2px solid var(--border);
      border-radius: 8px;
      outline: none;
      margin-bottom: 16px;
    }
    .pin-input:focus { border-color: var(--primary); }
    .auth-btn {
      width: 100%;
      background: var(--primary);
      color: #fff;
      border: none;
      padding: 12px;
      border-radius: 8px;
      font-weight: 600;
      cursor: pointer;
      font-size: 14px;
    }
    .auth-btn:hover { background: var(--primary-hover); }

    /* Layout */
    aside {
      width: 250px;
      background: var(--surface);
      border-right: 1px solid var(--border);
      display: flex;
      flex-direction: column;
    }
    .brand {
      padding: 20px;
      font-weight: 700;
      font-size: 16px;
      display: flex;
      align-items: center;
      gap: 10px;
      border-bottom: 1px solid var(--border);
    }
    .nav-links { list-style: none; padding: 12px 8px; flex: 1; overflow-y: auto; }
    .nav-item {
      padding: 10px 14px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      gap: 10px;
      cursor: pointer;
      color: var(--text-secondary);
      font-weight: 500;
      margin-bottom: 4px;
    }
    .nav-item:hover { background: var(--background); color: var(--text-main); }
    .nav-item.active { background: #e8f0fe; color: var(--primary); font-weight: 600; }
    .sidebar-footer {
      padding: 16px;
      border-top: 1px solid var(--border);
      font-size: 12px;
      color: var(--text-secondary);
    }

    main {
      flex: 1;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    header {
      height: 60px;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 24px;
    }
    .tab-content {
      flex: 1;
      padding: 24px;
      overflow-y: auto;
      display: none;
    }
    .tab-content.active { display: block; }

    /* Buttons & Inputs */
    .btn {
      padding: 8px 16px;
      border-radius: 6px;
      font-weight: 500;
      cursor: pointer;
      border: 1px solid transparent;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 13px;
    }
    .btn-primary { background: var(--primary); color: #fff; }
    .btn-primary:hover { background: var(--primary-hover); }
    .btn-outline { border-color: var(--border); background: var(--surface); color: var(--text-main); }
    .btn-outline:hover { background: var(--background); }
    .search-input {
      padding: 8px 12px;
      border: 1px solid var(--border);
      border-radius: 6px;
      outline: none;
      width: 280px;
      font-size: 13px;
    }
    .search-input:focus { border-color: var(--primary); }

    /* Keep Notes Grid */
    .notes-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 16px;
      margin-top: 16px;
    }
    .keep-card {
      border: 1px solid var(--border);
      border-radius: var(--card-radius);
      padding: 16px;
      background: #ffffff;
      box-shadow: 0 1px 3px rgba(0,0,0,0.04);
      display: flex;
      flex-direction: column;
      position: relative;
    }
    .keep-card h4 { font-size: 15px; font-weight: 700; margin-bottom: 6px; }
    .keep-card p { font-size: 13px; color: var(--text-main); white-space: pre-wrap; word-break: break-word; line-height: 1.4; flex: 1; }
    .keep-tags { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 10px; }
    .keep-tag-chip {
      background: rgba(0,0,0,0.06);
      padding: 2px 8px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
      color: var(--text-secondary);
    }
    .keep-card-actions {
      display: flex;
      justify-content: flex-end;
      gap: 8px;
      margin-top: 12px;
      padding-top: 8px;
      border-top: 1px solid rgba(0,0,0,0.05);
    }

    /* Modal */
    .modal {
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.5);
      display: none;
      align-items: center;
      justify-content: center;
      z-index: 500;
    }
    .modal.active { display: flex; }
    .modal-box {
      background: var(--surface);
      border-radius: 16px;
      padding: 24px;
      width: 100%;
      max-width: 500px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.15);
    }
    .form-group { margin-bottom: 14px; }
    .form-group label { display: block; font-size: 12px; font-weight: 600; margin-bottom: 4px; color: var(--text-secondary); }
    .form-control {
      width: 100%;
      padding: 8px 10px;
      border: 1px solid var(--border);
      border-radius: 6px;
      font-size: 13px;
      font-family: inherit;
    }

    /* Mistakes Cards */
    .mistakes-grid {
      display: flex;
      flex-direction: column;
      gap: 16px;
      margin-top: 16px;
    }
    .mistake-card {
      border: 1px solid var(--border);
      border-radius: var(--card-radius);
      padding: 18px 20px;
      background: var(--surface);
      box-shadow: 0 1px 3px rgba(0,0,0,0.04);
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .mistake-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      flex-wrap: wrap;
      gap: 10px;
    }
    .mistake-topic {
      font-size: 15px;
      font-weight: 700;
      color: var(--text-main);
    }
    .mistake-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      align-items: center;
    }
    .badge-subject {
      background: #e8f0fe;
      color: var(--primary);
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
    }
    .badge-severity-low {
      background: #e6f4ea;
      color: #137333;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
    }
    .badge-severity-medium {
      background: #fef7e0;
      color: #b06000;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
    }
    .badge-severity-high {
      background: #fce8e6;
      color: #c5221f;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
    }
    .badge-quiz {
      background: #f1f3f4;
      color: #5f6368;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 500;
    }
    .mistake-section {
      border-radius: 6px;
      padding: 10px 14px;
      font-size: 13px;
      line-height: 1.5;
    }
    .mistake-section-title {
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 4px;
    }
    .mistake-question {
      background: var(--background);
      border: 1px solid var(--border);
      color: var(--text-main);
      white-space: pre-wrap;
    }
    .answers-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    @media (max-width: 768px) {
      .answers-row { grid-template-columns: 1fr; }
    }
    .box-wrong {
      background: #fdf2f2;
      border-left: 3px solid var(--danger);
      color: #991b1b;
    }
    .box-correct {
      background: #f0fdf4;
      border-left: 3px solid var(--success);
      color: #166534;
    }
    .box-reason {
      background: #fffbeb;
      border-left: 3px solid var(--warning);
      color: #92400e;
    }
    .box-takeaway {
      background: #eff6ff;
      border-left: 3px solid var(--primary);
      color: #1e40af;
    }
    .mistake-footer {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-top: 4px;
      padding-top: 10px;
      border-top: 1px solid var(--border);
    }
    .badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
    }
    .badge-unresolved { background: #fce8e6; color: var(--danger); }
    .badge-resolved { background: #e6f4ea; color: var(--success); }
  </style>
</head>
<body>

  <!-- Auth Shield -->
  <div id="auth-shield">
    <div class="auth-card">
      <h2>Wi-Fi Shield Protection</h2>
      <p>Enter the 6-digit PIN displayed on your NYRO Tasks phone app to access this study studio session.</p>
      <input type="password" id="pin-input" class="pin-input" maxlength="6" placeholder="******" autofocus />
      <button class="auth-btn" onclick="verifyPin()">Unlock Studio</button>
      <div id="auth-err" style="color: var(--danger); font-size: 12px; margin-top: 10px; display: none;"></div>
    </div>
  </div>

  <!-- Sidebar -->
  <aside>
    <div class="brand">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#1a73e8" stroke-width="2.5"><polyline points="9 11 12 14 22 4"></polyline><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"></path></svg>
      <span>NYRO Studio</span>
    </div>
    <ul class="nav-links">
      <li class="nav-item active" onclick="switchTab('keep')">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18h6"></path><path d="M10 22h4"></path><path d="M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5A4.61 4.61 0 0 1 8.91 14"></path></svg>
        <span>Google Keep Notes</span>
      </li>
      <li class="nav-item" onclick="switchTab('mistakes')">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>
        <span>Mistakes Notebook</span>
      </li>
      <li class="nav-item" onclick="switchTab('status')">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline></svg>
        <span>Server & Sync Status</span>
      </li>
    </ul>
    <div class="sidebar-footer">
      <div>Host: $localIp:$port</div>
      <div>App v$version</div>
    </div>
  </aside>

  <!-- Main Content -->
  <main>
    <header>
      <div id="header-title" style="font-weight: 700; font-size: 16px;">Google Keep Notes</div>
      <div style="display: flex; gap: 10px; align-items: center;">
        <button class="btn btn-outline" onclick="lockStudio()">Lock</button>
      </div>
    </header>

    <!-- Tab 1: Google Keep Notes -->
    <div id="tab-keep" class="tab-content active">
      <div style="display: flex; justify-content: space-between; align-items: center;">
        <input type="text" id="keep-search" class="search-input" placeholder="Search notes and tags..." oninput="filterNotes()" />
        <button class="btn btn-primary" onclick="openCreateNoteModal()">+ New Note</button>
      </div>
      <div id="notes-container" class="notes-grid"></div>
    </div>

    <!-- Tab 2: Mistakes Notebook -->
    <div id="tab-mistakes" class="tab-content">
      <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px;">
        <input type="text" id="mistake-search" class="search-input" placeholder="Search by subject, topic, question, reason..." oninput="filterMistakes()" />
        <div style="display: flex; gap: 8px;">
          <button class="btn btn-primary" onclick="openCreateMistakeModal()">+ Log Mistake</button>
          <button class="btn btn-outline" onclick="loadMistakes()">Refresh</button>
        </div>
      </div>
      <div id="mistakes-container" class="mistakes-grid"></div>
    </div>

    <!-- Tab 3: Status -->
    <div id="tab-status" class="tab-content">
      <div style="background: var(--surface); padding: 20px; border-radius: var(--card-radius); border: 1px solid var(--border);">
        <h3 style="margin-bottom: 12px;">Server Information</h3>
        <p style="margin-bottom: 6px;">IP Address: <strong>$localIp</strong></p>
        <p style="margin-bottom: 6px;">Port: <strong>$port</strong></p>
        <p style="margin-bottom: 6px;">Version: <strong>v$version</strong></p>
        <p>Status: <span style="color: var(--success); font-weight: bold;">Online & Serving</span></p>
      </div>
    </div>
  </main>

  <!-- Create Note Modal -->
  <div id="note-modal" class="modal">
    <div class="modal-box">
      <h3 style="margin-bottom: 16px;">Create Note</h3>
      <div class="form-group">
        <label>Title</label>
        <input type="text" id="modal-note-title" class="form-control" placeholder="Note Title" />
      </div>
      <div class="form-group">
        <label>Content</label>
        <textarea id="modal-note-content" class="form-control" rows="5" placeholder="Take a note..."></textarea>
      </div>
      <div class="form-group">
        <label>Tags (comma separated)</label>
        <input type="text" id="modal-note-tags" class="form-control" placeholder="Formula, Revision" />
      </div>
      <div class="form-group">
        <label>Color</label>
        <select id="modal-note-color" class="form-control">
          <option value="#FFFFFF">Default White</option>
          <option value="#F28B82">Coral</option>
          <option value="#FBBC04">Peach</option>
          <option value="#FFF475">Sand</option>
          <option value="#CCFF90">Mint</option>
          <option value="#A7FFEB">Sage</option>
          <option value="#CBF0F8">Fog</option>
          <option value="#AECBFA">Storm</option>
          <option value="#D7AEFB">Dusk</option>
          <option value="#FDCFE8">Blossom</option>
          <option value="#E6C9A8">Clay</option>
          <option value="#E8EAED">Chalk</option>
        </select>
      </div>
      <div style="display: flex; justify-content: flex-end; gap: 8px; margin-top: 20px;">
        <button class="btn btn-outline" onclick="closeCreateNoteModal()">Cancel</button>
        <button class="btn btn-primary" onclick="submitCreateNote()">Save Note</button>
      </div>
    </div>
  </div>

  <!-- Create Mistake Modal -->
  <div id="mistake-modal" class="modal">
    <div class="modal-box" style="max-width: 620px; max-height: 90vh; overflow-y: auto;">
      <h3 style="margin-bottom: 16px;">Log New Blunder / Mistake</h3>
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
        <div class="form-group">
          <label>Subject *</label>
          <input type="text" id="modal-mistake-subject" list="subjects-datalist" class="form-control" placeholder="e.g. Linear Algebra, DBMS" />
          <datalist id="subjects-datalist"></datalist>
        </div>
        <div class="form-group">
          <label>Topic *</label>
          <input type="text" id="modal-mistake-topic" class="form-control" placeholder="e.g. Eigenvalues & Determinants" />
        </div>
      </div>
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
        <div class="form-group">
          <label>Severity</label>
          <select id="modal-mistake-severity" class="form-control">
            <option value="MEDIUM" selected>MEDIUM</option>
            <option value="LOW">LOW</option>
            <option value="HIGH">HIGH</option>
          </select>
        </div>
        <div class="form-group">
          <label>Linked Quiz (Optional)</label>
          <input type="text" id="modal-mistake-quiz" class="form-control" placeholder="e.g. Weekly Quiz 1" />
        </div>
      </div>
      <div class="form-group">
        <label>Question / Source Text</label>
        <textarea id="modal-mistake-question" class="form-control" rows="3" placeholder="Enter problem statement or context..."></textarea>
      </div>
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
        <div class="form-group">
          <label>Wrong Answer / Trap</label>
          <textarea id="modal-mistake-wrong" class="form-control" rows="2" placeholder="What you marked or thought..."></textarea>
        </div>
        <div class="form-group">
          <label>Correct Answer</label>
          <textarea id="modal-mistake-correct" class="form-control" rows="2" placeholder="The actual correct solution..."></textarea>
        </div>
      </div>
      <div class="form-group">
        <label>Why It Went Wrong (Mistake Reason)</label>
        <textarea id="modal-mistake-reason" class="form-control" rows="2" placeholder="Conceptual gap, calculation slip, missed edge case..."></textarea>
      </div>
      <div class="form-group">
        <label>Key Takeaway & Golden Rule</label>
        <textarea id="modal-mistake-takeaway" class="form-control" rows="2" placeholder="Never assume symmetric matrix without checking..."></textarea>
      </div>
      <div style="display: flex; justify-content: flex-end; gap: 8px; margin-top: 20px;">
        <button class="btn btn-outline" onclick="closeCreateMistakeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="submitCreateMistake()">Save Mistake</button>
      </div>
    </div>
  </div>

  <script>
    let authToken = localStorage.getItem('nyro_token') || '';
    let notesData = [];
    let mistakesData = [];

    async function checkAuth() {
      if (!authToken) {
        document.getElementById('auth-shield').style.display = 'flex';
        return;
      }
      try {
        const res = await fetch('/api/auth/status', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        const data = await res.json();
        if (data && data.authenticated) {
          document.getElementById('auth-shield').style.display = 'none';
          loadNotes();
          loadMistakes();
          loadSubjects();
        } else {
          document.getElementById('auth-shield').style.display = 'flex';
        }
      } catch (err) {
        document.getElementById('auth-shield').style.display = 'flex';
      }
    }

    async function verifyPin() {
      const pin = document.getElementById('pin-input').value.trim();
      const errBox = document.getElementById('auth-err');
      errBox.style.display = 'none';
      if (!pin || pin.length !== 6) {
        errBox.innerText = 'Please enter a 6-digit PIN.';
        errBox.style.display = 'block';
        return;
      }
      try {
        const res = await fetch('/api/auth/verify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ pin: pin })
        });
        const data = await res.json();
        if (data && data.success && data.token) {
          authToken = data.token;
          localStorage.setItem('nyro_token', authToken);
          document.getElementById('auth-shield').style.display = 'none';
          loadNotes();
          loadMistakes();
          loadSubjects();
        } else {
          errBox.innerText = data.error || 'Authentication failed.';
          errBox.style.display = 'block';
        }
      } catch (e) {
        errBox.innerText = 'Network connection failed.';
        errBox.style.display = 'block';
      }
    }

    async function lockStudio() {
      try {
        await fetch('/api/auth/logout', {
          method: 'POST',
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
      } catch (_) {}
      authToken = '';
      localStorage.removeItem('nyro_token');
      document.getElementById('auth-shield').style.display = 'flex';
      document.getElementById('pin-input').value = '';
    }

    function switchTab(tab) {
      document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
      document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
      document.getElementById('tab-' + tab).classList.add('active');

      const titles = {
        'keep': 'Google Keep Notes',
        'mistakes': 'Mistakes Notebook',
        'status': 'Server & Sync Status'
      };
      document.getElementById('header-title').innerText = titles[tab] || 'Studio';

      const links = document.querySelectorAll('.nav-item');
      if (tab === 'keep') links[0].classList.add('active');
      if (tab === 'mistakes') links[1].classList.add('active');
      if (tab === 'status') links[2].classList.add('active');
    }

    async function loadNotes() {
      try {
        const res = await fetch('/api/notes', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        if (res.status === 401) { lockStudio(); return; }
        const data = await res.json();
        notesData = data.notes || [];
        renderNotes(notesData);
      } catch (_) {}
    }

    function renderNotes(notes) {
      const c = document.getElementById('notes-container');
      c.innerHTML = '';
      if (!notes.length) {
        c.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 48px; color: var(--text-secondary);">No notes found. Tap New Note to create one.</div>';
        return;
      }
      notes.forEach(n => {
        const card = document.createElement('div');
        card.className = 'keep-card';
        card.style.backgroundColor = n.color || '#FFFFFF';

        let contentHtml = '';
        if (n.title) contentHtml += '<h4>' + escapeHtml(n.title) + '</h4>';
        if (n.content) contentHtml += '<p>' + escapeHtml(n.content) + '</p>';

        if (n.is_todo_list && n.todo_items_json) {
          try {
            const items = JSON.parse(n.todo_items_json);
            if (Array.isArray(items)) {
              items.forEach(it => {
                contentHtml += '<div style="font-size: 12px; margin: 2px 0;">' + (it.checked ? '&#9745; ' : '&#9744; ') + escapeHtml(it.text || '') + '</div>';
              });
            }
          } catch (_) {}
        }

        if (n.tags_json) {
          try {
            const tags = JSON.parse(n.tags_json);
            if (Array.isArray(tags) && tags.length) {
              contentHtml += '<div class="keep-tags">';
              tags.forEach(t => {
                contentHtml += '<span class="keep-tag-chip">#' + escapeHtml(t) + '</span>';
              });
              contentHtml += '</div>';
            }
          } catch (_) {}
        }

        contentHtml += '<div class="keep-card-actions">';
        contentHtml += '<button class="btn btn-outline" style="padding: 4px 8px; font-size: 11px;" onclick="deleteNote(\' + n.id + \')">Delete</button>';
        contentHtml += '</div>';

        card.innerHTML = contentHtml;
        c.appendChild(card);
      });
    }

    function filterNotes() {
      const q = document.getElementById('keep-search').value.toLowerCase().trim();
      if (!q) {
        renderNotes(notesData);
        return;
      }
      const filtered = notesData.filter(n => {
        const titleMatch = (n.title || '').toLowerCase().includes(q);
        const contentMatch = (n.content || '').toLowerCase().includes(q);
        const tagMatch = (n.tags_json || '').toLowerCase().includes(q);
        return titleMatch || contentMatch || tagMatch;
      });
      renderNotes(filtered);
    }

    function openCreateNoteModal() {
      document.getElementById('modal-note-title').value = '';
      document.getElementById('modal-note-content').value = '';
      document.getElementById('modal-note-tags').value = '';
      document.getElementById('modal-note-color').value = '#FFFFFF';
      document.getElementById('note-modal').classList.add('active');
    }

    function closeCreateNoteModal() {
      document.getElementById('note-modal').classList.remove('active');
    }

    async function submitCreateNote() {
      const title = document.getElementById('modal-note-title').value.trim();
      const content = document.getElementById('modal-note-content').value.trim();
      const rawTags = document.getElementById('modal-note-tags').value.trim();
      const color = document.getElementById('modal-note-color').value;

      const tags = rawTags ? rawTags.split(',').map(s => s.trim()).filter(s => s.length > 0) : [];

      try {
        const res = await fetch('/api/notes', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + authToken
          },
          body: JSON.stringify({
            title: title,
            content: content,
            color: color,
            tags: tags
          })
        });
        if (res.ok) {
          closeCreateNoteModal();
          loadNotes();
        }
      } catch (_) {}
    }

    async function deleteNote(id) {
      if (!confirm('Are you sure you want to delete this note?')) return;
      try {
        await fetch('/api/notes/' + id, {
          method: 'DELETE',
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        loadNotes();
      } catch (_) {}
    }

    function openCreateMistakeModal() {
      document.getElementById('modal-mistake-subject').value = '';
      document.getElementById('modal-mistake-topic').value = '';
      document.getElementById('modal-mistake-severity').value = 'MEDIUM';
      document.getElementById('modal-mistake-quiz').value = '';
      document.getElementById('modal-mistake-question').value = '';
      document.getElementById('modal-mistake-wrong').value = '';
      document.getElementById('modal-mistake-correct').value = '';
      document.getElementById('modal-mistake-reason').value = '';
      document.getElementById('modal-mistake-takeaway').value = '';
      document.getElementById('mistake-modal').classList.add('active');
    }

    function closeCreateMistakeModal() {
      document.getElementById('mistake-modal').classList.remove('active');
    }

    async function loadSubjects() {
      try {
        const res = await fetch('/api/subjects', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        if (res.ok) {
          const data = await res.json();
          const list = document.getElementById('subjects-datalist');
          if (list && data.subjects) {
            list.innerHTML = '';
            data.subjects.forEach(function(s) {
              const opt = document.createElement('option');
              opt.value = s;
              list.appendChild(opt);
            });
          }
        }
      } catch (_) {}
    }

    async function submitCreateMistake() {
      const subject = document.getElementById('modal-mistake-subject').value.trim();
      const topic = document.getElementById('modal-mistake-topic').value.trim();
      const severity = document.getElementById('modal-mistake-severity').value;
      const quiz = document.getElementById('modal-mistake-quiz').value.trim();
      const question = document.getElementById('modal-mistake-question').value.trim();
      const wrong = document.getElementById('modal-mistake-wrong').value.trim();
      const correct = document.getElementById('modal-mistake-correct').value.trim();
      const reason = document.getElementById('modal-mistake-reason').value.trim();
      const takeaway = document.getElementById('modal-mistake-takeaway').value.trim();

      if (!subject || !topic) {
        alert('Please provide both Subject and Topic.');
        return;
      }

      try {
        const res = await fetch('/api/mistakes', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + authToken
          },
          body: JSON.stringify({
            subject: subject,
            topic: topic,
            severity: severity,
            quiz_title: quiz,
            question_text: question,
            wrong_answer: wrong,
            correct_answer: correct,
            mistake_reason: reason,
            key_takeaway: takeaway
          })
        });
        if (res.status === 401) { lockStudio(); return; }
        if (res.ok) {
          closeCreateMistakeModal();
          loadMistakes();
        } else {
          const err = await res.json().catch(function() { return {}; });
          alert(err.error || 'Failed to save mistake.');
        }
      } catch (_) {
        alert('Failed to connect to server.');
      }
    }

    async function toggleMistake(id, newResolved) {
      try {
        const res = await fetch('/api/mistakes/' + id + '/resolve', {
          method: 'PATCH',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + authToken
          },
          body: JSON.stringify({ resolved: newResolved })
        });
        if (res.status === 401) { lockStudio(); return; }
        loadMistakes();
      } catch (_) {}
    }

    async function deleteMistake(id) {
      if (!confirm('Are you sure you want to delete this mistake record?')) return;
      try {
        const res = await fetch('/api/mistakes/' + id, {
          method: 'DELETE',
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        if (res.status === 401) { lockStudio(); return; }
        loadMistakes();
      } catch (_) {}
    }

    async function loadMistakes() {
      try {
        const res = await fetch('/api/mistakes', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        if (res.status === 401) { lockStudio(); return; }
        const data = await res.json();
        mistakesData = data.mistakes || data.records || [];
        renderMistakes(mistakesData);
      } catch (_) {}
    }

    function renderMistakes(records) {
      const c = document.getElementById('mistakes-container');
      c.innerHTML = '';
      if (!records.length) {
        c.innerHTML = '<div style="text-align: center; color: var(--text-secondary); padding: 48px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--card-radius);">No mistake records found. Click + Log Mistake to create one.</div>';
        return;
      }
      records.forEach(function(r) {
        const card = document.createElement('div');
        card.className = 'mistake-card';

        const isResolved = (r.status || '').toUpperCase() === 'RESOLVED';
        const severity = (r.severity || 'MEDIUM').toUpperCase();
        let sevClass = 'badge-severity-medium';
        if (severity === 'LOW') sevClass = 'badge-severity-low';
        else if (severity === 'HIGH' || severity === 'CRITICAL') sevClass = 'badge-severity-high';

        let html = '';

        // Header with Topic & Badges
        html += '<div class="mistake-header">';
        html += '  <div class="mistake-topic">' + escapeHtml(r.topic || 'Untitled Mistake') + '</div>';
        html += '  <div class="mistake-badges">';
        if (r.subject) {
          html += '    <span class="badge-subject">' + escapeHtml(r.subject) + '</span>';
        }
        html += '    <span class="' + sevClass + '">' + escapeHtml(severity) + '</span>';
        if (r.quiz_title && r.quiz_title.trim().length > 0) {
          html += '    <span class="badge-quiz">' + escapeHtml(r.quiz_title) + '</span>';
        }
        html += '  </div>';
        html += '</div>';

        // Question / Source Text
        const question = r.question_text || '';
        if (question && question.trim().length > 0) {
          html += '<div class="mistake-section mistake-question">';
          html += '  <div class="mistake-section-title" style="color: var(--text-secondary);">Question / Source Text</div>';
          html += '  <div>' + escapeHtml(question) + '</div>';
          html += '</div>';
        }

        // Side-by-side or stacked Wrong Answer & Correct Answer
        const wrong = r.wrong_answer || '';
        const correct = r.correct_answer || '';
        if (wrong.trim().length > 0 || correct.trim().length > 0) {
          html += '<div class="answers-row">';
          if (wrong.trim().length > 0) {
            html += '<div class="mistake-section box-wrong">';
            html += '  <div class="mistake-section-title">Wrong Answer / Trap</div>';
            html += '  <div>' + escapeHtml(wrong) + '</div>';
            html += '</div>';
          }
          if (correct.trim().length > 0) {
            html += '<div class="mistake-section box-correct">';
            html += '  <div class="mistake-section-title">Correct Answer</div>';
            html += '  <div>' + escapeHtml(correct) + '</div>';
            html += '</div>';
          }
          html += '</div>';
        }

        // Why It Went Wrong (mistake_reason or reason)
        const reason = r.mistake_reason || r.reason || '';
        if (reason && reason.trim().length > 0) {
          html += '<div class="mistake-section box-reason">';
          html += '  <div class="mistake-section-title">Why It Went Wrong</div>';
          html += '  <div>' + escapeHtml(reason) + '</div>';
          html += '</div>';
        }

        // Key Takeaway & Golden Rule
        const takeaway = r.key_takeaway || r.takeaway || '';
        if (takeaway && takeaway.trim().length > 0) {
          html += '<div class="mistake-section box-takeaway">';
          html += '  <div class="mistake-section-title">Key Takeaway & Golden Rule</div>';
          html += '  <div>' + escapeHtml(takeaway) + '</div>';
          html += '</div>';
        }

        // Footer with Status Pill and Action Buttons
        html += '<div class="mistake-footer">';
        html += '  <div>';
        html += '    <span class="badge ' + (isResolved ? 'badge-resolved' : 'badge-unresolved') + '">' + (isResolved ? 'RESOLVED' : 'UNRESOLVED') + '</span>';
        html += '  </div>';
        html += '  <div style="display: flex; gap: 8px;">';
        html += '    <button class="btn btn-outline" style="padding: 4px 10px; font-size: 11px;" onclick="toggleMistake(' + r.id + ', ' + (!isResolved) + ')">' + (isResolved ? 'Mark Unresolved' : 'Mark Resolved') + '</button>';
        html += '    <button class="btn btn-outline" style="padding: 4px 10px; font-size: 11px; color: var(--danger); border-color: #fce8e6;" onclick="deleteMistake(' + r.id + ')">Delete</button>';
        html += '  </div>';
        html += '</div>';

        card.innerHTML = html;
        c.appendChild(card);
      });
    }

    function filterMistakes() {
      const q = document.getElementById('mistake-search').value.toLowerCase().trim();
      if (!q) {
        renderMistakes(mistakesData);
        return;
      }
      const filtered = mistakesData.filter(function(r) {
        const subject = (r.subject || '').toLowerCase();
        const topic = (r.topic || '').toLowerCase();
        const question = (r.question_text || '').toLowerCase();
        const reason = (r.mistake_reason || r.reason || '').toLowerCase();
        const wrong = (r.wrong_answer || '').toLowerCase();
        const correct = (r.correct_answer || '').toLowerCase();
        const takeaway = (r.key_takeaway || r.takeaway || '').toLowerCase();
        const quiz = (r.quiz_title || '').toLowerCase();
        return subject.indexOf(q) !== -1 ||
               topic.indexOf(q) !== -1 ||
               question.indexOf(q) !== -1 ||
               reason.indexOf(q) !== -1 ||
               wrong.indexOf(q) !== -1 ||
               correct.indexOf(q) !== -1 ||
               takeaway.indexOf(q) !== -1 ||
               quiz.indexOf(q) !== -1;
      });
      renderMistakes(filtered);
    }

    function escapeHtml(text) {
      if (!text) return '';
      return String(text).replace(/[&<>"']/g, function(m) {
        return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[m];
      });
    }

    // 3s Session Heartbeat
    setInterval(async function() {
      if (!authToken) return;
      try {
        const res = await fetch('/api/auth/status', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        });
        if (res.status === 401) { lockStudio(); }
        else {
          const data = await res.json();
          if (!data || !data.authenticated) { lockStudio(); }
        }
      } catch (_) {}
    }, 3000);

    checkAuth();
  </script>
</body>
</html>''';
  }
}
