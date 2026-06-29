# Spec — Boucle A/B + waveform (incrément 2 du noyau looper)

> Document de conception. Date : 2026-06-16. Statut : **proposé** (en attente de revue).
> Deuxième incrément du *noyau looper*, par-dessus la persistance (incrément 1) et le moteur audio
> partagé. Branche : `spike/web-audio-engine`.

## 1. Contexte & objectif

L'app boucle déjà la lecture d'un morceau avec pitch/vitesse/volume et bibliothèque persistée. Il
manque le cœur de la pratique : **travailler un segment précis en boucle**.

Objectif : afficher la **waveform** du morceau, y poser une **boucle A/B** (deux poignées glissables,
zone surlignée), **boucler** la lecture entre A et B, et **mémoriser** la boucle par morceau (restaurée
à la réouverture). Plus une commande **+10 s** (miroir du −10 s existant).

**Critère de succès** : poser A/B sur la waveform → la lecture boucle proprement entre les deux ;
quitter puis rouvrir le morceau → la boucle (bornes + état activé) est retrouvée.

## 2. Périmètre

### Dans le périmètre
- **Waveform** interactive (remplace le curseur de position actuel) : affichage, tête de lecture,
  **tap = seek**.
- **Poignées A et B** glissables sur la waveform ; zone [A,B] surlignée.
- **Bouclage de segment** entre A et B (moteur), activable/désactivable par un **toggle ⟲**.
- **Persistance** de la boucle par morceau (`loopA`, `loopB`, `loopEnabled`), restaurée à l'ouverture.
- **+10 s** dans la barre de transport.

### Hors périmètre
Boucles multiples, compteur de répétitions, fondu/crossfade au raccord (le `loop` natif d'un
`AudioBufferSourceNode` est déjà sans micro-coupure), édition numérique des temps A/B au clavier,
zoom sur la waveform.

## 3. Persistance (modèle)

`TrackSettings` (dans `lib/core/library/track.dart`) reçoit trois champs :
- `double? loopA` — borne A en secondes (null = non défini → 0).
- `double? loopB` — borne B en secondes (null = non défini → durée du morceau).
- `bool loopEnabled` — défaut `false`.

`toJson`/`fromJson` étendus. **Rétrocompatibilité garantie** : `TrackSettings.fromJson` tolère déjà les
clés absentes (les anciens enregistrements se chargent avec `loopEnabled=false`, A/B null). Aucun
changement de schéma IndexedDB (les réglages sont un blob JSON dans le store `tracks`). Sauvegarde en
**debounce** comme les autres réglages ; restauration via `applySettings`.

## 4. Moteur — bouclage de segment

On implémente enfin `AudioEngine.setLoopRange(Duration a, Duration b)` (lève `UnimplementedError`
aujourd'hui) et on réutilise `setLoop(bool)` comme activation.

Mécanisme (natif Web Audio) : la source `AudioBufferSourceNode` qui alimente chaque backend expose
`loopStart`, `loopEnd`, `loop`. On les pilote :
- **façade** : `setLoopRange(a, b)` et `setLoop(on)` délèguent aux backends ; l'état (a, b, on) est
  conservé côté façade et **réinjecté lors d'un changement de moteur** (comme tempo/pitch/position le
  sont déjà dans `setEngine`).
- **chaque backend** (`plain`, `soundtouch`, `rubberband`) : mémorise `loopStartSec`, `loopEndSec`,
  `loopOn` ; les applique à la source **à chaque (re)création** (`startFrom`/`seek`) et **en direct**
  si une source existe. `loopEnd = 0` signifie « fin du buffer » (boucle morceau entier par défaut).

Le bouclage est ainsi **sans micro-coupure** et indépendant de la vitesse (playbackRate) et de la
transposition (le worklet est en aval de la source).

> Note seek + boucle : si l'utilisateur seek hors de [A,B] pendant que la boucle est active, la source
> rejoue depuis la position demandée puis reboucle dès `loopEnd` atteint (comportement natif accepté).

## 5. Données de waveform

À `load`, la **façade** calcule des **pics échantillonnés** à partir du buffer **déjà décodé** (donc
zéro décodage supplémentaire) : ~**800 buckets**, chaque bucket = amplitude **max absolue** sur sa
tranche (mix mono des canaux), normalisée dans [0, 1]. Exposés à Dart (`WebAudioEngine` →
`List<double> get waveformPeaks`). Calculés à l'ouverture, **non persistés**.

