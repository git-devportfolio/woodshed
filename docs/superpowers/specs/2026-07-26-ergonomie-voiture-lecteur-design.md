# Spec — Ergonomie voiture de l'écran lecteur (typographie + cibles tactiles)

> Document de conception. Date : 2026-07-26. Statut : **proposé** (en attente de revue).
> Lot purement présentation, par-dessus le lecteur existant (boucle A/B, export MP3).
> Branche : `spike/web-audio-engine`.

## 1. Contexte & objectif

L'écran lecteur a été construit en itérant sur la fonctionnalité, avec les tailles de contrôles par
défaut de Material. À l'usage **en voiture** — l'usage premier de l'app — ces cibles sont trop
petites et trop serrées : on ne touche pas le bon bouton sans regarder précisément l'écran.

**Critère de succès** : dans la voiture, atteindre play/pause, ±10 s et redémarrage **du premier
coup**, sans viser, et lire pitch et vitesse **d'un coup d'œil** — le tout **sans jamais scroller**.

Le lot ne change **aucun comportement audio** : ni moteur, ni `PlayerController`, ni persistance.

## 2. Périmètre

### Dans le périmètre
- **Police Inter** embarquée, appliquée à toute l'application.
- **Agrandissement du bloc transport** (−10 s, play/pause, +10 s, redémarrer) et affirmation de
  play/pause comme élément dominant.
- **Agrandissement du stepper de pitch** (boutons ± et valeur).
- **Vitesse** : suppression du `0.5x`, agrandissement des quatre restants, **une seule ligne garantie
  par construction**.
- **Layout tenant sans scroll** sur les cibles réelles, avec filet anti-débordement.
- **Extraction** des trois blocs de contrôles en widgets dédiés et testables.

