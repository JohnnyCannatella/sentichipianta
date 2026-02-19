# Plant Character Kit (Rive-ready)

Questo kit contiene asset vettoriali separati e specifiche per creare una pianta animata in Rive.

## Struttura
- `svg/`: parti vettoriali modulari (import in Rive come shape/layer distinti)
- `spec/rigging_guide.md`: pivot, bones e naming consigliato
- `spec/state_machine.md`: stati animazione e transizioni
- `spec/flutter_mapping.md`: mappatura sensori -> input Rive

## Parti SVG
- `pot_base.svg`
- `stem.svg`
- `leaf_left.svg`
- `leaf_right.svg`
- `face_eyes_open.svg`
- `face_eyes_closed.svg`
- `face_mouth_smile.svg`
- `face_mouth_sad.svg`
- `face_mouth_o.svg`
- `cheek_left.svg`
- `cheek_right.svg`

## Art direction
- Minimal, caldo, neutro
- Outline morbidi e pochi dettagli
- Palette preimpostata nei file SVG

## Prossimo step in Rive
1. Importa gli SVG.
2. Mantieni i nomi layer identici.
3. Applica il rigging da `spec/rigging_guide.md`.
4. Crea state machine da `spec/state_machine.md`.
5. Collega input runtime seguendo `spec/flutter_mapping.md`.
