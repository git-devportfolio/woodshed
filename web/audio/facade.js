// window.woodshedAudio : façade audio stable pour l'app Flutter.
// Route vers un backend interchangeable ('plain' | 'soundtouch' | 'rubberband').
(function () {
  let ctx = null;            // AudioContext
  let decoded = null;        // AudioBuffer décodé
  let backend = null;        // backend actif
  let backendId = 'plain';
  let positionCb = null;
  let pollTimer = null;

  const backends = {};       // rempli par les fichiers backend-*.js
  window.woodshedAudioRegisterBackend = (id, factory) => { backends[id] = factory; };

  function startPolling() {
    stopPolling();
    pollTimer = setInterval(() => {
      if (backend && positionCb) positionCb(backend.positionSeconds());
    }, 100);
  }
  function stopPolling() { if (pollTimer) { clearInterval(pollTimer); pollTimer = null; } }

  window.woodshedAudio = {
    async init() {
      if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
      await this.setEngine(backendId);
    },
    async load(uint8Array) {
      // decodeAudioData requiert un ArrayBuffer ; on copie pour ne pas détacher l'original.
      const arrayBuffer = uint8Array.buffer.slice(
        uint8Array.byteOffset,
        uint8Array.byteOffset + uint8Array.byteLength,
      );
      decoded = await ctx.decodeAudioData(arrayBuffer);
      if (backend) await backend.load(decoded);
    },
    play() { if (ctx.state === 'suspended') ctx.resume(); backend && backend.play(); startPolling(); },
    pause() { backend && backend.pause(); stopPolling(); },
    seek(seconds) { backend && backend.seek(seconds); },
    setTempo(ratio) { backend && backend.setTempo(ratio); },
    setPitchSemitones(n) { backend && backend.setPitchSemitones(n); },
    setLoop(loop) { backend && backend.setLoop(loop); },
    async setEngine(id) {
      const wasPlaying = backend ? backend.isPlaying() : false;
      const pos = backend ? backend.positionSeconds() : 0;
      const tempo = backend ? backend.tempo() : 1.0;
      const pitch = backend ? backend.pitchSemitones() : 0;
      if (backend) backend.dispose();
      const factory = backends[id];
      if (!factory) throw new Error('Backend inconnu: ' + id);
      backend = await factory(ctx);
      backendId = id;
      if (decoded) await backend.load(decoded);
      backend.setTempo(tempo);
      backend.setPitchSemitones(pitch);
      backend.seek(pos);
      if (wasPlaying) backend.play();
    },
    getGlitchCount() { return backend ? backend.glitchCount() : 0; },
    get duration() { return decoded ? decoded.duration : 0; },
    onPosition(cb) { positionCb = cb; },
    dispose() { stopPolling(); if (backend) backend.dispose(); },
  };
})();