## 6. UI — `PlayerPage`

La **waveform interactive remplace le `Slider` de position** (elle assure affichage + seek).

```
LECTEUR (← retour)              Titre (Hero)
 ▕▂▃▅▇█▆▄▃▂▃▅▇█▆▄▂▁▂▃▅▆▏          ← WaveformView (CustomPainter)
        A▐░░░░|playhead░░▌B       ← région [A,B] surlignée + poignées + tête de lecture
   0:42 / 3:58
   ⟲ boucle    ⟸ −10 s   ▶ / ⏸   restart   +10 s ⟹
   Pitch −6 ══|══ +6
   Vitesse [0.5] [0.75] [1.0]
   Volume ════|════
```

- **`WaveformView`** (nouveau widget `CustomPainter`) : dessine les pics, la **tête de lecture**
  (depuis le flux `position`), la **zone [A,B]** surlignée et **deux poignées** A/B.
- **Gestes** : tap sur la waveform → `seek` à la position correspondante ; **glisser une poignée** →
  met à jour A ou B (gel des mises à jour de tête pendant le drag, comme le scrubber actuel).
- **Toggle ⟲ boucle** : active/désactive le bouclage entre A et B.
- **+10 s** : bouton ajouté à la barre de transport (miroir du −10 s).
- Pendant le chargement : spinner (comme aujourd'hui), waveform affichée une fois les pics prêts.

## 7. Contrôleur

`PlayerController` reçoit :
- `setLoopA(Duration a)` / `setLoopB(Duration b)` : bornent avec un **écart minimal** `minGap = 0.2 s` —
  `setLoopA` clampe A dans `[0, B − minGap]` ; `setLoopB` clampe B dans `[A + minGap, durée]`. Mettent
  à jour `track.settings.loopA/loopB`, appellent `engine.setLoopRange`, planifient la sauvegarde,
  notifient.
- `toggleLoop()` : bascule `track.settings.loopEnabled`, appelle `engine.setLoop(enabled)`, sauvegarde,
  notifie.
- `forward10s(Duration current)` : `seek(min(current + 10 s, durée))`.
- `applySettings()` (étendu) : applique aussi `setLoopRange(loopA ?? 0, loopB ?? durée)` puis
  `setLoop(loopEnabled)`.

Getters exposés : `loopA`, `loopB`, `loopEnabled` (lus depuis `track.settings`, avec défauts 0/durée).

## 8. Tests (TDD)

Pur Dart (sans navigateur) :
- `TrackSettings` round-trip JSON **avec** `loopA/loopB/loopEnabled`, **et** rétrocompat (un JSON sans
  ces clés → `loopEnabled=false`, A/B null).
- `PlayerController` (avec fakes) : `setLoopA/B` bornent (A<B, dans [0,durée]) et délèguent à
  `engine.setLoopRange` ; `toggleLoop` bascule et appelle `engine.setLoop` ; `forward10s` borné à la
  durée ; `applySettings` réapplique la boucle.

Le rendu de la waveform, les gestes et le bouclage audible sont validés **manuellement sur iPhone**.

## 9. Découpage des fichiers (indicatif)

```
lib/
  core/library/track.dart            # + loopA, loopB, loopEnabled
  core/audio/web_audio_engine.dart   # setLoopRange réel + List<double> get waveformPeaks
  features/player/
    player_controller.dart           # + setLoopA/B, toggleLoop, forward10s, applySettings étendu
    player_page.dart                 # waveform remplace le slider + toggle boucle + +10s
    waveform_view.dart               # NOUVEAU : CustomPainter (pics + playhead + zone A/B + poignées)
web/audio/
  facade.js                          # setLoopRange + calcul/expose des pics ; setEngine réinjecte loop
  backend-plain.js / -soundtouch.js / -rubberband.js   # loopStart/loopEnd/loop sur la source
```

## 10. Risques & notes

- **Précision tactile des poignées** sur un petit segment : prévoir une zone de toucher généreuse
  autour de chaque poignée.
- **Cohérence A/B vs durée** : à l'ouverture, `loopB ?? durée` nécessite la durée (connue via
  `track.durationMs`).
- **`setEngine` doit réinjecter la boucle** (sinon basculer plain↔soundtouch↔rubberband perd A/B) —
  même motif que tempo/pitch déjà gérés.

## 11. Prochaine étape

Après validation → **plan d'implémentation** (`writing-plans`) puis exécution pilotée par sous-agents.
