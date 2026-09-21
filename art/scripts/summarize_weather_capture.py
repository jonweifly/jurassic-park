"""Build labelled native-weather comparisons; never alter the captured pixels."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "godot/captures/weather-refinement"


def comparison(stage, index):
    result = Image.new("RGB", (1280, 432), (20, 24, 26))
    draw = ImageDraw.Draw(result)
    for column, version in enumerate(("before", "after")):
        source = Image.open(FOLDER / f"{stage}-{version}-{index:02d}.png").convert("RGB")
        source.thumbnail((640, 400), Image.Resampling.LANCZOS)
        result.paste(source, (column * 640, 32))
        draw.text((column * 640 + 16, 10), f"{stage.upper()} | {version.upper()}", fill="white")
    return result


def main():
    measurements = {}
    for stage in ("gale", "rain", "storm"):
        frames = [comparison(stage, i) for i in range(40)]
        # A shared palette prevents unrelated color flicker between GIF frames.
        palette = frames[0].quantize(colors=256)
        indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
        indexed[0].save(FOLDER / f"{stage}-comparison.gif", save_all=True,
                        append_images=indexed[1:], duration=100, loop=0, optimize=False)
        frames[20].save(FOLDER / f"{stage}-comparison.png")
        for version in ("before", "after"):
            captures = [np.asarray(Image.open(FOLDER / f"{stage}-{version}-{i:02d}.png")
                                   .convert("RGB").resize((320, 200)), dtype=np.int16)
                        for i in range(40)]
            changes = [float(np.abs(b - a).mean()) for a, b in zip(captures, captures[1:])]
            measurements[f"{stage}-{version}"] = {
                "mean_absolute_frame_difference_0_255": float(np.mean(changes)),
                "p90_absolute_frame_difference_0_255": float(np.percentile(changes, 90)),
                "frames": 40,
            }
    measurements["limits"] = (
        "Native camera-matched captures. Wind clock steps at 0.1 seconds. "
        "Rain particles advance in real time, including capture overhead, and are not seed matched. "
        "Metrics include foliage, water and shadows; they are not a rain density or comfort score. "
        "GIF loops rewind and are previews, not an exact timing recording."
    )
    (FOLDER / "motion-metrics.json").write_text(json.dumps(measurements, indent=2) + "\n")
    print(json.dumps(measurements, indent=2))


if __name__ == "__main__":
    main()
