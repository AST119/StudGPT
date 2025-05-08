import 'package:flutter/material.dart'; // Optional, but good for context or future UI interaction
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  /// Picks an image from the specified [source].
  ///
  /// Defaults to picking from the gallery.
  /// Returns the selected [XFile] or null if no image was selected or an error occurred.
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85, // Optionally compress the image slightly
        // maxWidth: 1000, // Optionally set max width
        // maxHeight: 1000, // Optionally set max height
      );
      return pickedFile;
    } catch (e) {
      // Log the error or handle it appropriately (e.g., show a snackbar)
      debugPrint("Error picking image: $e");
      // Depending on the error type, you might want to check permissions specifically
      // e.g., if (e is PlatformException && e.code == 'photo_access_denied') { ... }
      return null;
    }
  }

// Optional: Add a method for picking video if needed later
/*
  Future<XFile?> pickVideo({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60), // Optional duration limit
      );
      return pickedFile;
    } catch (e) {
      debugPrint("Error picking video: $e");
      return null;
    }
  }
  */

// Optional: Add a method for picking multiple images if needed later
/*
  Future<List<XFile>?> pickMultipleImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 85,
        // maxWidth: 1000,
        // maxHeight: 1000,
      );
      return pickedFiles;
    } catch (e) {
      debugPrint("Error picking multiple images: $e");
      return null; // Return null or empty list on error
    }
  }
  */
}