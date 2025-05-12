import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Import Firebase Core
import 'firebase_options.dart'; // Import the generated options file

import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // For kIsWeb constant
import 'dart:html' as html; // For Blob, Url.createObjectUrlFromBlob, Url.revokeObjectUrl
// import 'package:permission_handler/permission_handler.dart'; // Less critical for web
// import 'package:path/path.dart' as p; // path package less needed for PlatformFile.name

// For web, we might not need path_provider or explicit permission_handler
// For simplicity, I'll comment out platform-specific permission parts
// but in a real cross-platform app, you'd use conditional imports/logic.

String? getCurrentUserId() {
  final User? user = FirebaseAuth.instance.currentUser;
  return user?.uid;
}

Future<User?> signInAnonymouslyIfNeeded() async {
  FirebaseAuth auth = FirebaseAuth.instance;
  if (auth.currentUser == null) {
    try {
      UserCredential userCredential = await auth.signInAnonymously();
      print("Signed in anonymously: ${userCredential.user?.uid}");
      return userCredential.user;
    } catch (e) {
      print("Error signing in anonymously: $e");
      return null;
    }
  } else {
    print("User already signed in: ${auth.currentUser?.uid}");
    return auth.currentUser;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Uses the generated firebase_options.dart
  );

  // Attempt anonymous sign-in
  await signInAnonymouslyIfNeeded(); // You might want to store the User object

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Web Music Player',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.teal,
        hintColor: Colors.tealAccent,
        scaffoldBackgroundColor: Colors.grey[900],
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      home: const MusicPlayerScreen(),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<PlatformFile> _songs = []; // Changed from List<File>
  int _currentSongIndex = -1;
  String _currentSongTitle = "No song selected";
  double _currentVolume = 1.0;
  String? _currentObjectUrl; // To store the current blob URL for web playback

  @override
  void initState() {
    super.initState();
    _audioPlayer.setVolume(_currentVolume);
    // _requestPermission(); // Permission handling is different on web

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        _playNext();
      }
    });
  }

  // Simplified permission for web context (browser handles it via picker)
  // Future<void> _requestPermission() async {
  //   if (kIsWeb) { // kIsWeb is from flutter/foundation.dart
  //     print("Running on Web, file picker will handle permissions.");
  //     return;
  //   }
  //   // ... (keep native permission logic if needed for mobile)
  // }

  Future<void> _pickSongs() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      print("Files picked to add: ${result.files.length}");
      
      final bool wasListEmpty = _songs.isEmpty; // Check if the list was empty before adding

      // Filter out files that might not have loaded bytes correctly (though withData should ensure it)
      final newSongs = result.files.where((file) => file.bytes != null).toList();

      if (newSongs.isNotEmpty) {
        _songs.addAll(newSongs); // ADD to the existing list

        setState(() {
          if (wasListEmpty) { // If the list was empty, play the first of the newly added songs
            _currentSongIndex = 0; // This will be the first of the new batch
            _playSong(_currentSongIndex);
          } else if (_currentSongIndex == -1) {
            // List was not empty, but nothing was selected/playing.
            // You could choose to auto-select the first of the new songs or just let the user tap.
            // For now, let's just ensure the UI can update if needed.
            // If you want to select the first new one:
            // _currentSongIndex = _songs.length - newSongs.length; // Index of the first new song
            // _currentSongTitle = _songs[_currentSongIndex].name;
          }
          // If a song was already playing, it continues to play.
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newSongs.length} song(s) added to library.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid audio files found in selection.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files selected or an error occurred.')),
      );
    }
  }

    Future<void> _playSong(int index, {bool resume = false}) async {
    if (index < 0 || index >= _songs.length) {
      print("_playSong: Invalid index $index"); // DEBUG
      return;
    }

    final song = _songs[index];
    print("_playSong: Attempting to play '${song.name}' at index $index. Has bytes: ${song.bytes != null}"); // DEBUG

    if (song.bytes == null) {
      print("Error: Song bytes are null for '${song.name}'. Cannot play."); // DEBUG
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: Could not load song data for ${song.name}')),
      );
      setState(() {
         _currentSongTitle = "Error loading song";
         _isPlaying = false;
      });
      return;
    }

    try {
      if (!resume || _currentSongIndex != index) {
        print("_playSong: Stopping player and setting new source."); // DEBUG
        await _audioPlayer.stop();
        await _audioPlayer.setSourceBytes(song.bytes as Uint8List); // Ensure song.bytes is not null here
        print("_playSong: Source set for '${song.name}'"); // DEBUG
      } else {
        print("_playSong: Resuming current song '${song.name}'"); // DEBUG
      }
      await _audioPlayer.resume();
      print("_playSong: Resumed/Played '${song.name}'"); // DEBUG
      
      setState(() {
        _currentSongIndex = index;
        _currentSongTitle = song.name;
        _isPlaying = true;
      });
    } catch (e, s) { // <<<<<<< CORRECTED CATCH BLOCK HERE
      print("Error playing song '${song.name}': $e"); 
      print("Stack trace for '${song.name}':\n$s"); // <<<<<<< PRINTING THE STACK TRACE
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: ${song.name} - $e')), // Added error to snackbar
      );
       setState(() {
        _isPlaying = false;
        _currentSongTitle = "Error playing song";
      });
    }
  }

  Future<void> _pauseSong() async {
    await _audioPlayer.pause();
    setState(() {
      _isPlaying = false;
    });
  }

  Future<void> _resumeSong() async {
     if (_currentSongIndex != -1) {
       _playSong(_currentSongIndex, resume: true);
    }
  }

  Future<void> _playNext() async {
    if (_songs.isEmpty) return;
    int nextIndex = (_currentSongIndex + 1) % _songs.length;
    _playSong(nextIndex);
  }

  Future<void> _playPrevious() async {
    if (_songs.isEmpty) return;
    int prevIndex = (_currentSongIndex - 1 + _songs.length) % _songs.length;
    _playSong(prevIndex);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return [
      if (hours > 0) hours.toString(),
      twoDigits(minutes),
      twoDigits(seconds),
    ].join(':');
  }

  Future<void> _seekRelative(int seconds) async {
    if (_currentSongIndex == -1 || _duration == Duration.zero) return; // No song or duration yet

    final currentPosition = _position;
    Duration newPosition = currentPosition + Duration(seconds: seconds);

    // Clamp the new position to be within the song's duration (0 to _duration)
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > _duration) {
      newPosition = _duration; // Don't seek beyond the end
    }

    await _audioPlayer.seek(newPosition);
    // Optional: If you want the song to resume if it was paused when seeking
    // if (!_isPlaying && _songs.isNotEmpty) {
    //   _resumeSong();
    // }
  }

  Future<void> _removeSong(int indexToRemove) async {
    if (indexToRemove < 0 || indexToRemove >= _songs.length) return; // Invalid index

    final removedSongName = _songs[indexToRemove].name;
    print("Attempting to remove song: $removedSongName at index $indexToRemove");

    bool isCurrentlyPlayingSongRemoved = (_currentSongIndex == indexToRemove);

    // 1. If the song being removed is the one currently playing:
    if (isCurrentlyPlayingSongRemoved) {
      await _audioPlayer.stop();
      _isPlaying = false;
      _duration = Duration.zero;
      _position = Duration.zero;
      if (kIsWeb && _currentObjectUrl != null) {
        html.Url.revokeObjectUrl(_currentObjectUrl!);
        _currentObjectUrl = null;
        print("Revoked _currentObjectUrl for removed playing song: $removedSongName");
      }
    }

    // 2. Remove the song from the list
    _songs.removeAt(indexToRemove);
    print("Song $removedSongName removed. New song count: ${_songs.length}");

    // 3. Adjust _currentSongIndex and player state
    if (_songs.isEmpty) {
      _currentSongIndex = -1;
      _currentSongTitle = "No song selected";
      // isPlaying, duration, position already handled if current was removed
    } else if (isCurrentlyPlayingSongRemoved) {
      // The currently playing song was removed, and the list is not empty.
      // Let's select the next song (or the first if the last one was removed), but don't auto-play.
      // User will need to tap to play.
      _currentSongIndex = indexToRemove % _songs.length; // Stays at same index or wraps to 0
      // Or simply set to -1 to force user selection:
      // _currentSongIndex = -1;
      // _currentSongTitle = "Select a song";
      // For now, let's try to keep a selection if possible
      if (_currentSongIndex >= _songs.length) _currentSongIndex = 0; // Ensure valid index
      _currentSongTitle = _songs[_currentSongIndex].name;

    } else if (_currentSongIndex > indexToRemove) {
      // A song *before* the currently playing one was removed.
      _currentSongIndex--;
    }
    // If a song *after* the current one was removed, _currentSongIndex is still correct.

    setState(() {}); // Update the UI
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Web Music Player by YZ & MM'), // Your custom title
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: _pickSongs,
            tooltip: 'Add Songs to Library',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Album Art Placeholder
            Container(
              height: 200,
              width: 200,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: const AssetImage('assets/default_album_art.png'),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.dstATop),
                ),
              ),
              child: _currentSongIndex == -1 ? Icon(Icons.music_note, size: 100, color: Colors.grey[600]) : null,
            ),
            const SizedBox(height: 24),

            // Song Title
            Text(
              _currentSongTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Artist/Status Text
            Text(
              _currentSongIndex != -1 ? "Playing from local file" : "Select a song",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 24),

            // Progress Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.tealAccent,
                inactiveTrackColor: Colors.teal.withOpacity(0.3),
                thumbColor: Colors.teal,
                overlayColor: Colors.teal.withAlpha(0x29),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0),
              ),
              child: Slider(
                min: 0,
                max: _duration.inSeconds.toDouble() + 1.0, // +1 to prevent jump at end
                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                onChanged: (value) async {
                  if (_duration > Duration.zero) { // Only seek if duration is loaded
                    final position = Duration(seconds: value.toInt());
                    await _audioPlayer.seek(position);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_position), style: const TextStyle(color: Colors.white70)),
                  Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Playback Controls with Seek Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10, size: 30),
                  onPressed: _songs.isNotEmpty && _duration > Duration.zero ? () => _seekRelative(-10) : null,
                  color: Colors.white,
                  tooltip: 'Rewind 10s',
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 36),
                  onPressed: _songs.isNotEmpty ? _playPrevious : null,
                  color: Colors.white,
                  tooltip: 'Play previous',
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 64,
                  ),
                  onPressed: _currentSongIndex != -1
                      ? (_isPlaying ? _pauseSong : _resumeSong)
                      : null,
                  color: Colors.tealAccent,
                  tooltip: 'Pause/Resume',
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 36),
                  onPressed: _songs.isNotEmpty ? _playNext : null,
                  color: Colors.white,
                  tooltip: 'Play next',
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10, size: 30),
                  onPressed: _songs.isNotEmpty && _duration > Duration.zero ? () => _seekRelative(10) : null,
                  color: Colors.white,
                  tooltip: 'Forward 10s',
                ),
              ],
            ),
            const SizedBox(height: 20), // Adjusted spacing

            // Volume Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.volume_down, color: _currentVolume > 0.05 ? Colors.white : Colors.white30),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white70,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withAlpha(0x29),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                    ),
                    child: Slider(
                      min: 0.0,
                      max: 1.0,
                      value: _currentVolume,
                      onChanged: (value) {
                        setState(() {
                          _currentVolume = value;
                        });
                        _audioPlayer.setVolume(_currentVolume);
                      },
                    ),
                  ),
                ),
                Icon(Icons.volume_up, color: _currentVolume < 0.95 ? Colors.white : Colors.white30),
              ],
            ),
            const SizedBox(height: 30),

            // Song List
            Expanded(
              child: _songs.isEmpty
                  ? Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.library_music),
                        label: const Text("Load Songs From Device"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _pickSongs,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _songs.length,
                      itemBuilder: (context, index) {
                        final songFile = _songs[index];
                        final title = songFile.name;
                        return Card(
                          color: _currentSongIndex == index
                              ? Colors.teal.withOpacity(0.5)
                              : Colors.grey[800],
                          child: ListTile(
                            leading: Icon(Icons.music_note, color: _currentSongIndex == index ? Colors.tealAccent : Colors.white),
                            title: Text(
                              title,
                              style: TextStyle(
                                color: _currentSongIndex == index ? Colors.white : Colors.white70,
                                fontWeight: _currentSongIndex == index ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              if (_currentSongIndex == index && _isPlaying) {
                                _pauseSong(); // If tapping current playing song, pause it
                              } else {
                                _playSong(index); // Else, play the tapped song
                              }
                            },
                            // --- MODIFIED TRAILING SECTION TO INCLUDE REMOVE BUTTON ---
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min, // Crucial for Row in ListTile trailing
                              children: [
                                if (_currentSongIndex == index && _isPlaying)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8.0), // Space between icons
                                    child: Icon(Icons.bar_chart_rounded, color: Colors.tealAccent),
                                  ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.redAccent[100]),
                                  tooltip: 'Remove from library',
                                  onPressed: () {
                                    _removeSong(index); // Call the remove song method
                                  },
                                ),
                              ],
                            ),
                            // --- END OF MODIFIED TRAILING SECTION ---
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
