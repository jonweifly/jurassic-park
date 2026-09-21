# gpt-image-2 Asset Prompts

The current game ships with lightweight local SVG assets so it runs without external credentials. If `OPENAI_API_KEY` is available, these prompts can be used with the imagegen CLI to replace the matching files with polished raster assets.

Use shared constraints for all sprites:

```text
Use case: stylized-concept
Asset type: top-down 2D game sprite for a Warcraft 3 style survival RPG
Style/medium: polished hand-painted game asset, readable at small size, transparent-looking isolated subject on a flat neutral background
Composition/framing: centered, three-quarter top-down view, generous padding, no crop
Lighting/mood: cinematic jungle adventure lighting, clear silhouette
Constraints: no logos, no copyrighted characters, no watermark, no text
Avoid: photorealism, messy background, UI frame, gore
```

## Prompts

`ranger`: A rugged park ranger hero with khaki vest, field hat, utility belt, compact rifle held low, confident survival stance.

`raptor`: A fast velociraptor-like predator, lean body, green and ochre scales, sharp profile, agile threat pose.

`trex`: A large tyrannosaur-like boss predator, heavy body, brown and olive scales, powerful head, dominant silhouette.

`turret`: A deployable automatic defense turret with rugged industrial base, rotating barrel, yellow hazard accents.

`fence`: A section of electrified dinosaur containment fence, metal posts, glowing insulators, worn jungle utility design.

`trap`: A circular tranquilizer trap device with blue glow, rugged metal casing, readable active center.

`generator`: A portable park power generator with cables, warning stripes, repairable machinery details.

`visitor-center`: A jungle visitor center building, warm lodge roof, reinforced doors, emergency lights, top-down readable footprint.

`tree`: A dense tropical jungle tree cluster, broad leaves, trunk visible, top-down game obstacle.

`crate`: A rugged emergency supply crate with straps and worn paint, top-down readable pickup.

`park-bg`: Wide jungle park background, stormy tropical forest, dirt service roads, distant visitor center lights, cinematic but usable behind UI.
