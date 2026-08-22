(() => {
  'use strict';

  const cfg = window.VELARIUM;
  const stage = document.getElementById('stage');
  const img = document.getElementById('screen');
  const frameEl = document.getElementById('frame');
  const placeholder = document.getElementById('placeholder');
  const dot = document.getElementById('dot');
  const bar = document.getElementById('bar');
  const timerEl = document.getElementById('timer');
  const zoomBadge = document.getElementById('zoomBadge');
  const coach = document.getElementById('coach');
  const flashLeft = document.getElementById('flash-left');
  const flashRight = document.getElementById('flash-right');

  const MAX_ZOOM = 6;
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

  // ---------------------------------------------------------------- socket

  let ws = null;
  let retry = 400;
  let live = false;

  function connect() {
    ws = new WebSocket(`ws://${location.hostname}:${cfg.wsPort}`);
    ws.binaryType = 'blob';

    ws.onopen = () => {
      ws.send(JSON.stringify({ t: 'auth', token: cfg.token }));
      retry = 400;
      setLive(true);
    };

    ws.onmessage = (event) => {
      if (typeof event.data !== 'string') render(event.data);
    };

    // Losing Wi-Fi for a second mid-talk should be invisible, so we just retry.
    ws.onclose = () => { setLive(false); schedule(); };
    ws.onerror = () => { try { ws.close(); } catch (_) {} };
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

  // ---------------------------------------------------------------- frames

  let previousURL = null;
  let natW = 0, natH = 0;

  function render(blob) {
    const url = URL.createObjectURL(blob);
    img.src = url;
    if (previousURL) URL.revokeObjectURL(previousURL);
    previousURL = url;
  }

  img.addEventListener('load', () => {
    if (img.naturalWidth !== natW || img.naturalHeight !== natH) {
      natW = img.naturalWidth;
      natH = img.naturalHeight;
      layout();
    }
    placeholder.classList.add('hidden');
  });

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
    applyTransform();
  }

  new ResizeObserver(layout).observe(stage);
  window.addEventListener('orientationchange', () => setTimeout(layout, 300));
  if (window.visualViewport) window.visualViewport.addEventListener('resize', layout);

  // ---------------------------------------------------------------- zoom

  let scale = 1;
  let fx = 0.5, fy = 0.5;   // image point held at the centre of the screen
  let zoomQueued = false;

  function shift() {
    const W = frameEl.clientWidth, H = frameEl.clientHeight;
    const maxX = W * (scale - 1) / 2;
    const maxY = H * (scale - 1) / 2;
    return {
      x: clamp((0.5 - fx) * W * scale, -maxX, maxX),
      y: clamp((0.5 - fy) * H * scale, -maxY, maxY),
    };
  }

  function applyTransform() {
    const s = shift();
    // CSS applies translate before scale, so divide out the scale factor.
    img.style.transform = `scale(${scale}) translate(${s.x / scale}px, ${s.y / scale}px)`;
    zoomBadge.textContent = scale.toFixed(1) + '×';
    zoomBadge.hidden = scale <= 1.01;
  }

  /** Element coordinates -> normalised image coordinates. */
  function toImage(ex, ey) {
    const W = frameEl.clientWidth, H = frameEl.clientHeight;
    const s = shift();
    return {
      x: (ex - W / 2 - s.x) / (scale * W) + 0.5,
      y: (ey - H / 2 - s.y) / (scale * H) + 0.5,
    };
  }

  /** Mirrors our zoom onto the projector. Coalesced to one message per frame. */
  function pushZoom() {
    if (zoomQueued) return;
    zoomQueued = true;
    requestAnimationFrame(() => {
      zoomQueued = false;
      send({ t: 'zoom', scale, x: fx, y: fy });
    });
  }

  function resetZoom() {
    scale = 1; fx = 0.5; fy = 0.5;
    applyTransform();
    send({ t: 'zoomEnd' });
  }

  // ---------------------------------------------------------------- gestures

  const SWIPE_DISTANCE = 55;
  const TAP_SLOP = 12;
  const TAP_TIME = 350;

  let start = null;      // one-finger gesture origin
  let pinch = null;      // two-finger gesture origin

  function localPoint(touch) {
    const box = frameEl.getBoundingClientRect();
    return { x: touch.clientX - box.left, y: touch.clientY - box.top };
  }

  function distance(a, b) {
    return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
  }

  document.addEventListener('touchstart', (event) => {
    wake();
    if (event.touches.length === 2) {
      const [a, b] = event.touches;
      const mid = localPoint({
        clientX: (a.clientX + b.clientX) / 2,
        clientY: (a.clientY + b.clientY) / 2,
      });
      pinch = {
        distance: distance(a, b),
        scale,
        anchor: toImage(mid.x, mid.y),
      };
      start = null;
    } else if (event.touches.length === 1) {
      const touch = event.touches[0];
      start = { x: touch.clientX, y: touch.clientY, at: Date.now(), fx, fy };
    }
  }, { passive: true });

  document.addEventListener('touchmove', (event) => {
    if (pinch && event.touches.length === 2) {
      const [a, b] = event.touches;
      const next = clamp(pinch.scale * (distance(a, b) / pinch.distance), 1, MAX_ZOOM);
      const mid = localPoint({
        clientX: (a.clientX + b.clientX) / 2,
        clientY: (a.clientY + b.clientY) / 2,
      });

      scale = next;
      // Keep the point the fingers grabbed pinned underneath them.
      const W = frameEl.clientWidth, H = frameEl.clientHeight;
      fx = 0.5 - (mid.x - W / 2 - scale * (pinch.anchor.x - 0.5) * W) / (W * scale);
      fy = 0.5 - (mid.y - H / 2 - scale * (pinch.anchor.y - 0.5) * H) / (H * scale);

      if (scale <= 1.02) { scale = 1; fx = 0.5; fy = 0.5; }
      applyTransform();
      pushZoom();

    } else if (start && scale > 1 && event.touches.length === 1) {
      // Zoomed in, so a single finger pans instead of changing slides.
      const touch = event.touches[0];
      const W = frameEl.clientWidth, H = frameEl.clientHeight;
      fx = start.fx - (touch.clientX - start.x) / (W * scale);
      fy = start.fy - (touch.clientY - start.y) / (H * scale);
      applyTransform();
      pushZoom();
    }
  }, { passive: true });

  document.addEventListener('touchend', (event) => {
    if (pinch && event.touches.length < 2) {
      if (scale <= 1.02) resetZoom();
      pinch = null;
      start = null;
      return;
    }
    if (!start || scale > 1) { start = null; return; }

    const touch = event.changedTouches[0];
    const dx = touch.clientX - start.x;
    const dy = touch.clientY - start.y;
    const elapsed = Date.now() - start.at;
    start = null;

    // A deliberate horizontal flick, not an accidental vertical drift.
    if (Math.abs(dx) > SWIPE_DISTANCE && Math.abs(dx) > Math.abs(dy) * 1.4 && elapsed < 700) {
      advance(dx < 0 ? 'next' : 'prev');
      return;
    }
    // Tapping either half is the discoverable fallback for swiping.
    if (Math.abs(dx) < TAP_SLOP && Math.abs(dy) < TAP_SLOP && elapsed < TAP_TIME) {
      advance(touch.clientX > window.innerWidth / 2 ? 'next' : 'prev');
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
    bar.classList.remove('faded');
    clearTimeout(fadeTimer);
    fadeTimer = setTimeout(() => bar.classList.add('faded'), 4000);
  }

  function hideCoach() { coach.classList.add('hidden'); }
  setTimeout(hideCoach, 7000);

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
