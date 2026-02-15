Plant state assets convention

Folder per plant type:
- assets/plant_states/generic/
- assets/plant_states/peperoncino/
- assets/plant_states/sansevieria/
- assets/plant_states/bonsai/
- assets/plant_states/cactus/

Required file names in each folder:
- happy.png
- ok.png
- thirsty.png
- overwatered.png
- low_light.png
- high_light.png
- unknown.png

State meaning:
- happy: moisture >= moisture_ok and light in good range
- ok: stable but not "happy"
- thirsty: moisture < moisture_low
- overwatered: moisture > moisture_high
- low_light: lux < lux_low
- high_light: lux > lux_high
- unknown: no reading available

Type selection priority:
- uses `plants.plant_type` when present
- fallback uses plant name keywords

Fallback keyword detection:
- peperoncino: peper, peperonc, pepper, chili
- sansevieria: sansevieria, sanseveria, snake
- bonsai: bonsai
- cactus: cactus
- fallback: generic
