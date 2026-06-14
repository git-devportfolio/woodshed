# CLAUDE.md — woodshed

Guidance pour Claude Code sur ce dépôt.

## Vue d'ensemble

`woodshed` est une **application mobile Flutter** (Android d'abord) pour **boucler un segment d'un
fichier audio local** afin de travailler un morceau à l'instrument (guitare). Fonctions clés :
**transposition (pitch ±6 demi-tons)**, **vitesse (0.5x / 0.75x / 1.0x sans altérer la tonalité)**,
**volume**, **boucle A/B**, **redémarrage**, **waveform interactive**.

Usage premier : **en voiture**, avec les **commandes au volant** (titre suivant/précédent, play/pause).

> Réécriture du module *Audio Looper* d'une app Angular antérieure (`youtube-looper`). La partie
> YouTube **n'est pas** reprise. La version web est abandonnée comme produit (dev UI seulement).

## Décision d'architecture structurante — moteur audio

Lire en premier : **`docs/architecture/2026-06-14-strategie-moteur-transposition.md`**.

En résumé :
- **Temps réel** : pitch/vitesse modifiés pendant la lecture, audibles **instantanément**
  (plus aucune étape de pré-traitement — c'est ce qui supprime les 20-50 s de l'ancienne app).
- **Interface unique `AudioEngine`** isolant le reste de l'app du moteur concret.
- **`NativePlayerEngine`** (défaut) via `just_audio` → moteurs intégrés OS (Sonic / AVAudioUnitTimePitch).
- **`RubberBandEngine`** (réserve, `dart:ffi`) **seulement si** la qualité du moteur intégré est jugée
  insuffisante à l'oreille. Pour un store, préférer **SoundTouch (LGPL)** à Rubber Band (GPL/commercial).
- **Qualité validée à l'oreille sur un Android physique** avant toute décision moteur.

## État de l'environnement (au 2026-06-14)

- ✅ Flutter 3.44 / Dart 3.12.
- ❌ **Android SDK absent** → installer Android Studio avant de builder sur Android (cible n°1).
- ⚠️ Workload « Desktop C++ » VS incomplet → build Windows desktop indisponible.
- ❌ iOS : nécessite un Mac.
- ✅ Web (Chrome) : utilisable pour itérer l'UI, **mais pas pour tester l'audio** (pitch KO sur web).

## Commandes de dev

```bash
flutter pub get                 # dépendances
flutter run -d chrome           # preview UI rapide (PAS de test audio fiable)
flutter run -d <android>        # vrai test (nécessite SDK Android + appareil/émulateur)
flutter analyze                 # lint / analyse statique
flutter test                    # tests
flutter build apk --release     # build Android
```

## Conventions de code

- **Dart/Flutter idiomatique** ; respecter `flutter_lints` (voir `analysis_options.yaml`).
- **Clean code** : composants/widgets petits et à responsabilité unique ; logique métier hors widgets.
- **Découpage** : viser `lib/features/<feature>/` + `lib/core/` (services, moteur audio, modèles).
  Le moteur audio est derrière l'interface `AudioEngine` (cf. doc d'archi) — ne pas coupler l'UI à
  `just_audio` directement.
- **État** : commencer simple (`ValueNotifier` / `ChangeNotifier` / `provider`). Pas de sur-ingénierie.
- **Pas de backend, pas de réseau** : tout est local. Persistance éventuelle via `path_provider` /
  stockage local.
- Texte UI et commentaires en **français** ; identifiants de code en **anglais**.

## Méthodologie

- **Itératif et testable** : chaque fonctionnalité livre quelque chose d'immédiatement essayable.
- **Brainstorming → spec → plan → implémentation** (skills superpowers). On ne code pas une feature
  avant d'avoir validé son design.
- Lancer `flutter analyze` (et un run) après chaque incrément pour détecter les erreurs tôt.

## Documentation à jour des packages

Utiliser le MCP **context7** (déjà disponible) pour la doc à jour de Flutter et des packages
(`just_audio`, `just_audio_background`, `audio_service`, `just_waveform`, `file_picker`) plutôt que
de se fier à la mémoire.

## Plugins

| Plugin | Rôle |
|---|---|
| `just_audio` | Lecture + vitesse + pitch (moteurs intégrés OS). |
| `just_audio_background` + `audio_service` | Contrôles média OS / Bluetooth / **commandes au volant** / Android Auto. |
| `just_waveform` | Extraction waveform (rendu `CustomPainter`). |
| `file_picker` | Sélection de fichiers audio locaux. |
