# Vendor : lamejs

- Fichier : `lame.min.js` (encodeur MP3 pur JavaScript, ~152 Ko)
- Source : https://cdn.jsdelivr.net/npm/lamejs@1.2.1/lame.min.js
- Version : 1.2.1
- Licence : **LGPL-3.0** (port JS de LAME).
- Global exposé : `window.lamejs` (une fonction auto-appelée en fin de fichier qui
  attache ses membres statiques). Après chargement, disponibles :
  `window.lamejs.Mp3Encoder` et `window.lamejs.WavHeader`.
- Usage : `new lamejs.Mp3Encoder(channels, sampleRate, kbps)` puis
  `enc.encodeBuffer(int16Left, int16Right)` (par blocs de 1152 échantillons) et
  `enc.flush()`. Chaque appel renvoie un `Int8Array` de données MP3.

## Vérification de la recon (au vendoring)

`grep` sur le fichier vendoré confirme :
- déclaration `function lamejs(){…}` au sommet, suivie de `lamejs();` en toute fin
  (donc `window.lamejs` est peuplé au chargement du script) ;
- membres statiques `lamejs.Mp3Encoder=function(c,k,n){…}` (c=canaux, k=sampleRate,
  n=kbps) et `lamejs.WavHeader` ;
- `encodeBuffer(a,b)` (si mono, b est ignoré) et `flush()` renvoient des `Int8Array`.

On ne modifie pas le fichier vendoré.

## Pour mettre à jour

Re-télécharger `lame.min.js` à la nouvelle version et revérifier :
- le nom du global (`grep -oE "lamejs|Mp3Encoder"`) ;
- la signature du constructeur `Mp3Encoder(channels, sampleRate, kbps)` ;
- la présence de `encodeBuffer` / `flush`.
