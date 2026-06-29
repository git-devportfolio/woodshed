// Backend 'soundtouch' : pitch temps réel via le worklet @soundtouchjs/audio-worklet
// (effet d'insertion 1:1, pas de time-stretch dans le worklet), vitesse via
// AudioBufferSourceNode.playbackRate avec compensation de hauteur.
//
// Décision d'archi (cf. Task 4) : on N'UTILISE PAS de time-stretch dans le worklet
// (cela provoquerait un décalage de flux car un AudioWorklet doit émettre 128 samples
// par quantum quel que soit le ratio). Le worklet ne fait QUE du pitch (1:1).
//
// API réelle vérifiée (v2.0.4) : le processor 'soundtouch-processor' expose les
// AudioParams 'pitch', 'pitchSemitones', 'playbackRate' et calcule en interne
//   pipe.pitch = pitch * 2^(pitchSemitones/12) / playbackRate
// avec pipe.tempo laissé à 1.0 (jamais piloté). On lui transmet donc le playbackRate
// de la source pour qu'il annule lui-même le décalage de hauteur dû au resampling,
// puis 'pitchSemitones' porte la transposition demandée par l'utilisateur.
// (Équivalent exact, mais sans erreur d'arrondi, à pitchSemitones - 12*log2(speed).)
window.woodshedAudioRegisterBackend('soundtouch', async (ctx, destination) => {
  await ctx.audioWorklet.addModule('vendor/soundtouch/soundtouch-processor.js');

  let node = null;                 // AudioWorkletNode 'soundtouch-processor' (pitch-shifter)
  let buffer = null, src = null, playing = false;
  let startedAt = 0;               // ctx.currentTime au démarrage de la source
  let offset = 0;                  // position (s, temps-morceau) au démarrage
  let loopStartSec = 0, loopEndSec = 0, loopOn = false;
  let speed = 1.0;                 // ratio de vitesse demandé (0.5 / 0.75 / 1.0)
  let pitchSemi = 0;               // transposition demandée (demi-tons)

  function ensureNode() {
    if (node) return;
    node = new AudioWorkletNode(ctx, 'soundtouch-processor', {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
    });
    node.connect(destination);
    applyParams();
  }
  // La vitesse vient de src.playbackRate ; le worklet ne fait QUE du pitch (mode 1:1).
  // On transmet 'playbackRate' au worklet : il compense lui-même le décalage de hauteur
  // induit par le resampling de la source, et 'pitchSemitones' applique la transposition.
  function applyParams() {
    if (src) src.playbackRate.value = speed;
    if (node) {
      node.parameters.get('playbackRate').value = speed;
      node.parameters.get('pitchSemitones').value = pitchSemi;
    }
  }
  function stopSrc() {
    if (src) { try { src.onended = null; src.stop(); } catch (e) {} src.disconnect(); src = null; }
  }
  function curPos() {
    if (!buffer) return 0;
    const p = playing ? offset + (ctx.currentTime - startedAt) * speed : offset;
    // Boucle A/B active : la position se replie dans [loopStartSec, effEnd] et
    // revient à loopStartSec en atteignant la fin de boucle (comme l'audio).
    const effEnd = loopEndSec > 0 ? loopEndSec : buffer.duration;
    if (loopOn && effEnd > loopStartSec) {
      if (p <= effEnd) return Math.min(p, buffer.duration);
      return loopStartSec + ((p - effEnd) % (effEnd - loopStartSec));
    }
    return Math.min(p, buffer.duration);
  }
  function startFrom(pos) {
    stopSrc();
    ensureNode();
    src = ctx.createBufferSource();
    src.buffer = buffer;
    src.loop = loopOn;
    src.loopStart = loopStartSec;
    src.loopEnd = loopEndSec;
    src.connect(node);             // source -> worklet (pitch) -> destination
    offset = pos; startedAt = ctx.currentTime;
    applyParams();                 // doit suivre la création de src (playbackRate)
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
    setLoop(on) { loopOn = on; if (src) src.loop = on; },
    setLoopRange(a, b) { loopStartSec = a; loopEndSec = b; if (src) { src.loopStart = a; src.loopEnd = b; } },
    isPlaying() { return playing; },
    positionSeconds() { return curPos(); },
    tempo() { return speed; },
    pitchSemitones() { return pitchSemi; },
    glitchCount() { return 0; },   // non instrumenté ; le jugement se fait à l'oreille
    dispose() { stopSrc(); if (node) { try { node.disconnect(); } catch (e) {} node = null; } },
  };
});
