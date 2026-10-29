"""Decode QR Code PNGs with an independent decoder, for t/09-decode.t.

Uses zxing-cpp (pip install zxing-cpp pillow) when present, otherwise
OpenCV (pip install opencv-python-headless). Reads one PNG path per line on
stdin and prints the hex of the decoded UTF-8 text, or ERR, per line.
Run with --check to exit 0 only if a decoder is importable."""
import sys

try:
    import zxingcpp
    from PIL import Image

    def decode(path):
        hits = zxingcpp.read_barcodes(Image.open(path).convert("L"))
        return hits[0].text if hits else None
except ImportError:
    import cv2

    _det = cv2.QRCodeDetector()

    def decode(path):
        text, _, _ = _det.detectAndDecode(cv2.imread(path, cv2.IMREAD_GRAYSCALE))
        return text or None

if "--check" in sys.argv:
    sys.exit(0)
for line in sys.stdin:
    text = decode(line.strip())
    print(text.encode("utf-8").hex() if text is not None else "ERR", flush=True)
