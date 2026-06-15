# Spec — Spike moteur audio web (PWA woodshed)

> Document de conception (design). Date : 2026-06-15. Statut : **proposé** (en attente de revue).
> Étend — sans la remplacer — la décision d'archi `docs/architecture/2026-06-14-strategie-moteur-transposition.md`.

## 1. Contexte

`woodshed` cible d'abord Android (usage en voiture, commandes au volant). Mais l'auteur possède un
**iPhone sans Mac** pour compiler iOS. Pour pouvoir **utiliser l'app rapidement sur iPhone**, on
ajoute une **version PWA** (Flutter web installable « écran d'accueil »).

Obstacle vérifié : sur web, `just_audio` **n'expose pas `setPitch`**, et `setSpeed` s'appuie sur
`<audio>.playbackRate` qui **couple vitesse et tonalité** (ralentir baisse la note). Donc ni la
transposition ni le ralenti-sans-altération ne fonctionnent via `just_audio` sur web. C'est le
« pitch KO sur web » déjà signalé dans la doc d'archi.

La solution est celle de l'ancienne app Angular, mais **en temps réel** : un moteur **Web Audio API
+ AudioWorklet** avec une bibliothèque de time-stretch/pitch compilée en **WASM**.

Le **risque n°1 du projet** est la **qualité + fluidité** de ce moteur dans **Safari iOS** (artefacts,
glitches, latence). On le dé-risque par un **spike** avant de construire l'app — équivalent web du
« quality spike » Android de la doc d'archi.

## 2. Objectif & critère de succès

Construire une **mini-PWA jetable-mais-réutilisable** dont l'unique but est de **trancher le choix du
moteur web**, en jugeant **à l'oreille sur l'iPhone réel** (Safari, PWA installée) si :

- **pitch ±6 demi-tons** et **vitesse 0.5 / 0.75 / 1.0** en temps réel sonnent assez bien
  (artefacts acceptables) ;
- la lecture tourne **sans saccade / glitch** sur mobile ;
- en comparant **SoundTouch** et **Rubber Band** (dans la mesure du plafond, cf. §7).

**Succès = un verdict clair**, parmi :

1. « SoundTouch suffit » → on construira le *noyau looper* dessus.
2. « Il faut Rubber Band » → moteur web = Rubber Band (effort de build à planifier séparément).
3. « Aucun n'est assez bon sur iOS » → on repense la stratégie (ex. PWA dégradée, ou priorité Android).

Ce verdict débloque la prochaine spec : le **noyau looper** complet.

## 3. Périmètre

### Dans le périmètre
- Chargement d'un fichier audio local (`file_picker`).
- Lecture : play / pause / restart.
- Transposition : pitch −6 … +6 demi-tons.
- Vitesse : 0.5 / 0.75 / 1.0 (sans altérer la tonalité).
- Bascule de moteur à chaud (SoundTouch ↔ Rubber Band) en conservant position + pitch + vitesse.
- Lecture en boucle du morceau entier (écoute prolongée pour repérer les artefacts).
- Déploiement PWA sur GitHub Pages, installable sur iPhone.

### Hors périmètre (YAGNI — relève de la spec *noyau looper*, après le verdict)
Boucle A/B, waveform, volume in-app, persistance des réglages, Media Session / contrôles écran
verrouillé / Bluetooth, playlist, navigation titre suivant/précédent. Ainsi que tout ce qui touche
la cible Android (elle garde sa propre feuille de route).

## 4. Architecture

On **étend** l'interface `AudioEngine` de la doc d'archi (on ne la remplace pas).

- **`AudioEngine`** — l'interface de la doc d'archi, déclarée entière. Côté web, seul le
  sous-ensemble du spike est implémenté : `load`, `play`, `pause`, `seek`, `setSpeed`, `setPitch`,
  `position`.
- **`WebAudioEngine`** — implémentation **Web Audio API pure** (pas `just_audio`). Gère
  l'`AudioContext`, le décodage, le graphe audio et le suivi de position. Paramétrée par le
  *processor* (worklet) actif.
- **Deux AudioWorklet processors interchangeables** : `SoundTouchProcessor` et `RubberBandProcessor`.
- **Interop Dart ↔ JS** via `dart:js_interop` + `package:web`. Le JS des worklets et les fichiers
  `.wasm` sont des **assets statiques** servis depuis `web/`.

> `just_audio` reste **réservé au futur `NativePlayerEngine` (Android)** ; il n'intervient pas sur web.

Découpage cible des fichiers (indicatif) :

```
lib/
  core/audio/
    audio_engine.dart            # interface AudioEngine (partagée web + futur Android)
    web_audio_engine.dart        # implémentation Web Audio (interop JS)
    engine_kind.dart             # enum { soundTouch, rubberBand }
  features/spike/
    spike_page.dart              # UI minimale du spike
    spike_controller.dart        # état (ChangeNotifier/ValueNotifier) : pitch, vitesse, moteur…
web/
  worklets/
    soundtouch-processor.js
    rubberband-processor.js      # (si build dispo, cf. §7)
  wasm/                          # .wasm des moteurs
  coi-serviceworker.js           # active SharedArrayBuffer sur hébergement statique
```

## 5. Flux de données

1. `file_picker` → octets du fichier local.
2. `AudioContext.decodeAudioData(bytes)` → `AudioBuffer` (décodage **une seule fois**).
3. Samples poussés dans l'`AudioWorkletNode` actif (SoundTouch ou Rubber Band), qui applique
   pitch + tempo **en temps réel**.
4. Worklet → sortie (haut-parleur). La position est remontée par messages du worklet →
   `Stream<Duration>` Dart → UI.
5. `setPitch` / `setSpeed` → message au worklet → **effet immédiat, aucun re-décodage** (c'est tout
   l'écart avec l'ancienne app : on supprime les 20-50 s de pré-traitement).

## 6. UI (volontairement minimale)

- Bouton **Charger un morceau** (`file_picker`).
- **Play / Pause** · **Restart** (seek 0).
- Slider **Pitch −6 … +6** (pas entiers, valeur affichée).
- Boutons **Vitesse 0.5 / 0.75 / 1.0**.
- Bascule **[SoundTouch] / [Rubber Band]** (conserve position + pitch + vitesse).
- Toggle **Boucler le morceau** (écoute prolongée).
- Affichage : **position / durée**, **moteur actif**, et un **compteur de glitches** si le worklet
  peut remonter les *buffer underruns* (pour objectiver « ça saccade »).

Texte UI en français ; identifiants de code en anglais (convention projet).

## 7. Plan des moteurs & plafond Rubber Band

Ordre imposé, du plus sûr au plus risqué :

1. **SoundTouch d'abord** — via un build prêt à l'emploi et maintenu
   (`@soundtouchjs/audio-worklet`). Valide tout le pipeline : décodage → worklet → son sur iPhone.
   Pas de `SharedArrayBuffer` attendu.
2. **Porte de décision** — juger SoundTouch à l'oreille sur iPhone :
   - **Suffisant** → **verdict rendu**, Rubber Band devient optionnel (on peut s'arrêter là).
   - **Insuffisant** → on tente Rubber Band, sous plafond ci-dessous.
3. **Rubber Band — PLAFONNÉ** :
   - **Pas de compilation Emscripten maison dans cette itération.**
   - On n'intègre Rubber Band qu'avec un **build WASM existant**, dans une **boîte de temps ~2 h**.
   - Si aucun build ne s'intègre dans ce délai → **on s'arrête à SoundTouch pour cette itération**,
     on **documente le constat**, et la compilation maison devient une **tâche séparée explicitement
     planifiée** (hors spike).

Rappel licence (de la doc d'archi) : SoundTouch = **LGPL** (OK pour publication) ; Rubber Band =
**GPL/commercial** (problématique si publication un jour).

## 8. Hébergement / PWA

- Build : `flutter build web --base-href /woodshed/`.
- Publication sur **GitHub Pages** via **GitHub Actions** (HTTPS gratuit, PWA installable, reproductible).
- **COOP/COEP** : GitHub Pages ne pose pas d'en-têtes custom → `SharedArrayBuffer` désactivé par
  défaut. On ajoute le shim **`coi-serviceworker.js`** pour activer l'isolation cross-origin côté
  client (nécessaire si Rubber Band utilise les threads). **Point de vigilance** : cohabitation avec
  le **service worker généré par Flutter** (ordre d'enregistrement à valider).
- Manifest + icônes : déjà présents dans `web/` (générés par Flutter) → ajuster nom / couleur / thème.

## 9. Risques assumés

- **Build Rubber Band WASM temps-réel** : existence non garantie → traité par le plafond §7.
- **iOS Safari suspend l'`AudioContext`** quand l'app passe en arrière-plan / écran éteint (attendu,
  hors scope) → prévoir un `resume()` déclenché par un geste utilisateur ; ne pas viser l'écran éteint.
- **Cohabitation `coi-serviceworker` ↔ service worker Flutter** : à valider tôt.
- **Latence / perf temps réel sur mobile** : c'est précisément ce que le spike mesure.

## 10. Validation & tests

Le spike **est lui-même le test** : jugement à l'oreille sur appareil. En complément :

- **Tests unitaires Dart purs** (sans navigateur) sur la logique testable : conversion
  demi-tons → ratio de fréquence, machine d'état play/pause/seek, bornage du pitch à [−6, +6].
- **Checklist de validation manuelle sur iPhone** :
  - Matériel de test : un morceau **dense** (mix chargé) + un morceau **clairsemé** (voix/guitare nue).
  - Écouter à **−6**, **+6**, **0.5×**, **0.75×**, et combinaisons (−6 & 0.5×).
  - Vérifier : artefacts perçus, saccades/glitches, latence au changement de réglage, tenue sur une
    boucle longue (plusieurs minutes).
  - Comparer SoundTouch vs Rubber Band sur le **même extrait, mêmes réglages**.

L'intégration JS / Web Audio elle-même est difficilement testable hors navigateur ; on ne cherche pas
à la couvrir par des tests automatisés dans ce spike.

## 11. Prochaine étape

Après validation de cette spec → **plan d'implémentation** (skill `writing-plans`), qui ordonnancera :
mise en place de l'`AudioEngine` + `WebAudioEngine`, intégration SoundTouch, déploiement GitHub Pages,
test iPhone, puis (sous plafond) Rubber Band, et enfin la rédaction du **verdict** qui ouvrira la
spec du *noyau looper*.
