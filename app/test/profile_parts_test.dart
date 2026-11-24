import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_control/core/dmx/effects.dart';
import 'package:dmx_control/data/builtin_profiles.dart';
import 'package:dmx_control/models/models.dart';

void main() {
  final sonic = builtinProfiles.firstWhere((p) => p.id == 'varytec-sonicstrobe-7');

  test('Lampe mit zwei Lichtquellen', () {
    expect(sonic.footprint, 7);
    expect(sonic.parts, ['Strobe', 'Ambient']);
    expect(sonic.hasParts, isTrue);
    expect(sonic.offsetOf(ChannelType.dimmer, part: 'Strobe'), 0);
    expect(sonic.offsetOf(ChannelType.dimmer, part: 'Ambient'), 2);
    expect(sonic.offsetsOf(ChannelType.dimmer), [0, 2]);
    expect(sonic.offsetOf(ChannelType.strobe, part: 'Ambient'), 3);
    expect(sonic.partHasColor('Ambient'), isTrue);
    expect(sonic.partHasColor('Strobe'), isFalse);
    expect(sonic.mainPart, 'Ambient');
  });

  test('Wertebereiche', () {
    final strobe = sonic.channels[1];
    expect(strobe.rangeLabel(0), 'Aus');
    expect(strobe.rangeLabel(8), 'Aus');
    expect(strobe.rangeLabel(9), 'Strobe langsam → schnell');
    expect(sonic.channels[0].rangeLabel(100), isNull);
  });

  test('JSON: Lichtquelle und Bereiche bleiben erhalten, alte Profile laden weiter', () {
    final back = FixtureProfile.fromJson(jsonDecode(jsonEncode(sonic.toJson())) as Map<String, dynamic>);
    expect(back.parts, sonic.parts);
    expect(back.channels[1].ranges.length, 2);
    expect(back.channels[1].ranges[1].from, 9);

    final old = FixtureProfile.fromJson({
      'id': 'x',
      'name': 'Alt',
      'channels': [
        {'name': 'Dimmer', 'type': 'dimmer', 'default': 0},
        {'name': 'Neu', 'type': 'gibtsnicht'},
      ],
    });
    expect(old.parts, ['']);
    expect(old.hasParts, isFalse);
    expect(old.channels[1].type, ChannelType.generic);
    expect(old.toJson()['channels'][0].containsKey('part'), isFalse);
  });

  test('Effekte wirken auf die Ambient-Lichtquelle', () {
    final f = Fixture(id: 'f', name: 'Sonic', profileId: sonic.id, universe: 0, address: 10);
    final t = EffectTarget.of(f, sonic);
    expect(t.dimmer, 9 + 2);
    expect(t.red, 9 + 4);
    expect(t.blue, 9 + 6);
  });
}
