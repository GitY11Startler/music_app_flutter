import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
// import 'package:permission_handler/permission_handler.dart'; // Less critical for web
// import 'package:path/path.dart' as p; // path package less needed for PlatformFile.name

// For web, we might not need path_provider or explicit permission_handler
// For simplicity, I'll comment out platform-specific permission parts
// but in a real cross-platform app, you'd use conditional imports/logic.

void main() {
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

  @override
  void initState() {
    super.initState();
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
      withData: true, // IMPORTANT for web: ensures bytes are loaded
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _songs = result.files; // Store PlatformFile objects
        if (_songs.isNotEmpty) {
          _currentSongIndex = 0;
          _playSong(_currentSongIndex);
        } else {
          _currentSongIndex = -1;
          _currentSongTitle = "No songs found";
        }
      });
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Web Music Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickSongs,
            tooltip: 'Load Songs',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 200,
              width: 200,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
                // Album art from bytes is more complex for web, placeholder for now
                // image: _currentSongIndex != -1 && _songs[_currentSongIndex].bytes != null
                //     ? DecorationImage(
                //         image: MemoryImage(_songs[_currentSongIndex].bytes!), // This won't work as these are audio bytes
                //         fit: BoxFit.cover,
                //       )
                //     : null,
                 image: DecorationImage( // Keep placeholder
                        image: const AssetImage('assets/default_album_art.png'),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.dstATop)
                      ),
              ),
              child: _currentSongIndex == -1 ? Icon(Icons.music_note, size: 100, color: Colors.grey[600]) : null,
            ),
            const SizedBox(height: 24),

            Text(
              _currentSongTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2, // Allow for longer filenames
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
             Text(
              _currentSongIndex != -1 ? "Playing from local file" : "Select a song",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 24),

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
                max: _duration.inSeconds.toDouble() + 1.0,
                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                onChanged: (value) async {
                  final position = Duration(seconds: value.toInt());
                  await _audioPlayer.seek(position);
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

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 36),
                  onPressed: _songs.isNotEmpty ? _playPrevious : null,
                ),
                const SizedBox(width: 20),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 64,
                  ),
                  onPressed: _currentSongIndex != -1
                      ? (_isPlaying ? _pauseSong : _resumeSong)
                      : null,
                  color: Colors.tealAccent,
                ),
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 36),
                  onPressed: _songs.isNotEmpty ? _playNext : null,
                ),
              ],
            ),
            const SizedBox(height: 30),
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
                        final title = songFile.name; // Use PlatformFile.name
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
                                fontWeight: _currentSongIndex == index ? FontWeight.bold : FontWeight.normal
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _playSong(index);
                            },
                             trailing: _currentSongIndex == index && _isPlaying
                                ? const Icon(Icons.bar_chart_rounded, color: Colors.tealAccent)
                                : null,
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