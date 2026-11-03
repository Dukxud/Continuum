import 'package:flutter/material.dart';

/// Compatible with the original Windows application's barAppearance schema.
/// No Flutter-only persistence format: both UIs can read the same preferences.
class AeroAppearance {
  const AeroAppearance({
    this.quota = 'green',
    this.weekly = 'cyan',
    this.time = 'blue',
    this.working = 'amber',
    this.finish = 0,
    this.lighting = 0,
    this.shimmer = 100,
    this.speed = 100,
    this.aero = true,
  });

  final String quota;
  final String weekly;
  final String time;
  final String working;
  final int finish;
  final int lighting;
  final int shimmer;
  final int speed;
  final bool aero;

  static const defaults = AeroAppearance();
  static const presetColors = <String, Color>{
    'green': Color(0xff14de8e),
    'blue': Color(0xff168dff),
    'cyan': Color(0xff04d5f7),
    'violet': Color(0xff9d64ff),
    'amber': Color(0xffffb328),
    'red': Color(0xffff3b62),
  };
  static const presetNames = <String, String>{
    'green': 'Windows green',
    'blue': 'Aero sapphire',
    'cyan': 'Lagoon cyan',
    'violet': 'Amethyst',
    'amber': 'Warm amber',
    'red': 'Ruby red',
  };

  static const keys = ['quota', 'weekly', 'time', 'working'];

  static String validatedColor(Object? value, String fallback) {
    final candidate = value?.toString().trim() ?? '';
    if (presetColors.containsKey(candidate)) return candidate;
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(candidate)) {
      return candidate.toUpperCase();
    }
    return fallback;
  }

  static int boundedInt(Object? value, int fallback, int lower, int upper) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      return fallback;
    }
    final parsed = value.toInt();
    return parsed < lower || parsed > upper ? fallback : parsed;
  }

  factory AeroAppearance.fromJson(Object? source) {
    if (source is! Map) return defaults;
    return AeroAppearance(
      quota: validatedColor(source['quota'], 'green'),
      weekly: validatedColor(source['weekly'], 'cyan'),
      time: validatedColor(source['time'], 'blue'),
      working: validatedColor(source['working'], 'amber'),
      finish: boundedInt(source['finish'], 0, 0, 2),
      lighting: boundedInt(source['lighting'], 0, 0, 2),
      shimmer: boundedInt(source['shimmer'], 100, 0, 200),
      speed: boundedInt(source['speed'], 100, 25, 300),
      aero: source['aero'] is bool ? source['aero'] as bool : true,
    );
  }

  Map<String, Object> toJson() => {
    'quota': quota,
    'weekly': weekly,
    'time': time,
    'working': working,
    'finish': finish,
    'lighting': lighting,
    'shimmer': shimmer,
    'speed': speed,
    'aero': aero,
  };

  String selection(String kind) {
    switch (kind) {
      case 'quota': return quota;
      case 'weekly': return weekly;
      case 'time': return time;
      case 'working': return working;
      default: throw ArgumentError.value(kind, 'kind');
    }
  }

  Color color(String kind) {
    final choice = selection(kind);
    final preset = presetColors[choice];
    if (preset != null) return preset;
    return Color(int.parse('FF' + choice.substring(1), radix: 16));
  }

  AeroAppearance copyWith({
    String? quota,
    String? weekly,
    String? time,
    String? working,
    int? finish,
    int? lighting,
    int? shimmer,
    int? speed,
    bool? aero,
  }) {
    return AeroAppearance(
      quota: quota ?? this.quota,
      weekly: weekly ?? this.weekly,
      time: time ?? this.time,
      working: working ?? this.working,
      finish: finish ?? this.finish,
      lighting: lighting ?? this.lighting,
      shimmer: shimmer ?? this.shimmer,
      speed: speed ?? this.speed,
      aero: aero ?? this.aero,
    );
  }

  AeroAppearance withColor(String kind, String value) {
    final validated = validatedColor(value, selection(kind));
    switch (kind) {
      case 'quota': return copyWith(quota: validated);
      case 'weekly': return copyWith(weekly: validated);
      case 'time': return copyWith(time: validated);
      case 'working': return copyWith(working: validated);
      default: throw ArgumentError.value(kind, 'kind');
    }
  }

  @override
  bool operator ==(Object other) => other is AeroAppearance &&
    other.quota == quota && other.weekly == weekly &&
    other.time == time && other.working == working &&
    other.finish == finish && other.lighting == lighting &&
    other.shimmer == shimmer && other.speed == speed && other.aero == aero;

  @override
  int get hashCode => Object.hash(
    quota, weekly, time, working, finish, lighting, shimmer, speed, aero);
}
