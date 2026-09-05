# PDF processing fixtures

`ContainerRGB.jp2` is a synthetic, lossless 4 × 4 RGB image generated for this
project. It contains no external artwork or user document data. Recreate with
Pillow's JPEG 2000 writer:

```python
from PIL import Image
image = Image.new('RGB', (4, 4))
image.putdata([(x * 85, y * 85, ((x + y) % 4) * 85)
               for y in range(4) for x in range(4)])
image.save('ContainerRGB.jp2', format='JPEG2000', irreversible=False)
```

The native test adds private XML/UUID boxes and main/tile comments in memory,
then verifies identical decoded pixels and removal of those metadata fields.
No JPEG 2000 encoder is used by the shipping compression workflow.
