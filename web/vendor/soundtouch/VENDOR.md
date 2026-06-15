# Vendor : @soundtouchjs/audio-worklet

- Fichier : `soundtouch-processor.js`
- Source : https://cdn.jsdelivr.net/npm/@soundtouchjs/audio-worklet@2.0.4/.dist/soundtouch-processor.js
- Version : 2.0.4
- Licence : MPL-2.0
- Processor enregistré : `soundtouch-processor` (effet d'insertion temps réel, 1:1)
- AudioParams (k-rate) : `pitch` (0.1–8, défaut 1), `pitchSemitones` (−24..24, défaut 0),
  `playbackRate` (0.1–8, défaut 1).
- Le processor calcule en interne `pipe.pitch = pitch * 2^(pitchSemitones/12) / playbackRate`
  et laisse `pipe.tempo` à 1.0 (jamais piloté → pas de time-stretch dans le worklet,
  donc pas de décalage de flux 128-samples/quantum).

## Note importante (divergence vs. recon initiale)

La recon de la tâche supposait un fichier `dist/soundtouch-worklet.js` avec les AudioParams
`rate` / `tempo` / `pitch` / `pitchSemitones`. La réalité de la v2.0.4 diffère :
- le dossier est `.dist` (et non `dist`) ;
- il n'existe pas de `soundtouch-worklet.js` : le processor est `soundtouch-processor.js` ;
- les AudioParams sont `pitch` / `pitchSemitones` / `playbackRate` (pas de `rate` ni `tempo`).

Le paramètre `playbackRate` du worklet n'est PAS un time-stretch : c'est une compensation de
hauteur. On lui transmet le `playbackRate` de l'`AudioBufferSourceNode` et le worklet annule
lui-même le décalage de hauteur dû au resampling. C'est exactement l'intention de design de la
tâche (« worklet = pitch uniquement, vitesse = playbackRate + compensation »), réalisée par le
paramètre dédié du worklet au lieu d'un calcul `pitchSemitones - 12*log2(speed)` côté JS.

## Pour mettre à jour

Re-télécharger `.dist/soundtouch-processor.js` à la nouvelle version et revérifier :
- le nom du processor (`grep registerProcessor`) ;
- les `parameterDescriptors` (noms et bornes des AudioParams) ;
- que `pipe.tempo` n'est toujours pas piloté par un AudioParam (sinon revoir la stratégie vitesse).
