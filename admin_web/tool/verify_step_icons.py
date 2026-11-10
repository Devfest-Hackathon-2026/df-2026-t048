from pathlib import Path
from PIL import Image

for f in Path("assets/steps").glob("step_*.png"):
    im = Image.open(f).convert("RGBA")
    a = im.getchannel("A")
    hist = a.histogram()
    print(f.name, im.size, "alpha0", hist[0], "alpha255", hist[255], "extrema", a.getextrema())
