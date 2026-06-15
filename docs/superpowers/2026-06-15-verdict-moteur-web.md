# Verdict — Spike moteur audio web (PWA)

> Date : 2026-06-15. Conclut le spike décrit dans
> `docs/superpowers/specs/2026-06-15-spike-moteur-audio-web-pwa-design.md`
> et `docs/superpowers/plans/2026-06-15-spike-moteur-audio-web.md`.
> Branche : `spike/web-audio-engine`.

## 1. Question posée

Une PWA Flutter peut-elle faire **transposition (±6 demi-tons)** et **vitesse (0.5/0.75/1.0)**
**en temps réel** sur un **iPhone (Safari)**, avec une **qualité acceptable à l'oreille** — et donc
supprimer les 20-50 s de pré-traitement de l'ancienne app Angular ?

## 2. Méthode

- Interface `AudioEngine` (Dart) → `WebAudioEngine` (proxy js_interop) → **façade JS**
  (`window.woodshedAudio`) → **backends worklet interchangeables**.
- Deux moteurs comparés **en A/B sur iPhone réel** (PWA installée, GitHub Pages) :
  - **SoundTouch** (`@soundtouchjs/audio-worklet` 2.0.4, MPL-2.0).
  - **Rubber Band** (`rubberband-web` 0.2.1, GPL-2.0-or-later).
- Montage identique pour les deux (une seule variable change : le moteur) : **vitesse via
  `AudioBufferSourceNode.playbackRate`**, le worklet ne fait **que** le pitch (compensation
  `2^(demi-tons/12) / vitesse`). Évite le problème de flux du time-stretch en insert et rend la
  comparaison équitable.

## 3. Résultats

- ✅ **Temps réel confirmé sur iPhone** : pitch et vitesse audibles instantanément, **aucune étape
  de pré-traitement**. Le problème de fond de l'ancienne app est **éliminé**.
- ✅ **Qualité — Rubber Band nettement meilleur** que SoundTouch à l'oreille, surtout sur le **cumul
  fort** (ex. +6 demi-tons & 0.5×). SoundTouch reste correct pour des décalages modérés mais se
  dégrade au cumul.
- ✅ **Architecture validée** : l'interface `AudioEngine` + façade JS + backends worklet
  interchangeables fonctionne (bascule de moteur à chaud, code Dart découplé du moteur).

## 4. Décision

- **Moteur par défaut : Rubber Band.** Objectif immédiat = **usage personnel** sur iPhone, où la
  qualité prime et la licence **GPL-2.0 ne pose aucun problème** (app non publiée/distribuée).
- **SoundTouch conservé** (sélectionnable) comme **repli publiable** : si l'app devait un jour être
  **distribuée sur un store**, il faudrait basculer sur SoundTouch (MPL-2.0) ou acquérir une
  **licence commerciale Rubber Band** — la GPL interdit la distribution sans ouvrir les sources.

## 5. Contraintes & limites relevées (à retenir pour la suite)

- **Formats iOS** : `decodeAudioData` de Safari décode **MP3, M4A/AAC, WAV, AIFF** ; **PAS
  OGG/FLAC/Opus** (limite plateforme, irréparable). Un format non décodable affiche un message.
- **Sélecteur de fichiers** (`file_picker` web) : il faut **`cancelUploadOnWindowBlur: false`**
  (sinon fausse annulation → fichier jamais reçu) et **`FileType.any`** (sinon iOS restreint au MP3).
- **Rubber Band WASM** : build **single-file** (~612 Ko, WASM embarqué), **sans `SharedArrayBuffer`**
  → fonctionne sur **GitHub Pages sans coi-serviceworker**. Bonne nouvelle pour l'hébergement.
- **Cache PWA** : le service worker Flutter sert l'ancienne version → il faut **rouvrir** (parfois
  re-installer) la PWA pour récupérer un nouveau déploiement.
- **Hors périmètre PWA** (confirmé) : lecture **écran éteint / arrière-plan** et **Media Session**
  (contrôles verrouillage/Bluetooth) **non fiables** sur iOS → le scénario **« voiture / commandes
  au volant »** reste sur la **feuille de route Android native**, pas la PWA.

## 6. État livré

PWA fonctionnelle déployée : https://git-devportfolio.github.io/woodshed/ — charger un fichier,
play/pause/restart, boucle, pitch ±6, vitesse 0.5/0.75/1.0, bascule moteur (Rubber Band par défaut,
SoundTouch et `plain` disponibles). Console de debug embarquée via `?debug`.

## 7. Suite

Le moteur est tranché → lancer la conception du **noyau looper** (nouveau cycle
brainstorming → spec → plan) : **boucle A/B**, **waveform interactive**, **volume**, **persistance**
des morceaux/réglages, UI épurée. Décider aussi de l'intégration de la branche
`spike/web-audio-engine` (PR vers `main`).
