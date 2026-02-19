# Rigging Guide (Rive)

## Canvas
- Artboard: `PlantCharacter`
- Size consigliata: `420 x 420`
- Origine personaggio: centro in basso (`x: 210`, `y: 300`)

## Layer order (bottom -> top)
1. `pot_base`
2. `stem`
3. `leaf_left`
4. `leaf_right`
5. `cheek_left`
6. `cheek_right`
7. `face_eyes_open`
8. `face_eyes_closed`
9. `face_mouth_smile`
10. `face_mouth_sad`
11. `face_mouth_o`

## Bones / pivots
- `root`: pivot su base vaso (`210, 300`)
- `stem_bone`: dal vaso verso alto (`210, 225`)
- `leaf_left_bone`: pivot `210, 176`
- `leaf_right_bone`: pivot `214, 166`
- `face_group`: pivot `210, 225`

## Recommended controls
- Rotation root: `-4° .. +4°`
- Rotation leaf_left: `-16° .. +8°`
- Rotation leaf_right: `-8° .. +16°`
- Stem bend (Y translate top): `-4 .. +6 px`

## Visibility switching
- Eyes: open OR closed
- Mouth: smile OR sad OR o

## Naming
Usa i nomi esatti per facilitare mapping runtime Flutter.
