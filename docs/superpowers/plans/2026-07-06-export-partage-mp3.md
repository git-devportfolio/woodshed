# Export / partage MP3 — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exporter l'audio retravaillé (pitch/vitesse) en MP3 — morceau entier ou boucle A/B — et le partager depuis l'iPhone (feuille de partage → Drive) ou le télécharger.

**Architecture:** Rendu hors-ligne dans un `OfflineAudioContext` répliquant le graphe de lecture (source `playbackRate=vitesse` → worklet Rubber Band `pitch`), puis encodage MP3 client (`lamejs` vendorisé), puis livraison via `navigator.share({files})` avec repli `<a download>`. UI = bottom sheet d'export.

**Tech Stack:** Flutter web (Dart 3.12), Web Audio (`OfflineAudioContext` + AudioWorklet), `lamejs` (encodeur MP3), `package:web` (`navigator.share` / download).

**Référence spec :** `docs/superpowers/specs/2026-07-06-export-partage-mp3-design.md`

## Global Constraints

- Flutter web ; cible PWA iPhone. `flutter_lints`.
- Texte UI/commentaires **français** ; identifiants **anglais**.
- Web Audio derrière la façade JS ; UI derrière `AudioEngine`/`WebAudioEngine`.
- Bitrate MP3 fixé à **192 kbps**. **Le volume n'est PAS appliqué** au rendu (uniquement pitch+vitesse).
- Le rendu doit être **fidèle à la lecture** : `source.playbackRate = vitesse`, worklet `tempo = 1.0`,
  worklet `pitch = 2^(demi-tons/12) / vitesse`.
- Build local Windows : `MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/`.

---

## Task 1 : `export_naming.dart` — nom de fichier + durée de sortie (TDD)

**Files:**
- Create: `lib/core/audio/export_naming.dart`
- Test: `test/export_naming_test.dart`

**Interfaces:**
- Produces: `String exportFileName(String trackName, double pitchSemitones, double speed)` ;
  `double exportOutputSeconds({required double fromSec, required double toSec, required double speed})`.

- [ ] **Step 1 : Écrire les tests (échouent)**

Créer `test/export_naming_test.dart` :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed/core/audio/export_naming.dart';

void main() {
  group('exportFileName', () {
    test('pitch négatif + vitesse', () {
      expect(exportFileName('Mon solo.mp3', -2, 0.85), 'Mon solo_-2st_0.85x.mp3');
    });
    test('pitch 0 et vitesse 1.0 -> 0st et 1x', () {
      expect(exportFileName('Track', 0, 1.0), 'Track_0st_1x.mp3');
    });
    test('pitch positif + assainissement des caractères + extension retirée', () {
      expect(exportFileName('a/b:c.wav', 3, 0.5), 'a_b_c_+3st_0.5x.mp3');
    });
    test('nom vide -> audio', () {
      expect(exportFileName('', 0, 1.0), 'audio_0st_1x.mp3');
    });
  });

  group('exportOutputSeconds', () {
    test('morceau entier ralenti double la durée', () {
      expect(exportOutputSeconds(fromSec: 0, toSec: 240, speed: 0.5), 480);
    });
    test('segment à 0.75x', () {
      expect(exportOutputSeconds(fromSec: 10, toSec: 40, speed: 0.75), closeTo(40, 1e-9));
    });
    test('vitesse 1.0 conserve la durée', () {
      expect(exportOutputSeconds(fromSec: 0, toSec: 100, speed: 1.0), 100);
    });
  });
}
```

- [ ] **Step 2 : Lancer (échoue)** — `flutter test test/export_naming_test.dart` → FAIL (fichier introuvable).

- [ ] **Step 3 : Implémenter**

Créer `lib/core/audio/export_naming.dart` :
```dart
/// Nom du fichier d'export : "<morceau>_<pitch>_<vitesse>x.mp3".
/// Ex. exportFileName('Mon solo.mp3', -2, 0.85) => 'Mon solo_-2st_0.85x.mp3'.
String exportFileName(String trackName, double pitchSemitones, double speed) {
  final base = _sanitize(_stripExtension(trackName));
  final p = pitchSemitones.round();
  final pitchLabel = p == 0 ? '0st' : '${p > 0 ? '+' : ''}${p}st';
  return '${base}_${pitchLabel}_${_trimNum(speed)}x.mp3';
}

/// Durée de sortie en secondes : (toSec - fromSec) / vitesse.
double exportOutputSeconds({
  required double fromSec,
  required double toSec,
  required double speed,
}) {
  final span = toSec - fromSec;
  return speed <= 0 ? span : span / speed;
}

String _stripExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String _sanitize(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^a-zA-Z0-9\-_ ]'), '_').trim();
  return cleaned.isEmpty ? 'audio' : cleaned;
}

