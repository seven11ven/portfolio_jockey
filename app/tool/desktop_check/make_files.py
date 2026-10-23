"""Makes the test files desktop-check.sh adds to a project. Standard library only.

    python3 -I make_files.py <folder>

- tone.wav: 12 s, 440 Hz, mono
- bars.avi: 10 s of 160x120 uncompressed video at 15 fps, a white bar moving
  across a grey background, so a playing video looks different from one frame
  to the next (AVI, because the app picks the preview type by extension)
- picture.png, notes.txt, readme.md, page.pdf (one page with a line of text)
- big.bin: 24 MB of random data, so an export takes long enough to cancel
"""
import math
import os
import struct
import sys
import wave
import zlib


def tone(path, seconds=12, rate=22050):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b''.join(struct.pack('<h', int(8000 * math.sin(2 * math.pi * 440 * i / rate))) for i in range(seconds * rate)))


def bars(path, seconds=10, fps=15, width=160, height=120):
    """An AVI with uncompressed 24-bit frames: a white bar moving across grey."""
    frame_size = width * height * 3
    frames = []
    for n in range(seconds * fps):
        x0 = (n * 6) % width
        row = bytearray(b'\x5a' * (width * 3))
        for x in range(x0, min(x0 + 16, width)):
            row[x * 3:x * 3 + 3] = b'\xeb\xeb\xeb'
        frames.append(bytes(row) * height)

    def chunk(kind, body):
        return kind + struct.pack('<I', len(body)) + body + (b'\x00' if len(body) % 2 else b'')

    def lst(kind, body):
        return chunk(b'LIST', kind + body)

    count = len(frames)
    avih = struct.pack('<10I4I', 1000000 // fps, frame_size * fps, 0, 0x10, count, 0, 1, frame_size, width, height, 0, 0, 0, 0)
    strh = b'vids' + b'DIB ' + struct.pack('<IHHIIIIIIIIhhhh', 0, 0, 0, 0, 1, fps, 0, count, frame_size, 0xFFFFFFFF, 0, 0, 0, width, height)
    strf = struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24, 0, frame_size, 0, 0, 0, 0)
    hdrl = lst(b'hdrl', chunk(b'avih', avih) + lst(b'strl', chunk(b'strh', strh) + chunk(b'strf', strf)))
    movi = lst(b'movi', b''.join(chunk(b'00db', f) for f in frames))
    offset, index = 4, []
    for f in frames:
        index.append(struct.pack('<4sIII', b'00db', 0x10, offset, len(f)))
        offset += 8 + len(f)
    body = b'AVI ' + hdrl + movi + chunk(b'idx1', b''.join(index))
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', len(body)) + body)


def png(path, width=64, height=48):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b''.join(b'\x00' + b''.join(bytes([(x * 4) % 256, (y * 5) % 256, 160]) for x in range(width)) for y in range(height))
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def pdf(path):
    text = b'BT /F1 24 Tf 72 720 Td (Portfolio Jockey test page) Tj ET'
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        b'<< /Length %d >>\nstream\n' % len(text) + text + b'\nendstream',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ]
    out = bytearray(b'%PDF-1.4\n')
    offsets = []
    for i, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += b'%d 0 obj\n' % i + body + b'\nendobj\n'
    xref = len(out)
    out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)
    out += b''.join(b'%010d 00000 n \n' % o for o in offsets)
    out += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    with open(path, 'wb') as f:
        f.write(out)


def main():
    folder = sys.argv[1]
    os.makedirs(folder, exist_ok=True)
    tone(os.path.join(folder, 'tone.wav'))
    bars(os.path.join(folder, 'bars.avi'))
    png(os.path.join(folder, 'picture.png'))
    with open(os.path.join(folder, 'notes.txt'), 'w') as f:
        f.write('First line of the test notes.\nSecond line.\n')
    with open(os.path.join(folder, 'readme.md'), 'w') as f:
        f.write('# Test readme\n\nSome **bold** text and a list:\n\n- one\n- two\n')
    pdf(os.path.join(folder, 'page.pdf'))
    with open(os.path.join(folder, 'big.bin'), 'wb') as f:
        f.write(os.urandom(24 * 1024 * 1024))


if __name__ == '__main__':
    main()
