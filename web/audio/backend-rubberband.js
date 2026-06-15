// Backend 'rubberband' : pitch temps réel via le worklet rubberband-web (Rubber Band, GPL),
// vitesse via AudioBufferSourceNode.playbackRate avec compensation de hauteur.
//
// Miroir EXACT du backend SoundTouch : on ne change qu'UNE variable — le moteur de pitch —
// pour une comparaison A/B propre. La vitesse vient de src.playbackRate ; Rubber Band ne fait
// QUE du pitch (tempo laissé à 1.0). On compense le décalage de hauteur dû au resampling de la
// source en divisant l'échelle de pitch par 'speed'.
//
// API réelle vérifiée (rubberband-web 0.2.1, cf. VENDOR.md) : le processor 'rubberband-processor'
// reçoit des messages JSON sur son port :
//   ['pitch', scale]   -> setPitch(scale)   (scale = ratio de fréquence, ex. 1.2)
//   ['tempo', ratio]   -> setTempo(ratio)
//   ['quality', bool]  -> haute qualité
//   ['close']          -> libère le worklet
window.woodshedAudioRegisterBackend('rubberband', async (ctx) => {
  await ctx.audioWorklet.addModule('vendor/rubberband/rubberband-processor.js');

  let node = null;
  let buffer = null, src = null, playing = false;
  let startedAt = 0;               // ctx.currentTime au démarrage de la source
  let offset = 0;                  // position (s, temps-morceau) au démarrage
  let loop = false;
  let speed = 1.0;                 // ratio de vitesse (0.5 / 0.75 / 1.0)
  let pitchSemi = 0;               // transposition (demi-tons)

  function postPitch(scale) { if (node) node.port.postMessage(JSON.stringify(['pitch', scale])); }
  function postTempo(ratio) { if (node) node.port.postMessage(JSON.stringify(['tempo', ratio])); }

  function ensureNode() {
    if (node) return;
    node = new AudioWorkletNode(ctx, 'rubberband-processor', {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
    });
    node.port.postMessage(JSON.stringify(['quality', true])); // haute qualité
    node.connect(ctx.destination);
    applyParams();
  }
  // Même montage que SoundTouch : vitesse via playbackRate ; Rubber Band ne fait QUE le pitch.
  // net pitch voulu = 2^(pitchSemi/12) ; playbackRate multiplie déjà par 'speed' => on divise.
  function applyParams() {
    if (src) src.playbackRate.value = speed;
    postTempo(1.0);
    postPitch(Math.pow(2, pitchSemi / 12) / speed);
  }
  function stopSrc() {
    if (src) { try { src.onended = null; src.stop(); } catch (e) {} src.disconnect(); src = null; }
  }
  function curPos() {
    if (!buffer) return 0;
    const p = playing ? offset + (ctx.currentTime - startedAt) * speed : offset;
    return loop && buffer.duration > 0 ? p % buffer.duration : Math.min(p, buffer.duration);
  }
  function startFrom(pos) {
    stopSrc();
    ensureNode();
    src = ctx.createBufferSource();
    src.buffer = buffer;
    src.loop = loop;
    src.connect(node);             // source -> rubberband (pitch) -> destination
    offset = pos; startedAt = ctx.currentTime;
    applyParams();
    src.start(0, pos);
    playing = true;
  }

  return {
    async load(decoded) { buffer = decoded; offset = 0; playing = false; stopSrc(); ensureNode(); },
    play() { if (ctx.state === 'suspended') ctx.resume(); if (buffer && !playing) startFrom(curPos()); },
    pause() { if (playing) { offset = curPos(); playing = false; stopSrc(); } },
    seek(s) { const wasPlaying = playing; offset = s; if (wasPlaying) startFrom(s); },
    setTempo(r) {
      if (playing) { offset = curPos(); startedAt = ctx.currentTime; }
      speed = r;
      applyParams();
    },
    setPitchSemitones(n) { pitchSemi = n; applyParams(); },
    setLoop(l) { loop = l; if (src) src.loop = l; },
    isPlaying() { return playing; },
    positionSeconds() { return curPos(); },
    tempo() { return speed; },
    pitchSemitones() { return pitchSemi; },
    glitchCount() { return 0; },
    dispose() {
      stopSrc();
      if (node) {
        try { node.port.postMessage(JSON.stringify(['close'])); } catch (e) {}
        try { node.disconnect(); } catch (e) {}
        node = null;
      }
    },
  };
});