String _trimNum(double v) {
  var s = v.toString();
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}
```

- [ ] **Step 4 : Lancer (passe)** — `flutter test test/export_naming_test.dart` → PASS (7 tests).
- [ ] **Step 5 : Analyse** — `flutter analyze` → clean.
- [ ] **Step 6 : Commit**
```bash
git add lib/core/audio/export_naming.dart test/export_naming_test.dart
git commit -m "feat(export): nom de fichier + duree de sortie (TDD)"
```

---

## Task 2 : Rendu + encodage MP3 (façade `renderMp3` + `WebAudioEngine.exportMp3`)

But : produire les octets MP3 de l'audio traité. Validé par `flutter analyze` + `flutter build web` (rendu/encodage jugés sur appareil en Task 4).

**Files:**
- Create: `web/vendor/lamejs/lame.min.js` (vendorisé), `web/vendor/lamejs/VENDOR.md`
- Modify: `web/index.html`, `web/audio/facade.js`, `lib/core/audio/web_audio_engine.dart`

**Interfaces:**
- Consumes: variables de la façade (`ctx`, `decoded`) ; le worklet `web/vendor/rubberband/rubberband-processor.js` (processor `rubberband-processor`, messages `["quality",b]`/`["tempo",r]`/`["pitch",scale]`).
- Produces: façade `renderMp3(fromSec, toSec, pitchSemitones, speed) → Promise<Uint8Array>` ;
  `WebAudioEngine.exportMp3({required Duration from, required Duration to, required double pitchSemitones, required double speed}) → Future<Uint8List>`.

- [ ] **Step 1 : Vendoriser lamejs**
```bash
mkdir -p web/vendor/lamejs
curl -sSL -o web/vendor/lamejs/lame.min.js https://cdn.jsdelivr.net/npm/lamejs@1.2.1/lame.min.js
```
Vérifier ~150 Ko. Inspecter le global exposé : `grep -oE "lamejs|Mp3Encoder" web/vendor/lamejs/lame.min.js | sort -u | head` — le build expose `window.lamejs` avec `Mp3Encoder`. Créer `web/vendor/lamejs/VENDOR.md` (FR) : source `https://cdn.jsdelivr.net/npm/lamejs@1.2.1/lame.min.js`, version 1.2.1, licence LGPL-3.0, usage `new lamejs.Mp3Encoder(channels, sampleRate, kbps)`.

- [ ] **Step 2 : Charger lamejs dans `index.html`**

Dans `web/index.html`, avant `flutter_bootstrap.js` (après les scripts audio existants), ajouter :
```html
  <script src="vendor/lamejs/lame.min.js"></script>
```

- [ ] **Step 3 : Façade — `renderMp3` + helpers (`web/audio/facade.js`)**

Lire `facade.js`. Ajouter, dans l'IIFE, les helpers d'encodage (près des autres fonctions) :
```js
  function floatToInt16(f32) {
    const i16 = new Int16Array(f32.length);
    for (let i = 0; i < f32.length; i++) {
      let s = Math.max(-1, Math.min(1, f32[i]));
      i16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }
    return i16;
  }
  function encodeMp3(buf) {
    const sr = buf.sampleRate;
    const left = floatToInt16(buf.getChannelData(0));
    const right = buf.numberOfChannels > 1 ? floatToInt16(buf.getChannelData(1)) : left;
    const enc = new window.lamejs.Mp3Encoder(2, sr, 192);
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
```
Ajouter la méthode `renderMp3` à l'objet `window.woodshedAudio` :
```js
    async renderMp3(fromSec, toSec, pitchSemitones, speed) {
      if (!decoded) throw new Error('Aucun morceau chargé');
      const sr = (ctx && ctx.sampleRate) || 44100;
      const span = toSec - fromSec;
      const outSec = speed > 0 ? span / speed : span;
      const frames = Math.max(1, Math.ceil(outSec * sr));
      const OfflineCtx = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      const off = new OfflineCtx(2, frames, sr);
      await off.audioWorklet.addModule('vendor/rubberband/rubberband-processor.js');
      const node = new AudioWorkletNode(off, 'rubberband-processor', {
        numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
      });
      // Attendre que le worklet soit prêt (il poste un message d'état à l'init) avant de rendre,
      // sinon le début peut être muet. Filet de sécurité par timeout.
      await new Promise((resolve) => {
        let done = false;
        const finish = () => { if (!done) { done = true; resolve(); } };
        node.port.onmessage = finish;
        setTimeout(finish, 1500);
      });
      node.port.postMessage(JSON.stringify(['quality', true]));
      node.port.postMessage(JSON.stringify(['tempo', 1.0]));
      node.port.postMessage(JSON.stringify(['pitch', Math.pow(2, pitchSemitones / 12) / speed]));
      const src = off.createBufferSource();
      src.buffer = decoded;
      src.playbackRate.value = speed;
      src.connect(node);
      node.connect(off.destination);
      src.start(0, fromSec, span);
      const rendered = await off.startRendering();
      return encodeMp3(rendered);
    },
```
> ⚠️ La détection du « ready » du worklet est best-effort (1er message ou timeout 1,5 s). Le worklet
> vendorisé signale un état (« ready »/« Initialized ») — l'implémenteur peut **lire
> `web/vendor/rubberband/rubberband-processor.js`** pour attendre le message exact si besoin. À
> valider sur appareil (Task 4) : si le début est muet, allonger le warm-up / attendre le message précis.

