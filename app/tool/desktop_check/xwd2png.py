"""Turns the framebuffer file Xvfb writes with -fbdir (XWD format) into a PNG.

Standard library only. Handles what Xvfb writes: 24-bit colour at 32 bits per
pixel, in either byte order.

    python3 -I xwd2png.py <Xvfb_screen0> <out.png> [x y width height]
"""
import struct
import sys
import zlib


def read_xwd(path):
    with open(path, 'rb') as f:
        data = f.read()
    fields = struct.unpack('>25I', data[:100])
    header_size, version = fields[0], fields[1]
    if version != 7:
        raise ValueError(f'not an XWD file (version {version})')
    width, height = fields[4], fields[5]
    byte_order, bits_per_pixel, bytes_per_line = fields[7], fields[11], fields[12]
    red_mask, green_mask, blue_mask = fields[14], fields[15], fields[16]
    ncolors = fields[19]
    if bits_per_pixel != 32:
        raise ValueError(f'unsupported {bits_per_pixel} bits per pixel')
    start = header_size + ncolors * 12
    order = '<' if byte_order == 0 else '>'
    shifts = [(mask, (mask & -mask).bit_length() - 1) for mask in (red_mask, green_mask, blue_mask)]
    rows = []
    for y in range(height):
        line = data[start + y * bytes_per_line:start + y * bytes_per_line + width * 4]
        pixels = struct.unpack(f'{order}{width}I', line)
        row = bytearray(width * 3)
        for x, p in enumerate(pixels):
            for c, (mask, shift) in enumerate(shifts):
                row[x * 3 + c] = (p & mask) >> shift
        rows.append(row)
    return width, height, rows


def write_png(path, width, height, rows):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b''.join(b'\x00' + bytes(row) for row in rows)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 6))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


def main():
    width, height, rows = read_xwd(sys.argv[1])
    if len(sys.argv) == 7:
        x, y, w, h = (int(v) for v in sys.argv[3:7])
        rows = [row[x * 3:(x + w) * 3] for row in rows[y:y + h]]
        width, height = w, h
    write_png(sys.argv[2], width, height, rows)


if __name__ == '__main__':
    main()
