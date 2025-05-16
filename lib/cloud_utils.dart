// filepath: /home/sinda/9raya/flutter/latest/music_app_flutter-main/lib/cloud_utils.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

Future<List<PlatformFile>> fetchSongsFromStorage() async {
  print("Fetching songs from Firebase Storage...");
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    print('No user signed in.');
    return [];
  }

  final uid = user.uid;
  final storageRef = FirebaseStorage.instance.ref().child('songs/$uid');

  try {
    // List all files in the user's folder
    final ListResult result = await storageRef.listAll();
    final List<PlatformFile> fetchedSongs = [];

    for (final Reference fileRef in result.items) {
      final fileName = fileRef.name;

      try {
        // Fetch the file bytes
        final fileBytes = await fileRef.getData();
        if (fileBytes != null) {
          fetchedSongs.add(PlatformFile(
            name: fileName,
            bytes: fileBytes,
            size: fileBytes.length,
          ));
          print("Fetched file: $fileName (${fileBytes.length} bytes)");
        } else {
          print("Failed to fetch bytes for file: $fileName");
        }
      } catch (e) {
        print("Error fetching file bytes for $fileName: $e");
      }
    }

    print('Fetched ${fetchedSongs.length} songs from Firebase Storage.');
    return fetchedSongs;
  } catch (e) {
    print('Error fetching songs from Firebase Storage: $e');
    return [];
  }
}