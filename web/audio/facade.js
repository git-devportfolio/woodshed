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
  let peaks = [];            // pics de waveform normalisés [0,1] (≈800 points)

  const backends = {};       // rempli par les fichiers backend-*.js
  window.woodshedAudioRegisterBackend = (id, factory) => { backends[id] = factory; };

  function computePeaks(buf, buckets) {
    const len = buf.length;
    const ch0 = buf.getChannelData(0);
    const ch1 = buf.numberOfChannels > 1 ? buf.getChannelData(1) : null;
    const out = new Array(buckets).fill(0);
    const block = Math.max(1, Math.floor(len / buckets));
    let maxAll = 1e-6;
    for (let b = 0; b < buckets; b++) {
      let m = 0;
      const start = b * block;
      const end = Math.min(len, start + block);
      for (let i = start; i < end; i++) {
        let v = Math.abs(ch0[i]);
        if (ch1) { const v1 = Math.abs(ch1[i]); if (v1 > v) v = v1; }
        if (v > m) m = v;
      }
      out[b] = m;
      if (m > maxAll) maxAll = m;
    }
    for (let b = 0; b < buckets; b++) out[b] = out[b] / maxAll;
    return out;
  }

  function startPolling() {
    stopPolling();
    pollTimer = setInterval(() => {
      if (backend && positionCb) positionCb(backend.positionSeconds());
    }, 100);
  }
  function stopPolling() { if (pollTimer) { clearInterval(pollTimer); pollTimer = null; } }

  // --- Encodage MP3 (lamejs, LGPL) : PCM float32 -> octets MP3 192 kbps. ---
  // Le volume N'est PAS appliqué ici : on encode l'audio traité (pitch + vitesse) tel quel.
  function floatToInt16(f32) {
    const i16 = new Int16Array(f32.length);
    for (let i = 0; i < f32.length; i++) {
      let s = Math.max(-1, Math.min(1, f32[i]));
      i16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }
    return i16;
  }
  function encodeMp3(leftF32, rightF32, sampleRate) {
    const left = floatToInt16(leftF32);
    const right = floatToInt16(rightF32);
    const enc = new window.lamejs.Mp3Encoder(2, sampleRate, 192);
    const block = 1152;
    const chunks = [];
    for (let i = 0; i < left.length; i += block) {
      const c = enc.encodeBuffer(left.subarray(i, i + block), right.subarray(i, i + block));
      if (c.length > 0) chunks.push(c);
    }
    const end = enc.flush();
    if (end.length > 0) chunks.push(end);
    let len = 0;
    for (const c of chunks) len += c.length;
    const out = new Uint8Array(len);
    let o = 0;
    for (const c of chunks) { out.set(c, o); o += c.length; }
    return out;
  }
  // Concatène des morceaux Float32 (chunks de capture) en un seul Float32Array.
  function flattenChunks(chunks) {
    let len = 0;
    for (const c of chunks) len += c.length;
    const out = new Float32Array(len);
    let o = 0;
    for (const c of chunks) { out.set(c, o); o += c.length; }
    return out;
  }

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
      peaks = computePeaks(decoded, 800);
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
    getPeaks() { return peaks; },
    get duration() { return decoded ? decoded.duration : 0; },
    onPosition(cb) { positionCb = cb; },
    // À appeler dans un geste utilisateur (iOS) pour sortir l'AudioContext de l'état suspendu.
    resume() { if (ctx && ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} } },
    // Rend le segment [fromSec, toSec] avec pitch/vitesse et encode en MP3.
    // CAPTURE TEMPS RÉEL : on rejoue le segment via le graphe temps réel qui fonctionne
    // (source -> worklet Rubber Band -> enregistreur -> gain 0 -> sortie) et on capture le PCM.
    // Un OfflineAudioContext ne convient pas : le WASM asynchrone du worklet n'y est pas prêt au
    // moment du rendu (aucun signal de disponibilité à attendre), d'où un fichier muet. Le contexte
    // réel garde le worklet actif, comme la lecture. Graphe/pitch identiques au backend 'rubberband'
    // (source.playbackRate = vitesse, tempo = 1.0, pitch = 2^(demi-tons/12) / vitesse). Volume NON
    // appliqué. Réutilise le buffer `decoded`. Durée ≈ temps réel (span / vitesse).
    async renderMp3(fromSec, toSec, pitchSemitones, speed) {
      if (!decoded) throw new Error('Aucun morceau chargé');
      const span = toSec - fromSec;
      if (!(span > 0) || !(speed > 0)) throw new Error('Plage ou vitesse invalide pour l\'export');
      const sr = ctx.sampleRate;

      // Contexte réel requis (on est dans le geste utilisateur du tap « Générer »).
      if (ctx.state === 'suspended') { try { await ctx.resume(); } catch (e) {} }
      // Stoppe la lecture live pour ne capturer que l'export.
      if (backend) backend.pause();
      stopPolling();
      // Le module worklet est déjà chargé par le backend 'rubberband' ; garde au cas où.
      try { await ctx.audioWorklet.addModule('vendor/rubberband/rubberband-processor.js'); } catch (e) {}

      const node = new AudioWorkletNode(ctx, 'rubberband-processor', {
        numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
      });
      node.port.postMessage(JSON.stringify(['quality', true]));
      node.port.postMessage(JSON.stringify(['tempo', 1.0]));
      node.port.postMessage(JSON.stringify(['pitch', Math.pow(2, pitchSemitones / 12) / speed]));

      const src = ctx.createBufferSource();
      src.buffer = decoded;
      src.playbackRate.value = speed;

      const recorder = ctx.createScriptProcessor(4096, 2, 2);
      const silent = ctx.createGain();
      silent.gain.value = 0; // n'émet rien vers les haut-parleurs pendant la capture

      const leftChunks = [];
      const rightChunks = [];
      let capturing = false;
      recorder.onaudioprocess = (e) => {
        if (!capturing) return;
        const inBuf = e.inputBuffer;
        const l = inBuf.getChannelData(0);
        const r = inBuf.numberOfChannels > 1 ? inBuf.getChannelData(1) : l;
        leftChunks.push(new Float32Array(l));
        rightChunks.push(new Float32Array(r));
      };

      src.connect(node);
      node.connect(recorder);
      recorder.connect(silent);
      silent.connect(ctx.destination);

      // Amorçage : laisse le WASM du nouveau nœud s'initialiser (contexte réel => rapide).
      await new Promise((res) => setTimeout(res, 300));

      await new Promise((resolve) => {
        src.onended = () => {
          // Laisse la queue du pitch shifter et de l'enregistreur se vider avant d'arrêter.
          setTimeout(() => { capturing = false; resolve(); }, 400);
        };
        capturing = true;
        src.start(0, fromSec, span);
      });

      // Débranchement / nettoyage.
      try { src.disconnect(); } catch (e) {}
      try { node.port.postMessage(JSON.stringify(['close'])); } catch (e) {}
      try { node.disconnect(); } catch (e) {}
      try { recorder.onaudioprocess = null; recorder.disconnect(); } catch (e) {}
      try { silent.disconnect(); } catch (e) {}

      return encodeMp3(flattenChunks(leftChunks), flattenChunks(rightChunks), sr);
    },
    dispose() { stopPolling(); if (backend) backend.dispose(); },
  };
})();
