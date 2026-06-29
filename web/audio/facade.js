// window.woodshedAudio : façade audio stable pour l'app Flutter.
// Route vers un backend interchangeable ('plain' | 'soundtouch' | 'rubberband').
(function () {
  let ctx = null;            // AudioContext
  let masterGain = null;     // gain maître (volume), entre les backends et la sortie
  let decoded = null;        // AudioBuffer décodé
  let backend = null;        // backend actif
  let backendId = 'rubberband';
  let positionCb = null;
  let pollTimer = null;
  let loopAsec = 0;          // borne A (s) ; 0 par défaut
  let loopBsec = 0;          // borne B (s) ; 0 = fin du buffer (boucle morceau entier)
  let loopOn = false;        // bouclage actif

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
      if (!ctx) {
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        masterGain = ctx.createGain();
        masterGain.connect(ctx.destination);
      }
      await this.setEngine(backendId);
    },
    async load(uint8Array) {
      console.log('[woodshedAudio] load: début, octets=' + uint8Array.byteLength + ', moteur=' + backendId);
      // decodeAudioData détache l'ArrayBuffer : on copie.
      const arrayBuffer = uint8Array.buffer.slice(
        uint8Array.byteOffset,
        uint8Array.byteOffset + uint8Array.byteLength,
      );
      // Décodage via un OfflineAudioContext : contrairement au contexte principal, il n'est
      // pas "suspendu" sur iOS, donc decodeAudioData se résout sans geste de reprise (le
      // contexte principal n'est repris qu'au Play). Évite le blocage du chargement sur iPhone.
      const OfflineCtx = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      const decodeCtx = new OfflineCtx(2, 1, ctx.sampleRate);
      decoded = await decodeCtx.decodeAudioData(arrayBuffer);
      console.log('[woodshedAudio] load: décodé, durée=' + decoded.duration.toFixed(1) + 's');
      if (backend) {
        await backend.load(decoded);
        console.log('[woodshedAudio] load: backend chargé, OK');
      } else {
        console.warn('[woodshedAudio] load: aucun backend actif au chargement');
      }
    },
    play() { if (ctx.state === 'suspended') ctx.resume(); backend && backend.play(); startPolling(); },
    pause() { backend && backend.pause(); stopPolling(); },
    seek(seconds) { backend && backend.seek(seconds); },
    setTempo(ratio) { backend && backend.setTempo(ratio); },
    setPitchSemitones(n) { backend && backend.setPitchSemitones(n); },
    setLoop(on) { loopOn = on; backend && backend.setLoop(on); },
    setLoopRange(aSec, bSec) { loopAsec = aSec; loopBsec = bSec; backend && backend.setLoopRange(aSec, bSec); },
    setVolume(v) { if (masterGain) masterGain.gain.value = v; },
    async setEngine(id) {
      const wasPlaying = backend ? backend.isPlaying() : false;
      const pos = backend ? backend.positionSeconds() : 0;
      const tempo = backend ? backend.tempo() : 1.0;
      const pitch = backend ? backend.pitchSemitones() : 0;
      if (backend) backend.dispose();
      const factory = backends[id];
      if (!factory) throw new Error('Backend inconnu: ' + id);
      backend = await factory(ctx, masterGain);
      backendId = id;
      console.log('[woodshedAudio] setEngine: moteur "' + id + '" prêt');
      if (decoded) await backend.load(decoded);
      backend.setTempo(tempo);
      backend.setPitchSemitones(pitch);
      backend.setLoopRange(loopAsec, loopBsec);
      backend.setLoop(loopOn);
      backend.seek(pos);
      if (wasPlaying) backend.play();
    },
    getGlitchCount() { return backend ? backend.glitchCount() : 0; },
    get duration() { return decoded ? decoded.duration : 0; },
    onPosition(cb) { positionCb = cb; },
    // À appeler dans un geste utilisateur (iOS) pour sortir l'AudioContext de l'état suspendu.
    resume() { if (ctx && ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} } },
    dispose() { stopPolling(); if (backend) backend.dispose(); },
  };
})();
