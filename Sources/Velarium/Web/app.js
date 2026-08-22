(() => {
  'use strict';

  const cfg = window.VELARIUM;
  const stage = document.getElementById('stage');
  const canvas = document.getElementById('screen');
  const ctx = canvas.getContext('2d', { alpha: false, desynchronized: true });
  const frameEl = document.getElementById('frame');
  const placeholder = document.getElementById('placeholder');
  const dot = document.getElementById('dot');
  const header = document.getElementById('header');
  const bar = document.getElementById('bar') || header;
  const timerEl = document.getElementById('timer');
  const zoomBadge = document.getElementById('zoomBadge');
  const coach = document.getElementById('coach');
  const flashLeft = document.getElementById('flash-left');
  const flashRight = document.getElementById('flash-right');

  const toolsToggleBtn = document.getElementById('toolsToggleBtn');
  const minimizeBtn = document.getElementById('minimizeBtn');

  if (toolsToggleBtn && header) {
    toolsToggleBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      wake();
      header.classList.toggle('collapsed');
    });
  }

  if (minimizeBtn && header) {
    minimizeBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      wake();
      header.classList.add('collapsed');
    });
  }

  const windowsBtn = document.getElementById('windowsBtn');
  const fullScreenBtn = document.getElementById('fullScreenBtn');
  const installBtn = document.getElementById('installBtn');
  const scanQrBtn = document.getElementById('scanQrBtn');
  const statusMsg = document.getElementById('statusMsg');

  const windowModal = document.getElementById('windowModal');
  const closeWindowModalBtn = document.getElementById('closeWindowModalBtn');
  const windowListEl = document.getElementById('windowList');

  const installModal = document.getElementById('installModal');
  const closeInstallModalBtn = document.getElementById('closeInstallModalBtn');

  const qrModal = document.getElementById('qrModal');
  const closeQrModalBtn = document.getElementById('closeQrModalBtn');
  const cameraVideo = document.getElementById('cameraVideo');

  const MAX_ZOOM = 30;
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

  // ---------------------------------------------------------------- PWA

  let deferredPrompt = null;
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
  });

  const isStandalone = window.navigator.standalone || window.matchMedia('(display-mode: standalone)').matches;
  if (installBtn && isStandalone) {
    installBtn.hidden = true;
  }

  if (installBtn) {
    installBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      wake();
      if (deferredPrompt) {
        deferredPrompt.prompt();
        deferredPrompt.userChoice.then(() => { deferredPrompt = null; });
      } else if (installModal) {
        installModal.classList.remove('hidden');
      }
    });
  }

  if (closeInstallModalBtn && installModal) {
    closeInstallModalBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      installModal.classList.add('hidden');
    });
  }

  if (installModal) {
    installModal.addEventListener('click', (e) => {
      if (e.target === installModal) installModal.classList.add('hidden');
    });
  }

  // ---------------------------------------------------------------- Manual IP Connect

  const hostInput = document.getElementById('hostInput');
  const manualConnectBtn = document.getElementById('manualConnectBtn');

  if (manualConnectBtn && hostInput) {
    manualConnectBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      let val = hostInput.value.trim();
      if (!val) return;
      if (!val.startsWith('http://') && !val.startsWith('https://')) {
        val = 'http://' + val;
      }
      if (!val.includes(':', 7)) {
        val += ':17890';
      }
      window.location.href = val;
    });
  }

  // ---------------------------------------------------------------- windows UI

  function updateWindows(list) {
    if (!Array.isArray(list) || !windowListEl) return;
    windowListEl.innerHTML = '';
    
    if (list.length === 0) {
      windowListEl.innerHTML = '<div class="window-loading">No se encontraron ventanas abiertas.</div>';
      return;
    }

    list.forEach((w) => {
      const card = document.createElement('div');
      card.className = 'window-card';
      card.innerHTML = `
        <div class="window-app-tag">${escapeHtml(w.appName || 'Aplicación')}</div>
        <div class="window-title">${escapeHtml(w.title || 'Sin título')}</div>
      `;
      card.onclick = (e) => {
        e.stopPropagation();
        send({ t: 'selectWindow', pid: w.pid, windowID: w.id, title: w.title });
        if (windowModal) windowModal.classList.add('hidden');
      };
      windowListEl.appendChild(card);
    });
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  if (windowsBtn) {
    windowsBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      wake();
      send({ t: 'requestWindows' });
      if (windowModal) windowModal.classList.remove('hidden');
    });
  }

  if (closeWindowModalBtn) {
    closeWindowModalBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (windowModal) windowModal.classList.add('hidden');
    });
  }

  if (windowModal) {
    windowModal.addEventListener('click', (e) => {
      if (e.target === windowModal) windowModal.classList.add('hidden');
    });
  }

  if (fullScreenBtn) {
    fullScreenBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      wake();
      send({ t: 'fullscreen' });
    });
  }

  let scale = 1;
  let panX = 0, panY = 0;

  function showBadge() {
    zoomBadge.textContent = scale.toFixed(1) + '×';
    zoomBadge.hidden = scale <= 1.01;
  }

  function resetZoom() {
    scale = 1;
    panX = 0;
    panY = 0;
    showBadge();
  }

  // ---------------------------------------------------------------- socket

  let ws = null;
  let retry = 400;
  let live = false;

  function connect() {
    const port = cfg.wsPort;
    const token = cfg.token;
    if (!port || port === '__WS_PORT__') return schedule();

    try {
      ws = new WebSocket(`ws://${location.hostname}:${port}`);
      ws.binaryType = 'blob';

      ws.onopen = () => {
        ws.send(JSON.stringify({ t: 'auth', token: token }));
        send({ t: 'requestWindows' });
        retry = 400;
        setLive(true);
      };

      ws.onmessage = (event) => {
        if (typeof event.data === 'string') {
          try {
            const msg = JSON.parse(event.data);
            if (msg.t === 'windows') updateWindows(msg.list);
          } catch (_) {}
        } else {
          render(event.data);
        }
      };

      ws.onclose = () => {
        setLive(false);
        if (statusMsg) statusMsg.textContent = 'Conectando con tu Mac...';
        if (placeholder) placeholder.classList.remove('hidden');
        schedule();
      };
      ws.onerror = () => { try { ws.close(); } catch (_) {} };
    } catch (_) {
      schedule();
    }
  }

  function schedule() {
    setTimeout(connect, retry);
    retry = Math.min(retry * 1.6, 3000);
  }

  function setLive(state) {
    live = state;
    dot.classList.toggle('live', state);
    if (state && !startedAt) startTimer();
  }

  function send(payload) {
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
  }

  // ---------------------------------------------------------------- frames (120Hz ProMotion)

  let natW = 0, natH = 0;
  let decoding = false;
  let pendingBlob = null;
  let latestBitmap = null;

  function render(blob) {
    pendingBlob = blob;
    if (!decoding) processDecode();
  }

  function processDecode() {
    if (decoding || !pendingBlob) return;
    const blob = pendingBlob;
    pendingBlob = null;
    decoding = true;

    createImageBitmap(blob).then((bitmap) => {
      if (latestBitmap) latestBitmap.close();
      latestBitmap = bitmap;
      send({ t: 'ack' });
    }).catch(() => {}).finally(() => {
      decoding = false;
      if (pendingBlob) {
        processDecode();
      }
    });
  }

  function tick() {
    if (latestBitmap) {
      const bitmap = latestBitmap;
      latestBitmap = null;
      if (bitmap.width !== natW || bitmap.height !== natH) {
        natW = bitmap.width;
        natH = bitmap.height;
        canvas.width = natW;
        canvas.height = natH;
        layout();
      }

      ctx.save();
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      if (scale > 1.001) {
        ctx.translate(canvas.width / 2 + panX, canvas.height / 2 + panY);
        ctx.scale(scale, scale);
        ctx.translate(-canvas.width / 2, -canvas.height / 2);
      } else {
        panX = 0;
        panY = 0;
      }

      ctx.drawImage(bitmap, 0, 0);
      ctx.restore();

      bitmap.close();
      placeholder.classList.add('hidden');
    }

    if (localLaserPoints.length > 0) {
      drawLaserOnCanvas();
    }
    requestAnimationFrame(tick);
  }

  requestAnimationFrame(tick);

  // The frame box is sized to the exact letterboxed image, so gesture maths
  // can work in element coordinates without correcting for object-fit padding.
  function layout() {
    if (!natW) return;
    // Measure the stage, not the window: on iOS the URL bar makes innerHeight
    // report a viewport that is taller than what you can actually see.
    const w = stage.clientWidth, h = stage.clientHeight;
    if (!w || !h) return;
    const fit = Math.min(w / natW, h / natH);
    frameEl.style.width = Math.round(natW * fit) + 'px';
    frameEl.style.height = Math.round(natH * fit) + 'px';
  }

  new ResizeObserver(layout).observe(stage);
  window.addEventListener('orientationchange', () => setTimeout(layout, 300));
  if (window.visualViewport) window.visualViewport.addEventListener('resize', layout);

  // ---------------------------------------------------------------- zoom

  // El zoom ya no se dibuja acá: se le pide a la app de la Mac con ⌘+, ella
  // redibuja nítida y el espejado nos devuelve el resultado. Por eso no
  // aplicamos ninguna transformación local — sería zoom sobre zoom.

  let scale = 1;
  let zoomQueued = false;

  function showBadge() {
    zoomBadge.textContent = scale.toFixed(1) + '×';
    zoomBadge.hidden = scale <= 1.01;
  }

  /** Coalesced to one message per frame. */
  function pushZoom() {
    if (zoomQueued) return;
    zoomQueued = true;
    requestAnimationFrame(() => {
      zoomQueued = false;
      send({ t: 'zoom', scale });
    });
  }

  function resetZoom() {
    scale = 1;
    showBadge();
    send({ t: 'zoomEnd' });
  }

  // ---------------------------------------------------------------- laser logic

  const laserBtn = document.getElementById('laserBtn');
  let laserActive = false;
  let localLaserPoints = [];
  let laserFrameQueued = false;
  let nextLaserPayload = null;

  if (laserBtn) {
    laserBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      wake();
      laserActive = !laserActive;
      laserBtn.classList.toggle('active', laserActive);
      if (!laserActive) {
        localLaserPoints = [];
        send({ t: 'laser', active: false });
      }
    });
  }

  function pushLaserPayload(payload) {
    nextLaserPayload = payload;
    if (!laserFrameQueued) {
      laserFrameQueued = true;
      requestAnimationFrame(() => {
        laserFrameQueued = false;
        if (nextLaserPayload) {
          send(nextLaserPayload);
          if (!nextLaserPayload.active) nextLaserPayload = null;
        }
      });
    }
  }

  function handleLaserTouch(touch, active) {
    if (!active) {
      pushLaserPayload({ t: 'laser', active: false });
      return;
    }

    const rect = frameEl.getBoundingClientRect();
    let normX = 0.5, normY = 0.5;
    if (rect.width > 0 && rect.height > 0) {
      normX = clamp((touch.clientX - rect.left) / rect.width, 0, 1);
      normY = clamp((touch.clientY - rect.top) / rect.height, 0, 1);
    } else {
      normX = touch.clientX / window.innerWidth;
      normY = touch.clientY / window.innerHeight;
    }

    localLaserPoints.push({ x: normX, y: normY, t: Date.now() });
    pushLaserPayload({ t: 'laser', active: true, x: normX, y: normY });
  }

  function drawLaserOnCanvas() {
    const now = Date.now();
    const duration = 1000;
    localLaserPoints = localLaserPoints.filter(p => now - p.t < duration);

    if (localLaserPoints.length === 0 || !canvas.width || !canvas.height) return;

    ctx.save();

    const pts = localLaserPoints.map(p => ({
      x: p.x * canvas.width,
      y: p.y * canvas.height
    }));

    // 1. Estela láser realista con curvas Bézier suaves de 3 capas
    if (pts.length > 1) {
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      ctx.beginPath();
      ctx.moveTo(pts[0].x, pts[0].y);

      if (pts.length === 2) {
        ctx.lineTo(pts[1].x, pts[1].y);
      } else {
        for (let i = 1; i < pts.length - 1; i++) {
          const midX = (pts[i].x + pts[i + 1].x) / 2;
          const midY = (pts[i].y + pts[i + 1].y) / 2;
          ctx.quadraticCurveTo(pts[i].x, pts[i].y, midX, midY);
        }
        ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
      }

      // Capa 1: Resplandor exterior (Glow aura)
      ctx.strokeStyle = 'rgba(239, 68, 68, 0.3)';
      ctx.lineWidth = 18;
      ctx.stroke();

      // Capa 2: Núcleo rojo incandescente
      ctx.strokeStyle = 'rgba(255, 40, 40, 0.9)';
      ctx.lineWidth = 8;
      ctx.stroke();

      // Capa 3: Centro blanco brillante
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
      ctx.lineWidth = 3;
      ctx.stroke();
    }

    // 2. Punto activo brillante (Cabeza del láser)
    const last = pts[pts.length - 1];
    const cx = last.x;
    const cy = last.y;

    // Resplandor exterior (Glow)
    ctx.beginPath();
    ctx.arc(cx, cy, 22, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(239, 68, 68, 0.35)';
    ctx.fill();

    // Punto rojo brillante
    ctx.beginPath();
    ctx.arc(cx, cy, 11, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255, 30, 30, 0.95)';
    ctx.fill();

    // Núcleo blanco
    ctx.beginPath();
    ctx.arc(cx, cy, 4, 0, Math.PI * 2);
    ctx.fillStyle = '#ffffff';
    ctx.fill();

    ctx.restore();
  }

  // ---------------------------------------------------------------- gestures

  const SWIPE_DISTANCE = 55;
  const TAP_SLOP = 12;
  const TAP_TIME = 350;

  for (const type of ['gesturestart', 'gesturechange', 'gestureend']) {
    document.addEventListener(type, (event) => event.preventDefault(), { passive: false });
  }

  let start = null;      // one-finger gesture origin
  let pinch = null;      // two-finger gesture origin

  function distance(a, b) {
    return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
  }

  function isInteractiveTarget(target) {
    return target.closest('#header') || target.closest('#placeholder') || target.closest('.modal') || target.closest('button');
  }

  document.addEventListener('touchstart', (event) => {
    if (isInteractiveTarget(event.target)) return;
    wake();
    if (laserActive && event.touches.length === 1) {
      event.preventDefault();
      handleLaserTouch(event.touches[0], true);
      return;
    }
    if (event.touches.length === 2) {
      event.preventDefault();
      const [a, b] = event.touches;
      pinch = { distance: distance(a, b), scale };
      start = null;
    } else if (event.touches.length === 1) {
      const touch = event.touches[0];
      start = { x: touch.clientX, y: touch.clientY, at: Date.now() };
    }
  }, { passive: false });

  document.addEventListener('touchmove', (event) => {
    if (isInteractiveTarget(event.target)) return;
    event.preventDefault();

    if (laserActive && event.touches.length === 1) {
      handleLaserTouch(event.touches[0], true);
      return;
    }

    if (pinch && event.touches.length === 2) {
      const [a, b] = event.touches;
      scale = clamp(pinch.scale * (distance(a, b) / pinch.distance), 1, MAX_ZOOM);
      if (scale <= 1.02) resetZoom();
      else showBadge();
    } else if (start && event.touches.length === 1) {
      const touch = event.touches[0];
      const dx = touch.clientX - start.x;
      const dy = touch.clientY - start.y;

      if (scale > 1.02) {
        panX += dx * 1.8;
        panY += dy * 1.8;
        start.x = touch.clientX;
        start.y = touch.clientY;
      } else if (Math.abs(dy) > 4 && Math.abs(dy) > Math.abs(dx) * 0.8) {
        send({ t: 'pan', dx: dx * 1.5, dy: dy * 2.2 });
        start.x = touch.clientX;
        start.y = touch.clientY;
      }
    }
  }, { passive: false });

  document.addEventListener('touchend', (event) => {
    if (isInteractiveTarget(event.target)) return;
    if (laserActive) {
      handleLaserTouch(null, false);
      return;
    }
    if (pinch && event.touches.length < 2) {
      if (scale <= 1.02) resetZoom();
      pinch = null;
      start = null;
      return;
    }
    if (!start) { start = null; return; }

    const touch = event.changedTouches[0];
    const dx = touch.clientX - start.x;
    const dy = touch.clientY - start.y;
    const elapsed = Date.now() - start.at;
    start = null;

    // Solo gestos de deslizamiento horizontal intencional (Swipe)
    if (Math.abs(dx) > SWIPE_DISTANCE && Math.abs(dx) > Math.abs(dy) * 1.4 && elapsed < 700) {
      advance(dx < 0 ? 'next' : 'prev');
      return;
    }
  }, { passive: true });

  function advance(direction) {
    send({ t: direction });
    // Confirm the input immediately; the new frame takes a moment to arrive.
    const target = direction === 'next' ? flashRight : flashLeft;
    target.classList.remove('pulse');
    void target.offsetWidth;
    target.classList.add('pulse');
    hideCoach();
  }

  // ---------------------------------------------------------------- chrome

  let startedAt = null;

  function startTimer() {
    startedAt = Date.now();
    setInterval(() => {
      const total = Math.floor((Date.now() - startedAt) / 1000);
      const minutes = Math.floor(total / 60);
      timerEl.textContent = `${minutes}:${String(total % 60).padStart(2, '0')}`;
    }, 1000);
  }

  timerEl.addEventListener('click', (event) => {
    event.stopPropagation();
    startedAt = Date.now();
    timerEl.textContent = '0:00';
  });
  timerEl.addEventListener('touchend', (event) => event.stopPropagation(), { passive: true });

  let fadeTimer = null;
  function wake() {
    if (bar) bar.classList.remove('faded');
    clearTimeout(fadeTimer);
    if (bar) fadeTimer = setTimeout(() => bar.classList.add('faded'), 4000);
  }

  function hideCoach() { if (coach) coach.classList.add('hidden'); }
  if (coach) setTimeout(hideCoach, 7000);

  // ---------------------------------------------------------------- screen sleep

  // Only available over HTTPS; on plain LAN http we fall back to asking once.
  async function holdScreenAwake() {
    if (!('wakeLock' in navigator)) return;
    try {
      await navigator.wakeLock.request('screen');
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') holdScreenAwake();
      });
    } catch (_) { /* not a secure context; nothing to do */ }
  }

  holdScreenAwake();
  wake();
  connect();
})();