### Hors périmètre
Thème sombre et confort nocturne (décision explicite : lot séparé si le besoin se confirme à
l'usage) ; palette de couleurs (inchangée) ; `WaveformView` (hors sa hauteur, déjà paramétrable) ;
ligne temps + boucle A–B ; slider de volume ; `ExportSheet` ; `LibraryPage` (qui hérite seulement de
la police) ; logique métier et moteur audio ; layout paysage dédié.

## 3. Décisions de conception

| Sujet | Décision | Raison |
|---|---|---|
| Cible ergonomique | Usage **voiture** | Écran manipulé à l'arrêt ou au feu rouge, commandes au volant pour le reste. Impose de gros contrôles, un contraste net et zéro scroll. |
| Police | **Inter embarquée** dans `assets/fonts/` | Rendu identique partout et **garanti hors réseau** (précache du service worker), contrairement à `google_fonts` dont le premier lancement offline retombe sur la police système. |
| Poids de police | **Deux statiques** (400 + 600), pas la variable | Flutter pilote mal les axes variables ; deux poids statiques sont prévisibles pour ~2 × 110 Ko. |
| Thème | **Clair uniquement, palette inchangée** | Le confort nocturne est un besoin distinct, non encore confirmé à l'usage. Garde ce lot petit et vérifiable à l'œil. |
| Vitesses | **0.75 / 0.85 / 0.95 / 1x** | Le `0.5x` est retiré comme demandé. Conséquence assumée : plus aucun palier sous 0.75 pour déchiffrer un passage rapide. |
| Une seule ligne | `Row` d'`Expanded`, **plus aucun `Wrap`** | Le retour à la ligne devient structurellement impossible, au lieu de dépendre de la largeur disponible. |
| Position des labels | **Au-dessus** des contrôles pour pitch, vitesse, volume | La ligne pitch actuelle (`label + [−] + valeur + [+]`) atteint ~330 px et déborderait sur un écran de 320 px avec des boutons à 64 px. Harmonise en prime les trois blocs de réglage. |

## 4. Typographie

`assets/fonts/` (nouveau) reçoit :

```
assets/fonts/Inter-Regular.ttf      # poids 400
assets/fonts/Inter-SemiBold.ttf     # poids 600
assets/fonts/OFL.txt                # licence Open Font License 1.1 (Inter)
```

Source : releases officielles d'Inter (`github.com/rsms/inter`, dossier `extras/ttf/`). Le
téléchargement est une **étape d'implémentation nécessitant un accès réseau**, à autoriser au moment
voulu. Inter étant sous OFL 1.1, le texte de licence accompagne les fichiers.

Déclaration `pubspec.yaml` :

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
```

`lib/core/theme/app_theme.dart` (nouveau) expose un unique `ThemeData` :

```dart
ThemeData buildWoodshedTheme() => ThemeData(
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    );
```

Le `ColorScheme` est repris **à l'identique** de `main.dart` : la palette violet pastel ne change
pas. Le thème ne redéfinit **pas** le `TextTheme` ; les tailles particulières restent locales aux
widgets qui les portent, ce qui évite d'affecter des écrans hors périmètre. `main.dart` appelle
`buildWoodshedTheme()`.

## 5. Métriques

Constantes portées par les widgets concernés (privées, `static const`) :

| Bloc | Métrique | Valeur |
|---|---|---|
| Transport | hauteur du bouton | 76 px |
| Transport | écart entre boutons | 12 px |
| Transport | rayon des coins | 20 px |
| Transport | icône play/pause | 48 px |
| Transport | icônes saut / redémarrage | 34 px |
| Pitch | bouton ± | 64 × 64 px |
| Pitch | icône ± | 32 px |
| Pitch | largeur figée de la valeur | 72 px |
| Pitch | taille / poids de la valeur | 36 px / w600 |
| Vitesse | hauteur du bouton | 56 px |
| Vitesse | écart entre boutons | 8 px |
| Vitesse | rayon des coins | 16 px |
| Labels de section | taille / poids | 16 px / w600 |

Toutes les cibles tactiles dépassent largement le minimum de 44 px des recommandations Apple : 76 px
pour le transport, 64 px pour le pitch, 56 px pour la vitesse.

## 6. Composants

### 6.1 `TransportBar`

```dart
TransportBar({
  required bool isPlaying,
  required VoidCallback onRewind,
  required VoidCallback onPlayPause,
  required VoidCallback onForward,
  required VoidCallback onRestart,
})
```

`Row` de quatre `Expanded` séparés par 12 px, chaque bouton à 76 px de haut :

| Position | Bouton | Style | Icône |
|---|---|---|---|
| 1 | −10 s | `FilledButton.tonal` (lavande) | `Icons.replay_10` — 34 px |
| 2 | **Play / Pause** | **`FilledButton`** (`primary` plein) | `Icons.play_arrow` / `Icons.pause` — **48 px** |
| 3 | +10 s | `FilledButton.tonal` | `Icons.forward_10` — 34 px |
| 4 | Redémarrer | `FilledButton.tonal` | `Icons.replay` — 34 px |

Les quatre conteneurs ont la **même taille** ; la dominance de play/pause vient du remplissage en
couleur d'accent et de son icône nettement plus grande. Chaque bouton reçoit
`style: FilledButton.styleFrom(minimumSize: Size.fromHeight(76), padding: EdgeInsets.zero, shape:
RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))` et reste enveloppé d'un `Tooltip`
comme aujourd'hui.

`Icons.replay_10` et `Icons.forward_10` portent déjà le chiffre gravé dans le glyphe : le besoin
« icône de saut avec le numéro » est couvert sans texte séparé. L'ordre des quatre boutons est
inchangé par rapport à l'existant.

### 6.2 `PitchStepper`

```dart
PitchStepper({
  required double pitch,          // −6 .. +6
  required ValueChanged<double> onChanged,
})
```

Label `Pitch (demi-tons)` **au-dessus**, puis une ligne centrée : `[−]` — valeur — `[+]`.

- Boutons : `IconButton.filledTonal`, `minimumSize: Size(64, 64)`, icône 32 px.
- Valeur : `SizedBox(width: 72)` pour que le layout ne bouge pas entre `0` et `−6`, texte 36 px w600.
- Format existant conservé : `0`, `+3`, `−2` (signe moins typographique U+2212).
- Bornes : le bouton `−` est **désactivé** à `pitch == -6`, le `+` à `pitch == 6`. Le widget émet une
  valeur déjà bornée ; il ne connaît pas le contrôleur.

### 6.3 `SpeedSelector`

```dart
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({required this.speed, required this.onChanged});
  static const speeds = <double>[0.75, 0.85, 0.95, 1.0];
  final double speed;
  final ValueChanged<double> onChanged;
}
```

Label `Vitesse` au-dessus, puis un `Row` de quatre `Expanded` séparés par 8 px, hauteur 56 px :

- Valeur sélectionnée → `FilledButton` (violet plein, `onPrimary`).
- Autres → `FilledButton.tonal` (lavande).
- Libellés : `0.75x`, `0.85x`, `0.95x`, **`1x`** (et non `1.0x`).

Écart assumé avec la demande initiale : les `Expanded` occupent **toute** la largeur au lieu de
centrer un groupe plus étroit. En voiture, quatre cibles de ~80 px valent mieux qu'un bloc centré
laissant des marges perdues ; le résultat reste symétrique.

## 7. Layout — tenir sans scroll

Un `LayoutBuilder` **placé dans le `body`** calcule la hauteur de la waveform. La contrainte qu'il
reçoit exclut déjà l'`AppBar`, donc la constante soustraite ne compte que les blocs du `body` :

```dart
// _fixedBodyHeight = 466 : tout le body sauf la waveform
final waveformHeight = (constraints.maxHeight - _fixedBodyHeight).clamp(96.0, 180.0);
```

| Élément du `body` | Hauteur |
|---|---|
| Padding vertical (2 × 16) | 32 |
| Ligne temps + Boucle A–B + reset (hauteur **forcée** à 56, cf. ci-dessous) | 56 |
| Transport | 76 |
| Pitch (label 22 + écart 8 + boutons 64) | 94 |
| Vitesse (label 22 + écart 8 + boutons 56) | 86 |
| Volume (label 22 + slider 48) | 70 |
| Écarts inter-blocs : ligne temps→transport 12, transport→pitch 16, pitch→vitesse 12, vitesse→volume 12 | 52 |
| **`_fixedBodyHeight`** | **466** |

La waveform est suivie directement du `Row` temps/boucle, sans écart dédié — comme aujourd'hui. Ce
`Row` voit sa hauteur **explicitement fixée à 56 px** (`SizedBox`), sans quoi la constante ne
correspondrait pas au rendu réel. Écran complet requis : 466 + 56 d'`AppBar` + 96 de waveform
minimale = **618 px**.

Comportement attendu (hauteur du `body` = hauteur utile de l'écran − 56 d'`AppBar`) :

| Contexte | Écran utile | `body` | Waveform | Scroll |
|---|---|---|---|---|
| PWA installée, iPhone 14 | ~763 px | ~707 px | 180 px | non |
| Safari avec barres | ~663 px | ~607 px | 141 px | non |
| iPhone SE portrait | ~548 px | ~492 px | 96 px | oui (déficit ~70 px) |
| Paysage | ~340 px | ~284 px | 96 px | oui |

Un `SingleChildScrollView` enveloppe la colonne et sert de **filet** : il ne défile que si le contenu
ne tient pas. L'objectif « zéro scroll » est donc tenu sur les cibles réelles, et les cas dégradés
dégradent proprement au lieu d'afficher un bandeau d'overflow.

La waveform reçoit sa hauteur via le paramètre `height` que `WaveformView` expose déjà (défaut 120) —
aucune modification de ce widget.

## 8. Architecture & fichiers

```
assets/fonts/
  Inter-Regular.ttf                  # NOUVEAU (400)
  Inter-SemiBold.ttf                 # NOUVEAU (600)
  OFL.txt                            # NOUVEAU (licence)