- [ ] **Step 4 : `WebAudioEngine.exportMp3` (`lib/core/audio/web_audio_engine.dart`)**

Ajouter à l'extension type `_Facade` :
```dart
  external JSPromise<JSUint8Array> renderMp3(
      double fromSec, double toSec, double pitchSemitones, double speed);
```
Ajouter la méthode :
```dart
  /// Rend l'audio traité (pitch/vitesse courants) entre [from] et [to] et renvoie un MP3.
  Future<Uint8List> exportMp3({
    required Duration from,
    required Duration to,
    required double pitchSemitones,
    required double speed,
  }) async {
    final result = await _facade
        .renderMp3(from.inMilliseconds / 1000.0, to.inMilliseconds / 1000.0,
            pitchSemitones, speed)
        .toDart;
    return result.toDart;
  }
```
(`import 'dart:typed_data'` est déjà présent ; `JSUint8Array`/`JSPromise` via `dart:js_interop`.)

- [ ] **Step 5 : Vérifier**
```
flutter analyze            # No issues found!
flutter test               # inchangé, tout vert
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/   # succès ; lame.min.js présent dans build/web/vendor/lamejs/
```

- [ ] **Step 6 : Commit**
```bash
git add web/vendor/lamejs/ web/index.html web/audio/facade.js lib/core/audio/web_audio_engine.dart
git commit -m "feat(export): rendu hors-ligne + encodage MP3 (lamejs) -> exportMp3"
```

---

## Task 3 : Livraison + UI (`share_file`, `ExportSheet`, bouton lecteur)

But : bouton d'export → boîte (portée, générer, progression, partager/télécharger). Validé par analyze + build (UX/partage jugés sur appareil en Task 4).

**Files:**
- Create: `lib/core/io/share_file.dart`, `lib/features/player/export_sheet.dart`
- Modify: `lib/features/player/player_page.dart`

**Interfaces:**
- Consumes: `exportFileName` (Task 1) ; `WebAudioEngine.exportMp3(...)` (Task 2) ; `PlayerController` getters `pitch`/`speed`/`loopA`/`loopB` ; `Track.name`/`durationMs`.
- Produces: `Future<void> shareOrDownloadFile(Uint8List, String name, String mime)` ; `void downloadFile(Uint8List, String name, String mime)` ; widget `ExportSheet`.

- [ ] **Step 1 : `share_file.dart` (partage / téléchargement)**

Créer `lib/core/io/share_file.dart` :
```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Partage le fichier via la feuille de partage (Drive/AirDrop…) si disponible,
/// sinon le télécharge. À appeler dans un geste utilisateur (iOS).
Future<void> shareOrDownloadFile(Uint8List bytes, String name, String mime) async {
  final parts = [bytes.toJS].toJS;
  final file = web.File(parts, name, web.FilePropertyBag(type: mime));
  final data = web.ShareData(files: [file].toJS);
  final nav = web.window.navigator;
  if (nav.canShare(data)) {
    try {
      await nav.share(data).toDart;
    } catch (_) {
      // partage annulé par l'utilisateur : ne rien faire
    }
    return;
  }
  downloadFile(bytes, name, mime);
}

/// Déclenche un téléchargement du fichier (repli desktop / bouton explicite).
void downloadFile(Uint8List bytes, String name, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
```
> Vérifier à l'analyse les signatures `package:web` (`File`, `ShareData`, `canShare`, `share`,
> `Blob`, `URL`) ; adapter minimalement si une signature diffère (rapporter le changement).

- [ ] **Step 2 : `ExportSheet` (bottom sheet)**

Créer `lib/features/player/export_sheet.dart` :
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/audio/export_naming.dart';
import '../../core/audio/web_audio_engine.dart';
import '../../core/io/share_file.dart';
import '../../core/library/track.dart';
import 'player_controller.dart';

enum _Scope { whole, loop }

