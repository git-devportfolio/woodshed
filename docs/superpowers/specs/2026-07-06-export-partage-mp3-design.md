# Spec — Export / partage de l'audio modifié (MP3)

> Document de conception. Date : 2026-07-06. Statut : **proposé** (en attente de revue).
> Incrément suivant du *noyau looper*, par-dessus le moteur audio partagé + la boucle A/B.
> Branche : `spike/web-audio-engine`.

## 1. Contexte & objectif

L'app retravaille un morceau (transposition, vitesse) mais tout reste **local à l'app**. L'utilisateur
veut **exporter l'audio modifié** (pitch/vitesse appliqués) en **MP3** pour l'**envoyer sur un Drive et
le partager** aux membres du groupe.

**Critère de succès** : depuis le lecteur, générer un MP3 qui sonne **exactement comme la lecture**
(mêmes pitch/vitesse), puis le **partager depuis l'iPhone** (feuille de partage → Drive) ou le
télécharger.

## 2. Périmètre

### Dans le périmètre
- Bouton **« Exporter / Partager »** dans le lecteur.
- Boîte d'export : choix **morceau entier** ou **boucle A/B** (si une boucle est définie).
- **Rendu hors-ligne** de l'audio avec le pitch/vitesse **courants** (fidèle à la lecture).
- **Encodage MP3** (~192 kbps) côté client.
- **Partage** via `navigator.share({files})` (feuille iOS) + **repli téléchargement** (`<a download>`).
- Nom de fichier explicite : `<morceau>_<pitch>_<vitesse>x.mp3`.

### Hors périmètre
Choix du bitrate dans l'UI (fixé à 192 kbps), autres formats (WAV/…), export multiple, métadonnées
ID3 riches, normalisation/mastering, export du volume (on exporte pitch+vitesse ; le volume est un
réglage d'écoute, pas appliqué au rendu).

## 3. Flux UX

1. Tap **« Exporter / Partager »** → ouvre une `ExportSheet` (bottom sheet).
2. **Choix de portée** : *Morceau entier* / *Boucle A/B* (cette dernière désactivée si aucune boucle
   n'est définie, c.-à-d. A=début & B=fin).
3. Tap **« Générer »** → **barre/roue de progression** (rendu + encodage, quelques secondes).
4. À la fin : boutons **« Partager »** et **« Télécharger »**.
   - Le partage/téléchargement est déclenché par ce **2ᵉ geste** (indispensable : iOS exige une
     activation utilisateur récente pour `navigator.share`, et le rendu prend quelques secondes).

## 4. Rendu hors-ligne (façade JS)

Nouvelle fonction façade : **`renderMp3({fromSec, toSec, pitchSemitones, speed}) → Promise<Uint8Array>`**.

1. Créer un **`OfflineAudioContext(2, ceil(outSec * sampleRate), sampleRate)`** où
   `outSec = (toSec − fromSec) / speed` (morceau entier : `fromSec=0`, `toSec=durée`).
2. **Répliquer le graphe de lecture** : `AudioBufferSourceNode` (buffer = le `decoded` courant,
   `playbackRate = speed`) → **worklet Rubber Band** (chargé dans ce contexte via `addModule`) →
   `offlineCtx.destination`. Appliquer **la même paramétrisation que le backend Rubber Band live** :
   `source.playbackRate = speed`, worklet `tempo = 1.0`, worklet `pitch = 2^(pitchSemitones/12) / speed`
   (la vitesse vient du `playbackRate`, le worklet ne fait que le pitch + compense le décalage induit)
   — rendu identique à ce qu'on entend.
3. **Attendre le message « ready » du worklet** (il le signale) avant `startRendering()` — évite un
   début muet.
4. `source.start(0, fromSec, toSec − fromSec)` (segment) ou `source.start(0)` (entier).
5. `await offlineCtx.startRendering()` → `AudioBuffer` (PCM traité).
6. Encoder en MP3 (§5) → `Uint8Array`.

**Repli** (si le rendu offline s'avère non fiable sur iOS — worklet muet) : capture **temps réel** via
un tap sur le moteur déjà chaud (plus lent). Gardé en réserve, non implémenté d'emblée.

## 5. Encodage MP3

`lamejs` (`lame.min.js` vendorisé dans `web/vendor/lamejs/`). Depuis l'`AudioBuffer` rendu :
- Récupérer les canaux (`getChannelData`), convertir Float32 [-1,1] → **Int16**.
- `new lamejs.Mp3Encoder(channels, sampleRate, 192)`, encoder par **blocs** (`encodeBuffer`), puis
  `flush()` ; concaténer les morceaux MP3 en `Uint8Array`.
- Mono ou stéréo selon le buffer.

## 6. Livraison (Dart util, `package:web`)

`shareOrDownloadFile(Uint8List bytes, String name, String mime)` :
- Construire un `File` (`[bytes] , name, {type: mime}`).
- Si `navigator.canShare({files:[file]})` → `await navigator.share({files:[file]})` (feuille iOS →
  Drive/AirDrop/Messages…).
- Sinon (desktop / non supporté) → créer un `Blob`, `URL.createObjectURL`, `<a download=name>` cliqué
  puis révoqué.

Appelé sur le **tap** des boutons « Partager » / « Télécharger » (geste utilisateur).

## 7. Nom de fichier

`sanitize(nomSansExtension)_<pitch>_<vitesse>x.mp3` où
- `pitch` = `0st` si 0, sinon `${signe}${n}st` (ex. `-2st`, `+3st`),
- `vitesse` = la valeur (ex. `0.85`),
- exemple : `Mon solo_-2st_0.85x.mp3`. `sanitize` retire l'extension d'origine et remplace les
  caractères non `[a-zA-Z0-9-_ ]` par `_`.

## 8. Architecture & fichiers

```
web/
  vendor/lamejs/lame.min.js          # NOUVEAU (vendorisé) + VENDOR.md
  audio/facade.js                    # + renderMp3({...}) : OfflineAudioContext + worklet + lamejs
  index.html                         # charge lame.min.js
lib/core/audio/
  web_audio_engine.dart              # + Future<Uint8List> exportMp3({...}) (proxy façade)
  export_naming.dart                 # NOUVEAU (pur) : nom de fichier + durée de sortie (testables)
lib/core/io/
  share_file.dart                    # NOUVEAU : shareOrDownloadFile (navigator.share + repli download)
lib/features/player/
  export_sheet.dart                  # NOUVEAU : bottom sheet (portée, générer, progression, partager/télécharger)
  player_page.dart                   # + bouton "Exporter / Partager" ouvrant l'ExportSheet
```

## 9. Tests (TDD là où c'est pur Dart)

- **`export_naming.dart`** : nom de fichier (`0st`, `-2st`, `+3st`, sanitize) et **durée de sortie**
  (`(to−from)/speed` ; entier vs segment). Round-trips et cas limites.
- Le rendu offline, l'encodage MP3, le partage = validation **manuelle sur iPhone**.

## 10. Risques (assumés)

- **Fiabilité du worklet en `OfflineAudioContext`** : atténuée par l'attente du « ready » ; repli
  temps réel documenté si besoin.
- **Temps de rendu + encodage** sur mobile (quelques s à quelques dizaines de s) → progression.
- **Mémoire** (PCM + MP3 en RAM) pour morceaux très longs — acceptable pour des morceaux usuels.
- **`navigator.share({files})`** : nécessite un geste + HTTPS (OK en PWA) ; repli download sinon.

## 11. Prochaine étape

Après validation → plan d'implémentation (`writing-plans`) puis exécution pilotée par sous-agents.
