import 'dart:convert';
import 'dart:typed_data';

/// Bedeutung eines Kanals – steuert, welches Bedienelement die App zeigt.
enum ChannelType {
  dimmer,
  red,
  green,
  blue,
  white,
  amber,
  uv,
  pan,
  panFine,
  tilt,
  tiltFine,
  speed,
  strobe,
  colorWheel,
  gobo,
  generic;

  bool get isColor => const {red, green, blue, white, amber, uv}.contains(this);
}

class ChannelDef {
  final String name;
  final ChannelType type;
  final int defaultValue;
  const ChannelDef(this.name, this.type, [this.defaultValue = 0]);

  Map<String, dynamic> toJson() =>
      {'name': name, 'type': type.name, 'default': defaultValue};
  factory ChannelDef.fromJson(Map<String, dynamic> j) => ChannelDef(
        j['name'] as String,
        ChannelType.values.byName(j['type'] as String),
        (j['default'] as int?) ?? 0,
      );
}

class FixtureProfile {
  final String id;
  final String manufacturer;
  final String name;
  final List<ChannelDef> channels;
  final bool builtIn;

  /// Paket-ID, die freigeschaltet sein muss (null = frei verfügbar).
  final String? requires;

  const FixtureProfile({
    required this.id,
    required this.manufacturer,
    required this.name,
    required this.channels,
    this.builtIn = false,
    this.requires,
  });

  int get footprint => channels.length;
  String get label => manufacturer.isEmpty ? name : '$manufacturer $name';

  int? offsetOf(ChannelType t) {
    final i = channels.indexWhere((c) => c.type == t);
    return i < 0 ? null : i;
  }

  bool has(ChannelType t) => offsetOf(t) != null;
  bool get hasColor => channels.any((c) => c.type.isColor);
  bool get hasPanTilt => has(ChannelType.pan) && has(ChannelType.tilt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'manufacturer': manufacturer,
        'name': name,
        'channels': channels.map((c) => c.toJson()).toList(),
        if (requires != null) 'requires': requires,
      };
  factory FixtureProfile.fromJson(Map<String, dynamic> j) => FixtureProfile(
        id: j['id'] as String,
        manufacturer: j['manufacturer'] as String? ?? '',
        name: j['name'] as String,
        channels: (j['channels'] as List)
            .map((c) => ChannelDef.fromJson(c as Map<String, dynamic>))
            .toList(),
        requires: j['requires'] as String?,
      );
}

/// Ein gepatchtes Gerät: Profil + Universe + Startadresse (1-basiert).
class Fixture {
  final String id;
  String name;
  final String profileId;
  int universe; // App-interner Index 0..n
  int address; // 1..512

  Fixture({
    required this.id,
    required this.name,
    required this.profileId,
    required this.universe,
    required this.address,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profileId': profileId,
        'universe': universe,
        'address': address,
      };
  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
        id: j['id'] as String,
        name: j['name'] as String,
        profileId: j['profileId'] as String,
        universe: j['universe'] as int,
        address: j['address'] as int,
      );
}

/// Eine Szene ist ein Schnappschuss aller Universen.
class Scene {
  final String id;
  String name;
  int fadeMs;
  final Map<int, Uint8List> universes;

  Scene({
    required this.id,
    required this.name,
    required this.universes,
    this.fadeMs = 1000,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fadeMs': fadeMs,
        'universes': universes
            .map((k, v) => MapEntry(k.toString(), base64Encode(v))),
      };
  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'] as String,
        name: j['name'] as String,
        fadeMs: (j['fadeMs'] as int?) ?? 1000,
        universes: (j['universes'] as Map<String, dynamic>).map((k, v) =>
            MapEntry(int.parse(k), Uint8List.fromList(base64Decode(v as String)))),
      );
}

class ChaseStep {
  String sceneId;
  int fadeMs;
  int holdMs;
  ChaseStep({required this.sceneId, this.fadeMs = 500, this.holdMs = 1000});

  Map<String, dynamic> toJson() =>
      {'sceneId': sceneId, 'fadeMs': fadeMs, 'holdMs': holdMs};
  factory ChaseStep.fromJson(Map<String, dynamic> j) => ChaseStep(
        sceneId: j['sceneId'] as String,
        fadeMs: j['fadeMs'] as int,
        holdMs: j['holdMs'] as int,
      );
}

class Chase {
  final String id;
  String name;
  bool loop;
  final List<ChaseStep> steps;

  /// Im Takt: Schrittlänge folgt dem Tempo (BPM) statt Fade+Halten.
  bool bpmSync;
  double beatsPerStep;

