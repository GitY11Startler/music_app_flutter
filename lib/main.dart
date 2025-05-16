import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Import Firebase Core
import 'firebase_options.dart'; // Import the generated options file

import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth

import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // For kIsWeb constant
// import 'package:permission_handler/permission_handler.dart'; // Less critical for web
// import 'package:path/path.dart' as p; // path package less needed for PlatformFile.name

// For web, we might not need path_provider or explicit permission_handler
// For simplicity, I'll comment out platform-specific permission parts
// but in a real cross-platform app, you'd use conditional imports/logic.

import 'authScreen.dart'; // Import the AuthScreen
import 'cloud_utils.dart'; 

String? getCurrentUserId() {
  final User? user = FirebaseAuth.instance.currentUser;
  return user?.uid;
}



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Uses the generated firebase_options.dart
  );


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
  static _MusicPlayerScreenState? instance;


  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLoading = false;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<PlatformFile> _songs = []; // Changed from List<File>
  int _currentSongIndex = -1;
  String _currentSongTitle = "No song selected";
  double _currentVolume = 1.0;
  String? _welcomeMessage;

  @override
void initState() {
  super.initState();
  instance = this; // Set the static instance to this state
  _audioPlayer.setVolume(_currentVolume);

  // Listen to Firebase Auth state changes
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      // User signed in
      print("User signed in: ${user.uid}");
      setState(() {
        _updateWelcomeMessage(user);
      });

      // Fetch songs from the cloud
      _fetchCloudSongs();
    } else {
      // User signed out
      print("User signed out");
      setState(() {
        _welcomeMessage = null;
        _songs.clear(); // Clear songs when signed out
        _currentSongIndex = -1;
        _currentSongTitle = "No song selected";
      });
    }
  });

  // Listen to audio player events
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

void _updateWelcomeMessage(User user) {
  if (user.isAnonymous) {
    _welcomeMessage = "Welcome, Anonymous";
  } else if (user.displayName != null && user.displayName!.isNotEmpty) {
    _welcomeMessage = "Welcome, ${user.displayName}";
  } else if (user.email != null) {
    _welcomeMessage = "Welcome, ${user.email}";
  } else {
    _welcomeMessage = "Welcome!";
  }
}

