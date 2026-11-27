import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum SoundEffect {
  /// A soft pop when a task is finished.
  complete('sounds/pop.wav'),

  /// A rising chime when everything due today is done.
  allDone('sounds/success.wav');

  const SoundEffect(this.asset);
  final String asset;
}

/// Plays short UI sounds.
abstract interface class SoundPlayer {
  void play(SoundEffect effect);
}

/// Used in tests and where sound isn't wanted.
class SilentSoundPlayer implements SoundPlayer {
  const SilentSoundPlayer();

  @override
  void play(SoundEffect effect) {}
}

/// Plays the bundled sounds with `audioplayers`. They respect the phone's
/// own volume and silent mode.
class AssetSoundPlayer implements SoundPlayer {
  final _players = <SoundEffect, AudioPlayer>{};

  @override
  void play(SoundEffect effect) {
    final player = _players.putIfAbsent(effect, () {
      final p = AudioPlayer();
      // Low-latency mode suits short effects.
      p.setPlayerMode(PlayerMode.lowLatency).catchError((_) {});
      return p;
    });
    player
        .stop()
        .then((_) => player.play(AssetSource(effect.asset), volume: 0.7))
        .catchError((Object e) {
          debugPrint('Could not play ${effect.name}: $e');
        });
  }
}