class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.engine,
    required this.controller,
    required this.track,
  });
  final WebAudioEngine engine;
  final PlayerController controller;
  final Track track;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  _Scope _scope = _Scope.whole;
  bool _generating = false;
  Uint8List? _mp3;
  String? _fileName;

  Duration get _total => Duration(milliseconds: widget.track.durationMs);
  bool get _hasLoop =>
      widget.controller.loopA > Duration.zero || widget.controller.loopB < _total;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _mp3 = null;
    });
    try {
      final loop = _scope == _Scope.loop;
      final from = loop ? widget.controller.loopA : Duration.zero;
      final to = loop ? widget.controller.loopB : _total;
      final pitch = widget.controller.pitch;
      final speed = widget.controller.speed;
      final bytes = await widget.engine.exportMp3(
        from: from,
        to: to,
        pitchSemitones: pitch,
        speed: speed,
      );
      if (!mounted) return;
      setState(() {
        _mp3 = bytes;
        _fileName = exportFileName(widget.track.name, pitch, speed);
      });
    } catch (e) {
      _snack('Échec de l\'export : $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kb = _mp3 == null ? 0 : (_mp3!.length / 1024).round();
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Exporter en MP3', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('Portée'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Morceau entier'),
                selected: _scope == _Scope.whole,
                onSelected: (_) => setState(() => _scope = _Scope.whole),
              ),
              ChoiceChip(
                label: const Text('Boucle A/B'),
                selected: _scope == _Scope.loop,
                onSelected:
                    _hasLoop ? (_) => setState(() => _scope = _Scope.loop) : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.graphic_eq),
            label: Text(_generating ? 'Génération…' : 'Générer le MP3'),
          ),
          if (_mp3 != null) ...[
            const SizedBox(height: 16),
            Text('$_fileName · $kb Ko', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => shareOrDownloadFile(_mp3!, _fileName!, 'audio/mpeg'),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Partager'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => downloadFile(_mp3!, _fileName!, 'audio/mpeg'),
                    icon: const Icon(Icons.download),
                    label: const Text('Télécharger'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 3 : Bouton d'export dans `PlayerPage` (`lib/features/player/player_page.dart`)**

Lire `player_page.dart`. Ajouter l'import `import 'export_sheet.dart';`. Ajouter une action dans l'`AppBar` (à côté du titre Hero) :
```dart
      appBar: AppBar(
        title: Hero(
          tag: 'track-title-${widget.track.id}',
          child: Material(
            type: MaterialType.transparency,
            child: Text(widget.track.name),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Exporter / Partager',
            icon: const Icon(Icons.ios_share),
            onPressed: _loading
                ? null
                : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ExportSheet(
                        engine: widget.engine,
                        controller: _c,
                        track: widget.track,
                      ),
                    ),
          ),
        ],
      ),
```
(Conserver le reste de l'AppBar/build inchangé.)

- [ ] **Step 4 : Vérifier**
```
flutter analyze            # No issues found!
flutter test               # inchangé, tout vert
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /woodshed/   # succès
```

- [ ] **Step 5 : Commit**
```bash
git add lib/core/io/share_file.dart lib/features/player/export_sheet.dart lib/features/player/player_page.dart
git commit -m "feat(export): bottom sheet d'export + partage/telechargement + bouton lecteur"
```

---

## Task 4 : Validation sur appareil (manuelle)

Après déploiement (push → GitHub Pages), sur iPhone (cache PWA vidé) :
- [ ] Ouvrir un morceau, régler pitch/vitesse → **Exporter / Partager** (AppBar).
- [ ] **Morceau entier** → « Générer » → le MP3 se génère (progression), sans **début muet**.
- [ ] **Partager** → la feuille iOS s'ouvre → enregistrer sur **Drive** ; le fichier lu ailleurs sonne **comme dans l'app** (pitch/vitesse appliqués).
- [ ] Avec une **boucle A/B** définie → portée « Boucle A/B » → l'export ne contient que [A,B].
- [ ] Vérifier le **nom de fichier** (ex. `Mon solo_-2st_0.85x.mp3`).
- [ ] Sur desktop (Chrome) : « Télécharger » enregistre le MP3.

Si le début est muet → ajuster l'attente « ready » du worklet (Task 2 Step 3). Sinon l'incrément est livré.

---

## Notes d'exécution

- **Testé automatiquement** : `export_naming` (nom + durée). Le rendu offline, l'encodage MP3, le
  partage = validation **manuelle** (Task 4) — non testables hors navigateur.
- **Décodage** : `renderMp3` réutilise le buffer `decoded` déjà en mémoire (aucun re-décodage).
- **Fidélité** : mêmes formules pitch/vitesse que le backend Rubber Band live (cf. Global Constraints).
- **Repli** (spec §4) : si le rendu offline est muet malgré le warm-up, basculer sur une capture temps
  réel — hors périmètre de ce plan, à rouvrir si Task 4 l'exige.