  Chase({
    required this.id,
    required this.name,
    required this.steps,
    this.loop = true,
    this.bpmSync = false,
    this.beatsPerStep = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'loop': loop,
        'bpmSync': bpmSync,
        'beatsPerStep': beatsPerStep,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
  factory Chase.fromJson(Map<String, dynamic> j) => Chase(
        id: j['id'] as String,
        name: j['name'] as String,
        loop: (j['loop'] as bool?) ?? true,
        bpmSync: (j['bpmSync'] as bool?) ?? false,
        beatsPerStep: (j['beatsPerStep'] as num?)?.toDouble() ?? 1,
        steps: (j['steps'] as List)
            .map((s) => ChaseStep.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// Feste Auswahl von Lampen, z. B. „Bühne links“.
class FixtureGroup {
  final String id;
  String name;
  final List<String> fixtureIds;
  FixtureGroup({required this.id, required this.name, required this.fixtureIds});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'fixtureIds': fixtureIds};
  factory FixtureGroup.fromJson(Map<String, dynamic> j) => FixtureGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        fixtureIds: [for (final f in (j['fixtureIds'] as List)) f as String],
      );
}

enum EffectType {
  rainbow('Regenbogen', 'Farben laufen durch'),
  pulse('Pulsieren', 'Helligkeit atmet auf und ab'),
  chase('Lauflicht', 'Licht wandert von Lampe zu Lampe'),
  strobe('Strobe', 'Schnelles Blitzen'),
  flicker('Flackern', 'Feuer oder Kerzenlicht'),
  circle('Kreis', 'Moving Heads fahren Kreise');

  const EffectType(this.label, this.hint);
  final String label;
  final String hint;

  /// Sinnvolle Startwerte je Effekt.
  ({double beats, double size, double spread, int? color}) get defaults => switch (this) {
        EffectType.rainbow => (beats: 16, size: 1, spread: 1, color: null),
        EffectType.pulse => (beats: 2, size: 0.8, spread: 0, color: null),
        EffectType.chase => (beats: 4, size: 0, spread: 0, color: null),
        EffectType.strobe => (beats: 0.5, size: 0.5, spread: 0, color: 0xFFFFFF),
        EffectType.flicker => (beats: 8, size: 0.6, spread: 0, color: 0xFF7A1E),
        EffectType.circle => (beats: 8, size: 0.3, spread: 0, color: null),
      };
}

/// Gespeicherter Effekt. Läuft auf den Lampen [fixtureIds] als Überlagerung
/// der normalen Werte; Gesamthelligkeit und Blackout gelten weiterhin.
class Effect {
  final String id;
  String name;
  EffectType type;
  List<String> fixtureIds;

  /// true = Zykluslänge in Schlägen ([beats]) des aktuellen Tempos,
  /// false = feste Geschwindigkeit [cyclesPerMinute].
  bool syncTempo;
  double beats;
  double cyclesPerMinute;

  /// Stärke 0..1 (Hub beim Pulsieren, Größe des Kreises, Schweif beim Lauflicht …)
  double size;

  /// 0 = alle Lampen gleich, 1 = über alle Lampen verteilt
  double spread;

  /// 0xRRGGBB oder null (= Effekt-Standard / aktuelle Farbe)
  int? color;

  Effect({
    required this.id,
    required this.name,
    required this.type,
    required this.fixtureIds,
    this.syncTempo = true,
    this.beats = 4,
    this.cyclesPerMinute = 30,
    this.size = 1,
    this.spread = 0,
    this.color,
  });

  factory Effect.preset(EffectType type, List<String> fixtureIds) {
    final d = type.defaults;
    return Effect(
      id: newId(),
      name: type.label,
      type: type,
      fixtureIds: fixtureIds,
      beats: d.beats,
      size: d.size,
      spread: d.spread,
      color: d.color,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'fixtureIds': fixtureIds,
        'syncTempo': syncTempo,
        'beats': beats,
        'cyclesPerMinute': cyclesPerMinute,
        'size': size,
        'spread': spread,
        'color': color,
      };
  factory Effect.fromJson(Map<String, dynamic> j) => Effect(
        id: j['id'] as String,
        name: j['name'] as String,
        type: EffectType.values.byName(j['type'] as String),
        fixtureIds: [for (final f in (j['fixtureIds'] as List)) f as String],
        syncTempo: (j['syncTempo'] as bool?) ?? true,
        beats: (j['beats'] as num?)?.toDouble() ?? 4,
        cyclesPerMinute: (j['cyclesPerMinute'] as num?)?.toDouble() ?? 30,
        size: (j['size'] as num?)?.toDouble() ?? 1,
        spread: (j['spread'] as num?)?.toDouble() ?? 0,
        color: j['color'] as int?,
      );
}

/// Ausgabe-Ziel: welches App-Universe auf welche Art-Net Port-Address geht.
class NetworkSettings {
  String? nodeIp; // null = Broadcast
  int universeCount;
  int net;
  int subnet;
  int firstUniverse;

  NetworkSettings({
    this.nodeIp,
    this.universeCount = 2,
    this.net = 0,
    this.subnet = 0,
    this.firstUniverse = 0,
  });

  Map<String, dynamic> toJson() => {
        'nodeIp': nodeIp,
        'universeCount': universeCount,
        'net': net,
        'subnet': subnet,
        'firstUniverse': firstUniverse,
      };
  factory NetworkSettings.fromJson(Map<String, dynamic> j) => NetworkSettings(
        nodeIp: j['nodeIp'] as String?,
        universeCount: (j['universeCount'] as int?) ?? 2,
        net: (j['net'] as int?) ?? 0,
        subnet: (j['subnet'] as int?) ?? 0,
        firstUniverse: (j['firstUniverse'] as int?) ?? 0,
      );
}

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
