import 'package:bhromon/features/tour_group/domain/services/study_booklet_svg_text.dart';
import 'package:flutter_test/flutter_test.dart';

// The labels of a figure in a printed booklet: symbols the built-in font cannot draw become plain
// words, letters it can draw stay, and the rest is dropped. The figure's shapes are not touched.

void main() {
  group('studyBookletPdfSafeSvg', () {
    test('symbols become words the font draws, so a label keeps its meaning',
        () {
      expect(
        studyBookletPdfSafeSvg('<svg><text>D₁ → D₂ (ΔY)</text></svg>'),
        '<svg><text>D1 -&gt; D2 (DeltaY)</text></svg>',
      );
    });

    test('a label with no plain form is dropped', () {
      expect(
        studyBookletPdfSafeSvg('<svg><text>উৎপাদন</text></svg>'),
        '<svg><text></text></svg>',
      );
    });

    test('Latin-1 letters, degree signs and superscripts are kept', () {
      expect(
        studyBookletPdfSafeSvg('<svg><text>é 45° × ÷ x²</text></svg>'),
        '<svg><text>é 45° × ÷ x²</text></svg>',
      );
    });

    test(
        'shapes and attributes are left alone, and a reference is read as its character',
        () {
      expect(
        studyBookletPdfSafeSvg(
          '<svg><path d="M0 0" fill="#fff"/><text x="5">&#8594; &amp; B</text></svg>',
        ),
        '<svg><path d="M0 0" fill="#fff"/><text x="5">-&gt; &amp; B</text></svg>',
      );
    });

    test('a line break inside a label becomes a space', () {
      expect(
        studyBookletPdfSafeSvg('<svg><text>A\nB</text></svg>'),
        '<svg><text>A B</text></svg>',
      );
    });

    test('markup inside a label, such as a tspan, is kept', () {
      expect(
        studyBookletPdfSafeSvg(
            '<svg><text>P<tspan font-size="9">₃</tspan> ≥ 10</text></svg>'),
        '<svg><text>P<tspan font-size="9">3</tspan> &gt;= 10</text></svg>',
      );
    });

    test('a diagram without text is unchanged', () {
      const svg = '<svg><rect width="10" height="10"/></svg>';
      expect(studyBookletPdfSafeSvg(svg), svg);
    });

    test('cleaning a diagram twice gives the same result', () {
      final once =
          studyBookletPdfSafeSvg('<svg><text>P₃ ≥ 10 → Q</text></svg>');
      expect(studyBookletPdfSafeSvg(once), once);
    });
  });
}
