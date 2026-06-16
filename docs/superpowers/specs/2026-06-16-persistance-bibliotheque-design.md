# Spec — Persistance / bibliothèque (incrément 1 du noyau looper)

> Document de conception. Date : 2026-06-16. Statut : **proposé** (en attente de revue).
> Premier incrément du *noyau looper*, par-dessus le moteur audio validé par le spike
> (`docs/superpowers/2026-06-15-verdict-moteur-web.md` : Rubber Band par défaut, interface
> `AudioEngine` + façade JS + backends worklet). Branche : `spike/web-audio-engine`.

## 1. Contexte & objectif

Sur l'iPhone, iOS ne donne pas aux apps web l'accès à la bibliothèque Musique ; les morceaux
viennent de Fichiers/iCloud/**Google Drive**, et il faut **réimporter à chaque ouverture** — pénible.

Objectif : importer un morceau **une seule fois** → il est **sauvegardé localement** (octets d'origine)
et **rechargeable d'un tap** depuis une **bibliothèque** ; chaque morceau **retient ses réglages**
(pitch / vitesse / volume), sauvegardés **automatiquement**.

**Critère de succès** : fermer puis rouvrir la PWA → mes morceaux sont toujours là, je tape l'un
d'eux, il se charge sans réimport, avec les réglages où je les avais laissés.

## 2. Périmètre

### Dans le périmètre
- Bibliothèque **multi-morceaux** persistée localement (IndexedDB).
- **Import** d'un morceau (file_picker) → ajout à la bibliothèque (octets d'origine stockés).
- **Rechargement** d'un morceau depuis la liste (zéro réimport).
- **Suppression** d'un morceau.
- **Réglages par morceau** persistés et **auto-sauvegardés** : pitch, vitesse, volume.
- **Volume** réellement implémenté dans le moteur (n'existait pas).
- Lecteur enrichi : **slider de position (scrubber)** et **bouton ⟲ −10 s**.
- Deux écrans : **Bibliothèque** → **Lecteur**.

### Hors périmètre (incréments / évolutions ultérieurs)
Boucle **A/B** (incrément suivant ; `TrackSettings` est déjà prêt à l'accueillir), **waveform**,
**renommer** un morceau (on prend le nom de fichier), **dédoublonnage** d'imports identiques (chaque
import = une entrée), impl **Android** de `LibraryRepository`, **choix du moteur par morceau** (reste
global, Rubber Band par défaut), **mémoriser la position de lecture** par morceau (le scrubber ne sert
qu'à la session courante).

## 3. Architecture — couche données isolée

La donnée est isolée derrière une interface, comme `AudioEngine` isole le moteur.

- **Modèles purs (Dart, testables) :**
  - `TrackSettings { double pitchSemitones; double speed; double volume; }` — extensible
    (recevra `loopA/loopB` à l'incrément A/B). Valeurs par défaut : pitch 0, speed 1.0, volume 1.0.
  - `Track { String id; String name; int durationMs; DateTime importedAt; TrackSettings settings; }`.
- **Interface `LibraryRepository` (pur Dart) :**
  - `Future<List<Track>> listTracks()`
  - `Future<Track> addTrack(String name, Uint8List bytes, Duration duration)`
  - `Future<Uint8List> loadAudio(String id)`
  - `Future<void> updateSettings(String id, TrackSettings settings)`
  - `Future<void> deleteTrack(String id)`
- **`IdbLibraryRepository implements LibraryRepository`** (via **`idb_shim`**) :
  - Deux object stores IndexedDB : **`tracks`** (métadonnées + réglages, JSON, petit) et **`audio`**
    (octets bruts `Uint8List`, gros), liés par `id`.
  - On stocke les **octets encodés d'origine** (MP3/M4A — quelques Mo), **re-décodés à la lecture**
    via le moteur (jamais de PCM stocké).
  - Reçoit son `IdbFactory` par injection → en prod `idbFactoryBrowser`, en test factory **mémoire**.
  - **`id`** généré via le paquet `uuid` (v4).
  - **Durée à l'import** : on l'obtient en décodant une fois les octets (cf. §4, `probeDuration`)
    avant de stocker — ainsi la liste affiche toujours la durée. (Pas de PCM conservé : seul le
    nombre est gardé.)
- **Durabilité iOS** : au démarrage, appel best-effort à `navigator.storage.persist()` ; si une
  écriture échoue (quota dépassé), message clair à l'utilisateur. (IndexedDB d'iOS peut être évincé
  sous pression de stockage ; une PWA installée est plus durable — on ne peut pas mieux garantir.)

Découpage indicatif :
```
lib/
  core/library/
    track.dart                 # modèles Track + TrackSettings (purs)
    library_repository.dart     # interface (pur Dart)
    idb_library_repository.dart # impl idb_shim
  features/library/
    library_page.dart           # écran liste + import + suppression
  features/player/
    player_controller.dart      # ex-SpikeController : repo + track, applique/sauve les réglages
    player_page.dart            # ex-SpikePage : scrubber, -10s, transport, pitch/vitesse/volume
```

## 4. Volume (addition au moteur)

Le volume n'existe pas encore. On ajoute un **`GainNode` maître dans la façade JS** : les backends se
connectent à ce gain (au lieu de `ctx.destination`), et `masterGain.connect(ctx.destination)`.
`facade.setVolume(v)` → `masterGain.gain.value = v`. Ainsi le volume est **indépendant du moteur**
(vaut pour plain/soundtouch/rubberband). Côté Dart, `WebAudioEngine.setVolume` cesse de lever
`UnimplementedError` et délègue à la façade.

On ajoute aussi à la façade une méthode **`probeDuration(bytes) → secondes`** (décode via
`decodeAudioData` et renvoie la durée, sans jouer) → exposée en Dart par
`WebAudioEngine.probeDuration`. Utilisée à l'import pour connaître la durée avant stockage.

## 5. UI / flux (deux écrans)

- **`LibraryPage`** (nouvel accueil) : liste des morceaux (nom + durée formatée), bouton **+ import**
  (sélecteur natif `pickAudioFile()` déjà construit dans `lib/core/io/audio_file_picker.dart` →
  `probeDuration` → `addTrack`), **suppression** (swipe ou appui long → confirmation). Liste vide →
  invite à importer. Tap sur un morceau → navigue vers le lecteur.
- **`PlayerPage`** (refonte de `SpikePage`) : reçoit un `Track`, charge ses octets via le repo →
  `engine.load`, **applique les réglages sauvegardés**, **auto-sauvegarde** (debounce ~500 ms) à
  chaque changement de pitch / vitesse / volume. Bouton retour → bibliothèque. Contrôles :

```
LECTEUR  (← retour)
  <nom du morceau>
  0:42 ───────●──────────────── 3:58      slider de position (scrubber)
   ⟲ −10 s     ▶ / ⏸     restart
   Pitch   −6 ══|══ +6
   Vitesse [0.5] [0.75] [1.0]
   Volume  ════|════
```
  - **Slider de position** : 0 → durée, reflète la position courante (flux `position`) ; pendant le
    glissement, un état **`scrubbing`** gèle la mise à jour auto pour ne pas lutter avec le doigt ;
    au relâchement → `seek`.
  - **Bouton ⟲ −10 s** : `seek(max(0, position − 10 s))`.
  - **Pas de bouton boucle** dans cet incrément (le bouclage = feature A/B du suivant). Le moteur
    conserve néanmoins `setLoop` en interne pour cet usage futur.
- Le `SpikeController` évolue en **`PlayerController`** : construit avec `(AudioEngine, LibraryRepository, Track)` ;
  applique les réglages du track au chargement ; sur chaque changement, met à jour `track.settings`
  et **planifie une sauvegarde debouncée** via `updateSettings`.

## 6. Tests (TDD)

- **`IdbLibraryRepository`** contre la **factory mémoire d'`idb_shim`** (pur Dart, sans navigateur) :
  `addTrack` → `listTracks` (présent) → `loadAudio` (octets identiques) → `updateSettings` (relecture
  reflète les nouveaux réglages) → `deleteTrack` (absent ensuite). Sérialisation `Track`/`TrackSettings`
  (round-trip JSON) testée.
- **`PlayerController`** avec un **`FakeLibraryRepository`** : applique les réglages au chargement ;
  un changement de pitch/vitesse/volume déclenche bien un `updateSettings` (debounce vérifié :
  plusieurs changements rapprochés → une seule sauvegarde).
- Le décodage / Web Audio / volume audible restent validés **manuellement** (navigateur / iPhone).

## 7. Risques & notes

- **Éviction IndexedDB iOS** : atténuée par `storage.persist()` + PWA installée ; non garantie à 100 %.
- **Quota** : un import volumineux peut échouer → message ; pas de gestion de quota avancée en v1.
- **Migration de schéma** : versionner la base IndexedDB (`onUpgradeNeeded`) dès le départ pour pouvoir
  ajouter `loopA/loopB` à `TrackSettings` sans casser les données existantes.
- **Sélecteur de fichier** : on utilise le `<input type="file">` natif (`pickAudioFile()`) construit
  pendant le spike ; `package:file_picker` a été abandonné sur web (fausses annulations iOS).

## 8. Prochaine étape

Après validation → **plan d'implémentation** (`writing-plans`), puis exécution. L'incrément suivant
sera la **boucle A/B** (+ waveform), qui s'appuiera sur `TrackSettings` (déjà extensible) et le scrubber.
