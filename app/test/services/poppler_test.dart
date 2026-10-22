import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/native/poppler.dart';

/// A minimal valid PDF: [pages] pages of 200 x 100 points, each with a
/// black rectangle filling the left half.
Uint8List samplePdf({int pages = 1}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[for (var i = 0; i < pages; i++) '${3 + i * 2} 0 R'].join(' ')}] /Count $pages >>',
  ];
  const content = '0 0 0 rg 0 0 100 100 re f';
  for (var i = 0; i < pages; i++) {
    objects
      ..add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents ${4 + i * 2} 0 R >>')
      ..add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return ascii.encode(out.toString());
}

void main() {
  test('opens a PDF from memory and renders its pages', () async {
    final pdf = await PdfDocument.open(samplePdf(pages: 2));
    addTearDown(pdf.close);
    expect(pdf.pageCount, 2);
    expect(pdf.pageSizes.first, (width: 200.0, height: 100.0));

    final page = await pdf.render(1, 2);
    expect((page.width, page.height), (400, 200));
    expect(page.pixels.length, 400 * 200 * 4);
    // BGRA: the left half is the black rectangle, the right half the white page.
    int pixel(int x, int y) => (y * page.width + x) * 4;
    expect(page.pixels.sublist(pixel(50, 100), pixel(50, 100) + 4), [0, 0, 0, 255]);
    expect(page.pixels.sublist(pixel(350, 100), pixel(350, 100) + 4), [255, 255, 255, 255]);
  });

  test('caps the rendered size', () async {
    final pdf = await PdfDocument.open(samplePdf());
    addTearDown(pdf.close);
    final page = await pdf.render(0, 100);
    expect((page.width, page.height), (PdfDocument.maxPixels, PdfDocument.maxPixels ~/ 2));
  });

  test('refuses bytes that are not a PDF', () async {
    await expectLater(
      PdfDocument.open(Uint8List.fromList(utf8.encode('not a pdf'))),
      throwsA(isA<PdfOpenException>().having((e) => e.failure, 'failure', PdfOpenFailure.unreadable)),
    );
  });

  test('rendering after close fails, and close can be called twice', () async {
    final pdf = await PdfDocument.open(samplePdf());
    await pdf.close();
    await pdf.close();
    await expectLater(pdf.render(0, 1), throwsStateError);
  });
}
