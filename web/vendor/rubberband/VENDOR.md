# Vendor : rubberband-web

- Fichier : `rubberband-processor.js` (worklet Emscripten single-file, WASM embarqué en base64)
- Source : https://cdn.jsdelivr.net/npm/rubberband-web@0.2.1/public/rubberband-processor.js
- Version : 0.2.1
- Licence : **GPL-2.0-or-later** — ⚠️ copyleft fort : problématique pour une publication store. Réservé à l'évaluation / usage personnel pour ce spike.
- Processor enregistré : `rubberband-processor` (effet d'insertion temps réel)
- Protocole (port.postMessage, JSON) : `["pitch", scale]`, `["tempo", ratio]`, `["quality", bool]`, `["close"]`.
- Pas de SharedArrayBuffer requis (donc pas de COOP/COEP / coi-serviceworker).

## Vérification de la recon (au vendoring)

`grep` sur le fichier vendoré confirme :
- `registerProcessor("rubberband-processor", ...)` présent ;
- handler `port.onmessage` : `var g=JSON.parse(I.data), C=g[0], Q=g[1]; switch(C){case"pitch":…setPitch(Q);case"quality":…;case"tempo":…setTempo(Q);case"close":…}` ;
- `SharedArrayBuffer` ABSENT.

Note : le handler du worklet émet un `console.log("port.onmessage", …)` à chaque message
(verbeux mais inoffensif). On ne modifie pas le fichier vendoré.

## Pour mettre à jour

Re-télécharger `public/rubberband-processor.js` à la nouvelle version et revérifier :
- le nom du processor (`grep registerProcessor`) ;
- le protocole de messages (`grep onmessage` / `JSON.parse`) ;
- l'absence de `SharedArrayBuffer` (sinon il faudra COOP/COEP + coi-serviceworker).
