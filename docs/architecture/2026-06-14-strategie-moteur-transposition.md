# Stratégie — Moteur de transposition / vitesse en temps réel

> Document de décision. Date : 2026-06-14. Statut : **validé** (phase 1 — moteur audio).
> Le reste de l'app (ergonomie, playlist, UI, waveform) fera l'objet d'une 2ᵉ phase de réflexion.

## 1. Contexte

`woodshed` est la **réécriture en Flutter** du module *Audio Looper* d'une app Angular existante
(`youtube-looper`). Objectif inchangé : **boucler un segment d'un fichier audio local** pour la
pratique instrumentale (guitare), avec **transposition (pitch ±6 demi-tons)**, **vitesse
(0.5x / 0.75x / 1.0x sans altérer la tonalité)**, **volume**, **boucle A/B** et **redémarrage**.

Cible finale : **application mobile native (Android d'abord)**, utilisée **en voiture** avec les
**commandes au volant**. La version web est abandonnée comme produit (uniquement confort de dev UI).

## 2. Problème à résoudre

Sur l'app Angular, transposer/ralentir un MP3 de 4 min prend **20 à 50 s**. Inacceptable.

### Diagnostic (ne pas se tromper de cause)

Le moteur de qualité (Rubber Band WASM) est **déjà le meilleur dispo côté client** — la lenteur
**n'est pas** un problème d'algorithme ni un compromis qualité/vitesse inévitable. Elle vient de
**l'architecture** :

1. Traitement en **mode « offline »** (`rubberband_new(..., options=0, ...)`) → deux passes
   complètes sur tout le fichier (*Study* 0→50 %, *Process* 50→100 %) **avant** de pouvoir jouer.
2. **Re-traitement intégral du fichier à chaque changement** de pitch/vitesse (debounce 500 ms).

➡️ La solution n'est **pas** de changer d'algo (ça dégraderait le son), mais de changer le **mode** :
passer en **traitement temps réel / streaming par blocs pendant la lecture**.

## 3. Décisions

| Sujet | Décision |
|---|---|
| Plateforme | **App mobile native Flutter, Android d'abord.** Web = dev UI uniquement. iOS plus tard (nécessite un Mac). |
| Modèle d'interaction | **Temps réel** (changement de pitch/vitesse audible instantanément pendant la lecture). Mode **hybride** (pitch en batch rapide) gardé comme filet de sécurité pour mobiles bas de gamme. |
| Moteur | **Stratégie pragmatique (« Stratégie 3 »)** : moteurs audio **intégrés à l'OS** d'abord, moteur custom C++ en **réserve**. |
| Qualité | **Validée à l'oreille sur un Android physique** (« quality spike ») dès le début du dev. C'est l'oreille qui décide si le moteur intégré suffit. |

### Pourquoi le temps réel supprime le problème

Les moteurs intégrés transforment le son **à la volée pendant la lecture** (streaming). Il n'y a
donc **plus aucune étape de pré-traitement** : on bouge le pitch/la vitesse, on entend le changement
**instantanément**. On ne « réduit » pas le temps de traitement — on le **supprime**.

## 4. Architecture

Une **interface unique** côté Dart isole le reste de l'app du choix de moteur :

```
abstract class AudioEngine {
  Future<void> load(Source source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double rate);        // 0.5 / 0.75 / 1.0 — sans altérer la tonalité
  Future<void> setPitch(double semitones);   // -6 .. +6
  Future<void> setLoop(Duration a, Duration b);
  Future<void> setVolume(double volume);     // 0..1
  Stream<Duration> get position;             // pour le curseur de la waveform
  // ...
}
```

Deux implémentations interchangeables :

1. **`NativePlayerEngine`** *(défaut, à coder en premier)* — via **`just_audio`**, qui s'appuie sur
   les moteurs intégrés : **Sonic** (Android) / **AVAudioUnitTimePitch** (iOS). Temps réel natif,
   gratuit, **aucune contrainte de licence**.
2. **`RubberBandEngine`** *(réserve)* — moteur C++ haute qualité via **`dart:ffi`**, activé
   **seulement si** l'oreille juge le moteur intégré insuffisant.
   - ⚠️ **Licence** : Rubber Band est **GPL / commercial**. Pour une app publiée sur store,
     préférer **SoundTouch (LGPL, libre)** sauf si l'écart de qualité le justifie.

### Bonus offert par le moteur intégré
Lecture, vitesse, volume, seek, **redémarrage** et **boucle A/B** sont quasi gratuits (positionnement).
Reste réellement custom : l'**affichage de la waveform** (`just_waveform` + `CustomPainter`) et,
éventuellement, une **boucle A/B sans micro-coupure** (à valider sur appareil).

## 5. Plugins retenus

| Plugin | Rôle |
|---|---|
| `just_audio` | Cœur du moteur : lecture + vitesse + pitch (moteurs OS). |
| `just_audio_background` + `audio_service` | Contrôles média OS : écran verrouillé, Bluetooth, **commandes au volant / Android Auto** (play/pause/suivant/précédent). |
| `just_waveform` | Extraction des données de waveform (rendu via `CustomPainter`). |
| `file_picker` | Sélection des fichiers audio locaux (MP3/WAV/OGG/M4A). |
| *(réserve)* `ffi` + SoundTouch | Chemin « qualité max » si nécessaire. |

## 6. Surfaces de dev / test (machine Windows)

| Surface | Teste | Limite |
|---|---|---|
| **Web (Chrome)** | UI + logique — itération rapide (hot reload) | ⚠️ Le **pitch ne marche pas** correctement sur web → **pas** un test audio valable |
| **Émulateur Android** | Build Android, intégration | ⚠️ Audio **non fiable** pour juger latence/qualité |
| **Android physique** | **Qualité audio réelle**, latence, Bluetooth voiture, commandes au volant | Indispensable avant de valider l'audio |

### Prérequis non encore satisfaits (au 2026-06-14)
- ❌ **Android SDK absent** → installer Android Studio (bloquant pour la cible Android).
- ⚠️ **Workload « Desktop C++ » de Visual Studio incomplet** → bloque le build Windows desktop.
- ❌ **iOS** : nécessite un Mac.

## 7. Étape de validation décisive (« quality spike »)

Au tout début du dev : charger un vrai MP3 de 4 min, appliquer **±6 demi-tons** et **0.5x** sur un
**Android physique**, et **juger à l'oreille**.
- Moteur intégré suffisant → on reste sur `NativePlayerEngine`.
- Insuffisant → on bascule sur le moteur custom (`RubberBandEngine` / SoundTouch).

## 8. Points ouverts (phases suivantes)

- **Ergonomie / app complète** : playlist, navigation titre suivant aux commandes au volant,
  waveform interactive, boucle A/B, UI épurée. → 2ᵉ phase de brainstorming.
- **Boucle A/B sans micro-coupure** : à valider sur appareil avec `just_audio`.
- **Pitch sur iOS** : à valider quand un Mac sera dispo (support pitch de `just_audio` plus limité sur iOS).
