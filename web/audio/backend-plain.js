window.woodshedAudioRegisterBackend('plain', async (ctx, destination) => {
  let buffer = null, src = null, playing = false;
  let startedAt = 0;      // ctx.currentTime au démarrage
  let offset = 0;         // position (s) au démarrage
  let loopStartSec = 0, loopEndSec = 0, loopOn = false;

  function stopSrc() {
    if (src) { try { src.onended = null; src.stop(); } catch (e) {} src.disconnect(); src = null; }
  }
  function curPos() {
    if (!buffer) return 0;
    const p = playing ? offset + (ctx.currentTime - startedAt) : offset;
    return loopOn && buffer.duration > 0 ? p % buffer.duration : Math.min(p, buffer.duration);
  }
  function startFrom(pos) {
    stopSrc();
    src = ctx.createBufferSource();
    src.buffer = buffer;
    src.loop = loopOn;
    src.loopStart = loopStartSec;
    src.loopEnd = loopEndSec;
    src.connect(destination);
    offset = pos; startedAt = ctx.currentTime;
    src.start(0, pos);
    playing = true;
  }

  return {
    async load(decoded) { buffer = decoded; offset = 0; playing = false; stopSrc(); },
    play() { if (buffer && !playing) startFrom(curPos()); },
    pause() { if (playing) { offset = curPos(); playing = false; stopSrc(); } },
    seek(s) { const wasPlaying = playing; offset = s; if (wasPlaying) startFrom(s); },
    setTempo(_r) { /* backend plain : non supporté (vitesse=1.0) */ },
    setPitchSemitones(_n) { /* backend plain : non supporté */ },
    setLoop(on) { loopOn = on; if (src) src.loop = on; },
    setLoopRange(a, b) { loopStartSec = a; loopEndSec = b; if (src) { src.loopStart = a; src.loopEnd = b; } },
    isPlaying() { return playing; },
    positionSeconds() { return curPos(); },
    tempo() { return 1.0; },
    pitchSemitones() { return 0; },
    glitchCount() { return 0; },
    dispose() { stopSrc(); },
  };
});