Future<void> _fetchCloudSongs() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  _showLoadingDialog("Fetching your songs from the cloud...");
  try {
    final fetchedSongs = await fetchSongsFromStorage(); // Use the new function
    if (fetchedSongs.isNotEmpty) {
      setState(() {
        updateSongs(fetchedSongs);
      });
    }
  } catch (e) {
    print("Error fetching songs from Firebase Storage: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to fetch songs from the cloud.')),
    );
  } finally {
    _hideLoadingDialog();
  }
}

  @override
  void dispose() {
    instance = null; // Clear the instance
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<User?> signInAnonymouslyIfNeeded() async {
    FirebaseAuth auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      try {
        _showLoadingDialog("Signing in and fetching your songs...");
        UserCredential userCredential = await auth.signInAnonymously();
        print("Signed in anonymously: ${userCredential.user?.uid}");

        // Fetch songs from the cloud after signing in
        final fetchedSongs = await fetchSongsFromStorage();
        if (fetchedSongs.isNotEmpty) {
          updateSongs(fetchedSongs);
        }

        _hideLoadingDialog();
        return userCredential.user;
      } catch (e) {
        _hideLoadingDialog();
        print("Error signing in anonymously: $e");
        return null;
      }
    } else {
      print("User already signed in: ${auth.currentUser?.uid}");

      // Fetch songs from the cloud if already signed in
      _showLoadingDialog("Fetching your songs...");
      final fetchedSongs = await fetchSongsFromStorage();
      if (fetchedSongs.isNotEmpty) {
        updateSongs(fetchedSongs);
      }
      _hideLoadingDialog();

      return auth.currentUser;
    }
  }

    void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing the dialog
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Row(
            children: [
              const CircularProgressIndicator(color: Colors.teal),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _hideLoadingDialog() {
    Navigator.of(context, rootNavigator: true).pop(); // Close the dialog
  }

    void updateSongs(List<PlatformFile> fetchedSongs) {
    setState(() {
      _songs = fetchedSongs;
      if (_songs.isNotEmpty) {
        _currentSongIndex = 0;
        _currentSongTitle = _songs[0].name;
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

        

      // Check if the user is signed in and upload songs to the cloud
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _showLoadingDialog("Uploading songs to the cloud...");
        try {
          final uid = user.uid;
          final storageRef = FirebaseStorage.instance.ref().child('songs/$uid');
          final firestoreRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('songs');

          for (final file in newSongs) {
            if (file.bytes != null) {
              final fileName = file.name;
              final fileRef = storageRef.child(fileName);

              try {
                print("Uploading started for $fileName");

                // Start the upload task
                final uploadTask = fileRef.putData(file.bytes!);

                // Listen to the upload progress
                uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
                  final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
                  print("Upload is $progress% complete for $fileName");
                });

                // Wait for the upload to complete
                await uploadTask;
                print("Upload completed for $fileName");
              } catch (e) {
                print('Error uploading $fileName: $e');
              }
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Songs uploaded to the cloud.')),
          );
        } finally {
          _hideLoadingDialog();
        }
      } else {
        print("User is not signed in. Songs will only be stored locally.");
      }

      setState(() {
          if (wasListEmpty) { // If the list was empty, play the first of the newly added songs
            _currentSongIndex = 0; // This will be the first of the new batch
            _playSong(_currentSongIndex);
          } 
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
      await _audioPlayer.setSourceBytes(song.bytes as Uint8List); // Directly use the bytes
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
  } catch (e, s) {
    print("Error playing song '${song.name}': $e");
    print("Stack trace for '${song.name}':\n$s");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error playing song: ${song.name} - $e')),
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
    print("Stopped playback for removed playing song: $removedSongName");
  }

  // 2. Remove the song from the list
  _songs.removeAt(indexToRemove);
  print("Song $removedSongName removed. New song count: ${_songs.length}");

  // 3. Adjust _currentSongIndex and player state
  if (_songs.isEmpty) {
    _currentSongIndex = -1;
    _currentSongTitle = "No song selected";
  } else if (isCurrentlyPlayingSongRemoved) {
    _currentSongIndex = indexToRemove % _songs.length;
    if (_currentSongIndex >= _songs.length) _currentSongIndex = 0;
    _currentSongTitle = _songs[_currentSongIndex].name;
  } else if (_currentSongIndex > indexToRemove) {
    _currentSongIndex--;
  }

  setState(() {}); // Update the UI
}


@override
  Widget build(BuildContext context) {

    String? welcomeMessage;
    final user = FirebaseAuth.instance.currentUser;
    print("Current user: $user");

    if (user != null) {
      if (user.isAnonymous) {
        welcomeMessage = "Welcome, Anonymous";
      } else if (user.displayName != null && user.displayName!.isNotEmpty) {
        welcomeMessage = "Welcome, ${user.displayName}";
      } else if (user.email != null) {
        welcomeMessage = "Welcome, ${user.email}";
      }
  } else {
    welcomeMessage = null; // No message for guests
  }


    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Web Music Player by YZ & MM'), // Your custom title
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: _pickSongs,
            tooltip: 'Add Songs to Library',
          ),
          IconButton(
            icon: Icon(
              FirebaseAuth.instance.currentUser != null ? Icons.logout : Icons.login,
            ),
            onPressed: () async {
              if (FirebaseAuth.instance.currentUser != null) {
                // User is signed in, so sign out
                await FirebaseAuth.instance.signOut();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out successfully.')),
                );
                setState(() {
                  _songs.clear(); // Clear the song list on logout
                  _currentSongIndex = -1;
                  _currentSongTitle = "No song selected";
                });
              } else {
                // Navigate to the AuthScreen and wait for the result
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                );

                // If the result contains fetched songs, update the song list
                if (result is List<PlatformFile> && result.isNotEmpty) {
                  updateSongs(result);
                }
              }
            },
            tooltip: FirebaseAuth.instance.currentUser != null ? 'Sign Out' : 'Sign In',
          ),
          ],
        ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome Message
          if (welcomeMessage != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                welcomeMessage,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
            ),
          const SizedBox(height: 16), // Add spacing below the welcome message

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
