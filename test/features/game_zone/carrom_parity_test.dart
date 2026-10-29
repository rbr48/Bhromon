import 'package:bhromon/features/game_zone/carrom/carrom_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// A break shot recorded from the server's physics (functions/src/carrom).
// The phone replays online shots on its own engine, so both must land every
// piece in exactly the same place. The same numbers are checked on the server
// in functions/src/__tests__/carrom_game.test.ts.

const _vx = 0.041423333219775885;
const _vy = -3.1862307445420464;

const _start = <({int id, CarromPieceType type, double x, double y})>[
  (id: 0, type: CarromPieceType.queen, x: 0.5, y: 0.5),
  (id: 1, type: CarromPieceType.white, x: 0.5, y: 0.54386),
  (id: 2, type: CarromPieceType.black, x: 0.46201612579001455, y: 0.52193),
  (id: 3, type: CarromPieceType.white, x: 0.4620161257900145, y: 0.47807),
  (id: 4, type: CarromPieceType.black, x: 0.5, y: 0.45614),
  (id: 5, type: CarromPieceType.white, x: 0.5379838742099855, y: 0.47807),
  (id: 6, type: CarromPieceType.black, x: 0.5379838742099855, y: 0.52193),
  (id: 7, type: CarromPieceType.black, x: 0.5, y: 0.58772),
  (
    id: 8,
    type: CarromPieceType.white,
    x: 0.45614000000000005,
    y: 0.575967748419971
  ),
  (id: 9, type: CarromPieceType.black, x: 0.42403225158002905, y: 0.54386),
  (id: 10, type: CarromPieceType.white, x: 0.41228, y: 0.5),
  (
    id: 11,
    type: CarromPieceType.black,
    x: 0.42403225158002905,
    y: 0.45614000000000005
  ),
  (
    id: 12,
    type: CarromPieceType.white,
    x: 0.45614000000000005,
    y: 0.42403225158002905
  ),
  (id: 13, type: CarromPieceType.black, x: 0.5, y: 0.41228),
  (
    id: 14,
    type: CarromPieceType.white,
    x: 0.5438599999999999,
    y: 0.424032251580029
  ),
  (id: 15, type: CarromPieceType.black, x: 0.5759677484199709, y: 0.45614),
  (id: 16, type: CarromPieceType.white, x: 0.58772, y: 0.5),
  (id: 17, type: CarromPieceType.black, x: 0.575967748419971, y: 0.54386),
  (id: 18, type: CarromPieceType.white, x: 0.54386, y: 0.5759677484199709),
  (id: 99, type: CarromPieceType.striker, x: 0.5, y: 0.845),
];

// Where each coin comes to rest.
const _end = <({int id, double x, double y, bool pocketed})>[
  (id: 0, x: 0.39909468590158453, y: 0.17328294054717144, pocketed: false),
  (id: 1, x: 0.5167747634618395, y: 0.5370611084713123, pocketed: false),
  (id: 2, x: 0.45885043551658583, y: 0.5189562165851487, pocketed: false),
  (id: 3, x: 0.44670603161652933, y: 0.47032891900113505, pocketed: false),
  (id: 4, x: 0.6473804822495929, y: 0.3452438132414054, pocketed: false),
  (id: 5, x: 0.5830937766731544, y: 0.450331434676579, pocketed: false),
  (id: 6, x: 0.5674600973129902, y: 0.49308408386878677, pocketed: false),
  (id: 7, x: 0.4247674984033129, y: 0.568871863184978, pocketed: false),
  (id: 8, x: 0.15503938167604112, y: 0.7893282107373064, pocketed: false),
  (id: 9, x: 0.38737019457281474, y: 0.5465748123214239, pocketed: false),
  (id: 10, x: 0.4030048669795413, y: 0.48426615530294176, pocketed: false),
  (id: 11, x: 0.18741871994278278, y: 0.08416732742074995, pocketed: false),
  (id: 12, x: 0.3841581677362726, y: 0.4107264548819789, pocketed: false),
  (id: 13, x: 0.4907153523868395, y: 0.4886402011565425, pocketed: false),
  (id: 14, x: 0.6073500191252046, y: 0.3802232166340815, pocketed: false),
  (id: 15, x: 0.9072188133325689, y: 0.1615356671629447, pocketed: false),
  (id: 16, x: 0.6340456713861573, y: 0.46171026608610755, pocketed: false),
  (id: 17, x: 0.773478877766681, y: 0.5290815552436978, pocketed: false),
  (id: 18, x: 0.5948915798383954, y: 0.6682263769038964, pocketed: false),
];

void main() {
  test('A break shot ends exactly where the server puts it', () {
    final pieces = [
      for (final p in _start)
        CarromPiece(id: p.id, type: p.type, x: p.x, y: p.y),
    ];
    pieces.last
      ..vx = _vx
      ..vy = _vy;
    CarromBoard.simulateToRest(pieces);
    for (var i = 0; i < _end.length; i++) {
      final want = _end[i];
      final got = pieces[i];
      expect(got.id, want.id);
      expect(got.x, want.x, reason: 'x of piece ${want.id}');
      expect(got.y, want.y, reason: 'y of piece ${want.id}');
      expect(got.pocketed, want.pocketed, reason: 'piece ${want.id}');
    }
  });
}
