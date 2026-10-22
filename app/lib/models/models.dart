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

  const FixtureProfile({
    required this.id,
    required this.manufacturer,
    required this.name,
    required this.channels,
    this.builtIn = false,
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
      };
  factory FixtureProfile.fromJson(Map<String, dynamic> j) => FixtureProfile(
        id: j['id'] as String,
        manufacturer: j['manufacturer'] as String? ?? '',
        name: j['name'] as String,
        channels: (j['channels'] as List)
            .map((c) => ChannelDef.fromJson(c as Map<String, dynamic>))
            .toList(),
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
  Chase({required this.id, required this.name, required this.steps, this.loop = true});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'loop': loop,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
  factory Chase.fromJson(Map<String, dynamic> j) => Chase(
        id: j['id'] as String,
        name: j['name'] as String,
        loop: (j['loop'] as bool?) ?? true,
        steps: (j['steps'] as List)
            .map((s) => ChaseStep.fromJson(s as Map<String, dynamic>))
            .toList(),
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
