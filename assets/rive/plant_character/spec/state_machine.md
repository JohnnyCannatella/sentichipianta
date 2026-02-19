# State Machine Spec

## Inputs
- `moisture` (Number 0..100)
- `lux` (Number)
- `connected` (Bool)
- `critical` (Bool)
- `mood` (Number enum)
  - 0 unknown
  - 1 thriving
  - 2 ok
  - 3 thirsty
  - 4 dark
  - 5 stressed

## States
- `idle`
- `happy`
- `thirsty`
- `dark`
- `stressed`
- `sleep`

## Logic
- if `connected == false` -> `sleep`
- else if `mood == 3` -> `thirsty`
- else if `mood == 4` -> `dark`
- else if `mood == 5` -> `stressed`
- else if `mood == 1` -> `happy`
- else -> `idle`

## Animation behavior
- `idle`: sway leggero, blink ogni 3-5s
- `happy`: sway morbido + smile
- `thirsty`: leaf droop + mouth sad + micro tremble
- `dark`: slow motion, eyes half-closed
- `stressed`: pulse rapido + small shake
- `sleep`: eyes closed, oscillazione minima