pubspec.yaml                         # + déclaration de la famille Inter
lib/core/theme/
  app_theme.dart                     # NOUVEAU : buildWoodshedTheme() (fontFamily + colorScheme)
lib/main.dart                        # utilise buildWoodshedTheme()
lib/features/player/
  player_page.dart                   # 240 -> ~110 lignes : composition + LayoutBuilder
  widgets/transport_bar.dart         # NOUVEAU
  widgets/pitch_stepper.dart         # NOUVEAU
  widgets/speed_selector.dart        # NOUVEAU
  widgets/section_label.dart         # NOUVEAU : libellé de bloc (16 px w600), partagé
test/core/theme/
  app_theme_test.dart                # NOUVEAU
test/features/player/
  transport_bar_test.dart            # NOUVEAU
  pitch_stepper_test.dart            # NOUVEAU
  speed_selector_test.dart           # NOUVEAU
```

`section_label.dart` évite de répéter trois fois le même style de libellé (pitch, vitesse, volume) —
c'est la seule pièce partagée entre les widgets extraits.

L'extraction sert deux buts au-delà de la propreté. D'abord `player_page.dart`, déjà à 240 lignes et
sur une trajectoire croissante, redevient lisible d'un coup d'œil. Ensuite — et c'est le point
décisif — `PlayerPage` reçoit un `WebAudioEngine` concret, dépendant de `package:web`, donc
**non testable** sur la VM Dart ; les trois widgets extraits ne reçoivent que des valeurs primitives
et des callbacks, et deviennent les **premiers widgets testables** du projet.

## 9. Tests

Un test unitaire sur le thème, et trois tests widget rendus possibles précisément par l'extraction :

- **`app_theme_test.dart`** : la typographie du thème porte bien la famille `Inter` ; la palette reste
  celle de la graine `deepPurple` ; le thème reste en `Brightness.light`. Ce test ne garantit pas que
  les `.ttf` sont présents — Flutter se rabat silencieusement sur la police système —, d'où la
  vérification visuelle explicite au moment de l'implémentation.


- **`speed_selector_test.dart`** : expose exactement 4 boutons ; **aucun libellé `0.5`** ; le tap
  remonte la valeur attendue via `onChanged` ; la valeur courante porte l'état sélectionné (et une
  seule) ; `1x` s'affiche `1x` et non `1.0x`.
- **`transport_bar_test.dart`** : les quatre callbacks sont déclenchés par leur bouton respectif ;
  l'icône bascule entre `play_arrow` et `pause` selon `isPlaying` ; **aucun débordement** à 320 px de
  large (un `RenderFlex overflow` fait échouer le test automatiquement).
- **`pitch_stepper_test.dart`** : bouton `−` désactivé à −6 et `+` désactivé à +6 ; les valeurs
  émises sont bornées ; le formatage `0` / `+3` / `−2` est correct ; la largeur du bloc valeur est
  **identique** entre `0` et `−6`.

Puis `flutter analyze`, `flutter test`, et un run réel sur iPhone. La vérification qui compte
vraiment ici est **à l'œil, dans la voiture** — aucun test automatisé ne dira si les boutons sont
assez gros pour être touchés sans regarder.

## 10. Risques (assumés)

- **Perte du 0.5x** : plus aucun palier sous 0.75 pour déchiffrer un passage très rapide. Choix
  explicite ; réintroduire une valeur lente si le manque se fait sentir à la pratique.
- **Bundle +220 Ko** pour Inter. Acceptable ; réductible par subset latin (~40 Ko/poids) si le
  premier chargement de la PWA devient gênant.
- **Waveform à 96 px** sur petit écran : le pointage fin de A/B y devient plus délicat. Les poignées
  A/B ont été élargies récemment (commit `cf127ce`), ce qui limite la gêne.
- **Tailles calibrées sur le papier** : les 76 / 64 / 56 px viennent d'un calcul de place, pas d'un
  essai. Un ajustement après le premier trajet réel est à prévoir — d'où des constantes regroupées
  en tête de chaque widget.
- **Cache PWA iOS** : vérifier le déploiement effectif après build (onglet privé Safari ou
  réinstallation), la police embarquée étant un nouvel asset à précacher.

## 11. Prochaine étape

Après validation → plan d'implémentation (`writing-plans`) puis exécution.
