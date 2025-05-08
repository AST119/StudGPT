// lib/mainscreen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard, HapticFeedback
import 'package:speech_to_text/speech_to_text.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:hive/hive.dart'; // Import Hive
import 'package:uuid/uuid.dart'; // Import Uuid
import 'package:hive_flutter/hive_flutter.dart'; // Needed for listenable boxes

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';// For Uint8List

// Ensure these imports point to the correct files
import 'sidemenu.dart';
import 'image_picker_service.dart';
import 'models/chat_data.dart'; // Import Hive models and helpers
import 'bookmarks.dart'; // Import bookmarks screen

const uuid = Uuid(); // Initialize uuid generator

// --- Data Structures & Enums --- (Defined outside the class)
enum Sender { user, bot }
enum MessageType { text, image, youtube, error, loading, code }

class ChatMessage {
  final Sender sender;
  final MessageType type;
  final String? text;
  final Uint8List? imageData;
  final String? imageUrl;
  final String? youtubeVideoId;
  // NON-FINAL fields to allow overwriting on load
  DateTime timestamp;
  String id;

  ChatMessage({
    required this.sender,
    required this.type,
    this.text,
    this.imageData,
    this.imageUrl,
    this.youtubeVideoId,
  })  : timestamp = DateTime.now(),
        id = uuid.v4();
}

// --- MainScreen Widget ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

// --- MainScreen State ---
class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  // --- State Variables ---
  // Controllers
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _menuAnimationController; // Initialized in initState

  // Services
  final ImagePickerService _imagePickerService = ImagePickerService();
  final SpeechToText _speechToText = SpeechToText();

  // UI State
  bool _isMenuOpen = false;
  bool _isStudZoneOpen = false;
  bool _isDarkMode = false; // Determined in initState
  bool _isOptionsPanelVisible = false;
  Timer? _showOptionsTimer; // For long-press options

  // Input State
  XFile? _pickedImage;
  Uint8List? _imageBytes;
  bool _canSend = false; // Derived state for enabling send button
  bool _isListening = false; // Speech input state
  String _lastWords = ''; // Last recognized speech

  // AI & Loading State
  bool _isLoading = false; // True when waiting for AI response
  bool _geminiInitialized = false; // True if Gemini models initialized ok
  bool _speechEnabled = false; // True if speech service initialized ok

  // Gemini SDK Variables (late initialized)
  final String _apiKey = 'AIzaSyBbJV4iAmnwq2eXJVtQmE8iOLlLCx6RAbU'; // <<< --- PASTE YOUR KEY HERE --- <<<
  late final GenerativeModel _textModel;
  late final GenerativeModel _visionModel;

  // Chat History & Persistence
  List<ChatMessage> _chatHistory = [];
  String? _currentChatId; // ID of the active chat in Hive
  bool _isChatSaved = false; // If the current chat matches a saved bookmark
  List<RecentChatMetadata> _recentChatsMetadata = []; // For side menu

  // Hive Boxes (late initialized - ensure opened in main.dart)
  late Box<SavedChatSession> _savedChatsBox;
  late Box<RecentChatMetadata> _recentChatsBox;
  late Box<List<dynamic>> _fullChatsBox;

  // Constants
  static const Duration _longPressDuration = Duration(seconds: 2);
  static const Duration _optionsPanelAnimationDuration = Duration(milliseconds: 250);
  static const double _optionsPanelHeight = 65.0;
  static const double _buttonRadius = 24.0;
  static const double _buttonSize = _buttonRadius * 2;
  static const double _inputRowPadding = 16.0;

  @override
  void initState() {
    super.initState();
    debugPrint("MainScreen initState: Starting initialization...");
    // Add listener to update _canSend state based on input changes
    _promptController.addListener(_updateCanSendState);
    // Initialize animation controller
    _menuAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // Start async initialization
    _initializeServicesAndHive();
  }

  // Handles all async initialization
  void _initializeServicesAndHive() async {
    debugPrint("MainScreen _initializeServicesAndHive: Running...");
    bool geminiOk = false;
    bool speechOk = false;

    try {
      // 1. Assign Hive Boxes (MUST be open already from main.dart)
      if (!Hive.isBoxOpen('savedChats') || !Hive.isBoxOpen('recentChats') || !Hive.isBoxOpen('fullChats')) {
        debugPrint("!!! FATAL: Hive boxes not open! Ensure they are opened in main.dart before runApp().");
        _showErrorSnackBar("Storage initialization failed. Please restart the app.");
        // Cannot proceed without storage
        if (mounted) setState(() { _geminiInitialized = false; _speechEnabled = false; });
        return;
      }
      _savedChatsBox = Hive.box<SavedChatSession>('savedChats');
      _recentChatsBox = Hive.box<RecentChatMetadata>('recentChats');
      _fullChatsBox = Hive.box<List<dynamic>>('fullChats');
      debugPrint("Hive boxes assigned.");

      // 2. Load initial recent chats metadata (requires boxes)
      _loadRecentChatsMetadata();

      // 3. Initialize Speech-to-Text
      speechOk = await _initSpeech(); // await the result

      // 4. Initialize Gemini Models
      debugPrint("Initializing Gemini...");
      if (_apiKey == 'YOUR_GEMINI_API_KEY' || _apiKey.isEmpty) {
        debugPrint("API Key is missing or placeholder.");
        _showErrorSnackBar("API Key not configured.");
        geminiOk = false;
      } else {
        try {
          // TODO: Add GenerationConfig and SafetySettings if needed
          _textModel = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
          _visionModel = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
          // Simple check (consider a test call for real confirmation)
          geminiOk = true;
          debugPrint("Gemini Models assigned (initialization seems ok).");
        } catch (e) {
          debugPrint("!!! Error initializing GenerativeModel: $e");
          _showErrorSnackBar("Failed to initialize AI Model. Check API Key/Network.");
          geminiOk = false;
        }
      }

      // 5. Determine initial dark mode
      try {
        // final Brightness platformBrightness = View.instance.platformDispatcher.platformBrightness; // Incorrect way
        // Use PlatformDispatcher.instance directly
        final Brightness platformBrightness = PlatformDispatcher.instance.platformBrightness; // <<< CORRECT WAY
        _isDarkMode = platformBrightness == Brightness.dark;
        debugPrint("Dark Mode initial state: $_isDarkMode (from PlatformDispatcher)");
      } catch(e) {
        // It's less likely PlatformDispatcher will throw here, but keep the catch
        debugPrint("!!! Error getting platform brightness: $e");
        // Default to light mode on error
        _isDarkMode = false;
        debugPrint("Defaulting Dark Mode state to false due to error.");
      }


    } catch (e) {
      debugPrint("!!! Critical error during initialization: $e");
      _showErrorSnackBar("Initialization failed: $e");
      geminiOk = false; // Ensure AI is marked as not ready
      speechOk = false; // Ensure speech is marked as not ready
    } finally {
      debugPrint("Initialization sequence complete.");
      // Update state after all async operations using final results
      if (mounted) {
        setState(() {
          _geminiInitialized = geminiOk;
          _speechEnabled = speechOk;
        });
        _updateCanSendState(); // Update button state based on final init results
        debugPrint("Final State: Gemini Ready: $_geminiInitialized, Speech Enabled: $_speechEnabled, Can Send: $_canSend");
      }
    }
  }

  // Listener for text field and image changes to update send button state
  void _updateCanSendState() {
    final bool hasInput = _promptController.text.isNotEmpty || _imageBytes != null;
    // Can send if: Gemini is ready AND not currently loading AND (has text OR has image)
    final newCanSend = _geminiInitialized && !_isLoading && hasInput;
    if (_canSend != newCanSend) {
      if (mounted) {
        setState(() {
          _canSend = newCanSend;
          // Debugging log for state change
          // debugPrint("Updated _canSend state: $_canSend (gemini: $_geminiInitialized, loading: $_isLoading, hasInput: $hasInput)");
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint("MainScreen disposing...");
    _promptController.removeListener(_updateCanSendState);
    _promptController.dispose();
    _showOptionsTimer?.cancel();
    _speechToText.stop();
    _menuAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- UI Feedback ---
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove previous snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- Speech Recognition ---
  Future<bool> _initSpeech() async { // Returns success status
    try {
      debugPrint("Initializing Speech...");
      bool available = await _speechToText.initialize(
          onError: (error) => debugPrint('!!! Speech init error: $error'),
          onStatus: (status) {
            debugPrint('Speech status: $status');
            if (mounted) {
              // Update _isListening based on the actual status from the plugin
              final currentlyListening = status == SpeechToText.listeningStatus;
              if (_isListening != currentlyListening) {
                setState(() => _isListening = currentlyListening);
              }
            }
          }
      );
      debugPrint("Speech initialization result: available=$available");
      return available; // Return the result
    } catch (e) {
      debugPrint("!!! Could not initialize speech recognition: $e");
      return false; // Return false on error
    }
  }

  void _startListening() async {
    debugPrint("Attempting to start listening...");
    // Ensure speech is enabled and Gemini is ready etc.
    if (!_speechEnabled || _speechToText.isListening || !_geminiInitialized || _isLoading) {
      _showErrorSnackBar("Cannot start listening now.");
      debugPrint("_startListening cancelled: enabled=$_speechEnabled, listening=${_speechToText.isListening}, gemini=$_geminiInitialized, loading=$_isLoading");
      return;
    }

    // Re-check availability in case service was stopped
    if (!_speechToText.isAvailable) {
      debugPrint("Speech not available, re-initializing...");
      bool reinitOk = await _initSpeech(); // Re-initialize
      if (!reinitOk) {
        _showErrorSnackBar("Speech recognition service unavailable.");
        return;
      }
    }

    // Clear previous input and set listening state
    if (mounted) {
      setState(() {
        _isListening = true;
        _lastWords = '';
        _promptController.clear();
        _updateCanSendState(); // Text cleared, update send state
      });
    }

    debugPrint("Calling speechToText.listen...");
    _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 45), // Longer listen duration
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        localeId: 'en_US',
        cancelOnError: true,
        listenMode: ListenMode.confirmation
    ).then((result) {
      debugPrint("speechToText.listen finished callback. Result: $result");
      // Ensure listening state is false if listen completes without error/cancellation
      if (mounted && result && !_speechToText.isListening) {
        setState(() => _isListening = false);
      }
    }).catchError((e){
      debugPrint("!!! Error during speech listener execution: $e");
      if (mounted) setState(() => _isListening = false);
    });
  }

  void _stopListening() async {
    if (!_speechToText.isListening) return;
    debugPrint("Stopping listening...");
    try {
      await _speechToText.stop();
      // Status callback should set _isListening to false
    } catch (e) {
      debugPrint("!!! Error stopping speech listener: $e");
      if (mounted) setState(() => _isListening = false); // Force state update
    }
  }

  void _onSpeechResult(result) {
    if (!mounted) return;
    final recognized = result.recognizedWords;
    final isFinal = result.finalResult;
    // debugPrint("Speech Result: '$recognized', final: $isFinal"); // Can be noisy

    setState(() {
      _lastWords = recognized;
      _promptController.text = _lastWords;
      _promptController.selection = TextSelection.fromPosition(
          TextPosition(offset: _promptController.text.length));
      // Ensure listening state is false ONLY when final result is confirmed
      if (isFinal) {
        _isListening = false;
        debugPrint("Final speech result received: '$recognized'");
      }
    });
    _updateCanSendState(); // Update send button state as text changes
  }

  // --- Image Picker ---
  Future<void> _pickImage() async {
    // Re-check conditions
    if (_isLoading || !_geminiInitialized) return;

    FocusScope.of(context).unfocus();
    _dismissOptionsPanel();
    debugPrint("Picking image...");

    final XFile? image = await _imagePickerService.pickImage();
    if (image != null) {
      debugPrint("Image picked: ${image.path}");
      final bytes = await image.readAsBytes();
      if (mounted) {
        setState(() {
          _pickedImage = image;
          _imageBytes = bytes;
          _updateCanSendState(); // Update button state
        });
      }
    } else {
      debugPrint("Image picking cancelled by user.");
    }
  }

  void _clearImageSelection() {
    if (mounted && !_isLoading) { // Can clear image even if AI isn't ready
      setState(() {
        _pickedImage = null;
        _imageBytes = null;
        _updateCanSendState();
      });
      debugPrint("Image selection cleared.");
    }
  }

  // --- Chat History & Persistence ---
  void _addMessageToChat(ChatMessage message, {bool isUserMessage = false}) async {
    // (Implementation from previous answers - assume correct logic for
    //  _currentChatId, Hive boxes, metadata, _isChatSaved updates)
    if (!mounted) return;

    String? initialChatId = _currentChatId;
    bool isNewChat = initialChatId == null && _chatHistory.isEmpty;

    // 1. Assign/Update Chat ID & Metadata
    if (isUserMessage && isNewChat && (message.text?.isNotEmpty == true || message.imageData != null) ) {
      _currentChatId = uuid.v4();
      debugPrint("Starting new chat with ID: $_currentChatId");
      String title = message.text?.isNotEmpty == true
          ? (message.text!.length > 30 ? '${message.text!.substring(0, 30)}...' : message.text!)
          : "Image Chat ${DateFormat('HH:mm').format(message.timestamp)}";

      final newMetadata = RecentChatMetadata.create( chatId: _currentChatId!, title: title, lastUpdated: message.timestamp,);

      if (_recentChatsBox.isOpen) {
        if (_recentChatsBox.length >= 10) { /* ... remove oldest logic ... */
          try {
            List<dynamic> keys = _recentChatsBox.keys.toList();
            List<RecentChatMetadata> sortedMetas = _recentChatsBox.values.toList()
              ..sort((a, b) => a.lastUpdated.compareTo(b.lastUpdated));
            if (sortedMetas.isNotEmpty) {
              var keyToDelete = keys.firstWhere((k) => (_recentChatsBox.get(k) as RecentChatMetadata?)?.chatId == sortedMetas.first.chatId, orElse: () => null);
              if (keyToDelete != null) await _recentChatsBox.delete(keyToDelete);
            }
          } catch (e) { debugPrint("Error removing oldest chat meta: $e"); }
        }
        await _recentChatsBox.add(newMetadata);
        _loadRecentChatsMetadata(); // Refresh list for side menu
      } else { debugPrint("Warning: _recentChatsBox closed, cannot add metadata."); }
      if(mounted) setState(() { _isChatSaved = false; });
    }

    // 2. Update UI State
    if (mounted) {
      setState(() {
        if (message.sender == Sender.bot && _chatHistory.isNotEmpty && _chatHistory.last.type == MessageType.loading) {
          _chatHistory.removeLast(); // Replace loading message
        }
        _chatHistory.add(message);
      });
    }
    _scrollToBottom();

    // 3. Persist message if conditions met
    if (_currentChatId != null && message.type != MessageType.loading && _fullChatsBox.isOpen) {
      final hiveMessage = ChatMessageHive.fromChatMessage(message);
      final List<dynamic> currentMessagesDynamic = _fullChatsBox.get(_currentChatId!, defaultValue: [])!;
      final List<ChatMessageHive> currentMessages = currentMessagesDynamic.cast<ChatMessageHive>().toList();
      currentMessages.add(hiveMessage);
      await _fullChatsBox.put(_currentChatId!, currentMessages);

      if (_recentChatsBox.isOpen) { /* ... update recent meta timestamp ... */
        final recentMetadataKey = _recentChatsBox.keys.cast<dynamic>().firstWhere( (key) => (_recentChatsBox.get(key) as RecentChatMetadata?)?.chatId == _currentChatId, orElse: () => null);
        if (recentMetadataKey != null) {
          final metadata = _recentChatsBox.get(recentMetadataKey) as RecentChatMetadata;
          metadata.lastUpdated = message.timestamp;
          await _recentChatsBox.put(recentMetadataKey, metadata);
          _loadRecentChatsMetadata(); // Re-sort list
        }
      }
    } else if (message.type != MessageType.loading) { debugPrint("Warning: Cannot persist msg. ID: $_currentChatId, BoxOpen: ${_fullChatsBox.isOpen}"); }

    // 4. Update save status
    if (_isChatSaved && _currentChatId != null && message.type != MessageType.loading) {
      if (mounted) setState(() => _isChatSaved = false);
    }
    // Update send button state AFTER message is added (esp. bot response)
    _updateCanSendState();
  }

  void _loadRecentChatsMetadata() {
    if (!mounted || !_recentChatsBox.isOpen) { return; }
    try {
      final List<RecentChatMetadata> recent = _recentChatsBox.values.toList()
        ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      if (mounted) {
        setState(() { _recentChatsMetadata = recent; });
        // debugPrint("Loaded ${_recentChatsMetadata.length} recent chat metadata items.");
      }
    } catch (e) {
      debugPrint("!!! Error loading/sorting recent chats metadata: $e");
      if (mounted) setState(() => _recentChatsMetadata = []);
    }
  }


  // --- Gemini Interaction ---
  Future<void> _sendMessage({required String prompt, required String mode}) async {
    final currentText = prompt.trim();
    final currentImageBytes = _imageBytes;

    // Final guard checks
    if (!_canSend || _isLoading) { // Use _canSend which includes geminiInit check
      debugPrint("_sendMessage blocked: canSend=$_canSend, isLoading=$_isLoading");
      return;
    }

    debugPrint("Sending message - Mode: $mode");
    FocusScope.of(context).unfocus();
    _dismissOptionsPanel();

    final userMessage = ChatMessage( /* ... create user message ... */
      sender: Sender.user, type: currentText.isNotEmpty ? MessageType.text : (currentImageBytes != null ? MessageType.image : MessageType.text), text: currentText.isNotEmpty ? currentText : null, imageData: currentImageBytes,
    );
    _addMessageToChat(userMessage, isUserMessage: true); // Add & persist user message

    // Clear inputs & SET LOADING STATE
    if (mounted) {
      setState(() {
        _promptController.clear(); _pickedImage = null; _imageBytes = null;
        _isLoading = true; // <<< START LOADING >>>
        _lastWords = '';
        _updateCanSendState(); // Update button state
      });
    }

    // Add visual loading indicator
    final loadingMessage = ChatMessage(sender: Sender.bot, type: MessageType.loading);
    if (mounted) { setState(() => _chatHistory.add(loadingMessage)); _scrollToBottom(); }

    // --- AI Call ---
    try {
      ChatMessage? botMessage;
      // ... (Switch statement for modes - Standard, Study, Code) ...
      // ... (Call internal generation helpers: _perform...Internal) ...
      // ... (Assign result to botMessage or handle multi-message modes like Study) ...
      switch (mode) {
        case 'Standard':
          debugPrint("Performing Standard Generation...");
          final response = await _performStandardGenerationInternal(currentText, currentImageBytes);
          if (response?.text != null && response!.text!.isNotEmpty) { botMessage = ChatMessage(sender: Sender.bot, type: MessageType.text, text: response.text!);
          } else { debugPrint("Standard gen returned null/empty."); botMessage = ChatMessage(sender: Sender.bot, type: MessageType.error, text: "Received no response or an empty response."); }
          break;
        case 'Study':
          debugPrint("Performing Study Generation...");
          await _performStudyGeneration(currentText); botMessage = null; // Adds messages internally
          break;
        case 'Code':
          debugPrint("Performing Code Generation...");
          final response = await _performCodeGenerationInternal(currentText);
          if (response?.text != null && response!.text!.isNotEmpty) { /* ... extract code ... */
            final codeBlockRegex = RegExp(r'```(?:[a-zA-Z]+)?\n([\s\S]*?)\n?```');
            final match = codeBlockRegex.firstMatch(response.text!);
            String codeContent = response.text!.trim();
            if (match != null && match.groupCount >= 1) { codeContent = match.group(1)!.trim();
            } else { debugPrint("Code gen no markdown block."); }
            botMessage = ChatMessage(sender: Sender.bot, type: MessageType.code, text: codeContent);
          } else { debugPrint("Code gen returned null/empty."); botMessage = ChatMessage(sender: Sender.bot, type: MessageType.error, text: "Could not generate code snippet."); }
          break;
        default:
          debugPrint("!!! Unknown send mode: $mode"); botMessage = ChatMessage(sender: Sender.bot, type: MessageType.error, text: "Internal error: Unknown mode.");
      }

      // Add final bot message (replaces loading state via _addMessageToChat logic)
      if (botMessage != null) { _addMessageToChat(botMessage); }
      // If study mode (no single botMessage), ensure loading indicator is removed anyway
      else if (mode == 'Study' && mounted && _chatHistory.any((m) => m.type == MessageType.loading)) {
        setState(() => _chatHistory.removeWhere((msg) => msg.type == MessageType.loading));
      }

    } catch (e) { // Catch errors from AI helpers or switch logic
      debugPrint("!!! Error during generation processing ($mode): $e");
      if (mounted) {
        final errorMessage = ChatMessage( sender: Sender.bot, type: MessageType.error, text: "An error occurred. Please try again.");
        _addMessageToChat(errorMessage); // Replaces loading
      }
    } finally { // *** CRITICAL: Always reset loading state ***
      debugPrint("Generation finished or failed for mode: $mode. Resetting loading state.");
      if (mounted) {
        setState(() {
          _isLoading = false; // <<< STOP LOADING >>>
          // Ensure loading message is gone if something went wrong before adding bot msg
          _chatHistory.removeWhere((msg) => msg.type == MessageType.loading);
          _updateCanSendState(); // Update button state
        });
      }
      _scrollToBottom();
    }
  }

  // --- Specific AI Generation Functions (Internal Helpers) ---
  // (Keep implementations from previous response - assuming they are correct)
  Future<GenerateContentResponse?> _performStandardGenerationInternal(String prompt, Uint8List? imageBytes) async { /* ... */
    if (!_geminiInitialized) return null;
    try { if (imageBytes != null) { final imagePart = DataPart('image/jpeg', imageBytes); final effectivePrompt = prompt.isEmpty ? "Describe this image." : prompt; final content = [ Content.multi([ TextPart(effectivePrompt), imagePart ]) ]; return await _visionModel.generateContent(content); } else { final content = [Content.text(prompt)]; return await _textModel.generateContent(content); }
    } catch (e) { debugPrint('!!! Standard Generation Error: $e'); return null; }
  }
  Future<void> _performStudyGeneration(String prompt) async {
    final String safePrompt = prompt.trim(); // Use trimmed prompt consistently
    if (safePrompt.isEmpty) {
      _addMessageToChat(ChatMessage(
          sender: Sender.bot,
          type: MessageType.error,
          text: "Please provide a topic for study mode."));
      return;
    }
    if (!_geminiInitialized) {
      _addMessageToChat(ChatMessage(
          sender: Sender.bot,
          type: MessageType.error,
          text: "AI Model not initialized. Cannot process study request."));
      return;
    }

    debugPrint("Study Generation: Fetching components for '$safePrompt'");

    // Define specific prompts for clarity
    const String notFoundImageMarker = "NO_IMAGE_FOUND";
    const String notFoundVideoMarker = "NO_VIDEO_FOUND";
    final String imagePrompt = "Provide exactly one relevant image URL for '$safePrompt'. Output *only* the URL. If no suitable image URL is found, output exactly '$notFoundImageMarker'.";
    final String youtubePrompt = "Provide exactly one relevant YouTube video URL for '$safePrompt'. Output *only* the URL (e.g., https://www.youtube.com/watch?v=...). If no suitable video URL is found, output exactly '$notFoundVideoMarker'.";
    final String explanationPrompt = "Explain clearly and concisely: '$safePrompt'";

    try {
      // Use Future.wait with slightly adjusted timeouts
      // Run explanation first as it's often the longest
      final explanationResult = await _generateContentHelper(explanationPrompt)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);

      // Add explanation (or error) immediately
      if (explanationResult?.isNotEmpty == true && mounted) {
        _addMessageToChat(ChatMessage(
            sender: Sender.bot, type: MessageType.text, text: explanationResult));
        debugPrint("Study Generation: Explanation added.");
      } else if (mounted) {
        _addMessageToChat(ChatMessage(
            sender: Sender.bot,
            type: MessageType.error,
            text: 'Could not fetch explanation for "$safePrompt". (Timeout or empty response)'));
        debugPrint("Study Generation: Explanation fetch failed or timed out.");
        // Still proceed to try fetching image/video
      }

      // Now fetch image and video concurrently
      final List<String?> mediaResults = await Future.wait([
        _generateContentHelper(imagePrompt)
            .timeout(const Duration(seconds: 18), onTimeout: () => null),
        _generateContentHelper(youtubePrompt)
            .timeout(const Duration(seconds: 18), onTimeout: () => null),
      ], eagerError: false); // Continue even if one fails

      final String? imageUrlResponse = mediaResults[0]?.trim();
      final String? youtubeUrlResponse = mediaResults[1]?.trim();

      // Process Image URL
      if (imageUrlResponse != null && imageUrlResponse.isNotEmpty && imageUrlResponse != notFoundImageMarker && mounted) {
        // Basic check if it looks like a URL
        if (Uri.tryParse(imageUrlResponse)?.hasAbsolutePath ?? false) {
          _addMessageToChat(ChatMessage(
              sender: Sender.bot,
              type: MessageType.image,
              imageUrl: imageUrlResponse)); // Use the raw response
          debugPrint("Study Generation: Image URL added: $imageUrlResponse");
        } else {
          _addMessageToChat(ChatMessage(
              sender: Sender.bot,
              type: MessageType.error,
              text: 'Received an invalid format for the image URL.'));
          debugPrint("Study Generation: Invalid image URL format received: $imageUrlResponse");
        }
      } else if (mounted) {
        _addMessageToChat(ChatMessage(
            sender: Sender.bot,
            type: MessageType.text, // Use text to convey the message clearly
            text: 'Could not find a relevant image for "$safePrompt".'));
        debugPrint("Study Generation: Image not found or fetch failed.");
      }

      // Process YouTube URL
      if (youtubeUrlResponse != null && youtubeUrlResponse.isNotEmpty && youtubeUrlResponse != notFoundVideoMarker && mounted) {
        // Use RegExp to extract video ID robustly
        final urlRegExp = RegExp(r'(?:https?://)?(?:www\.)?(?:youtube\.com/(?:watch\?v=|embed/|v/)|youtu\.be/)([\w-]+)(?:\S+)?'); // Allow potential extra chars after ID
        final match = urlRegExp.firstMatch(youtubeUrlResponse);

        if (match != null && match.groupCount >= 1) {
          String? videoId = match.group(1)?.trim();
          if (videoId?.isNotEmpty == true) {
            _addMessageToChat(ChatMessage(
                sender: Sender.bot,
                type: MessageType.youtube,
                youtubeVideoId: videoId!));
            debugPrint("Study Generation: YouTube Video ID added: $videoId");
          } else {
            _addMessageToChat(ChatMessage(
                sender: Sender.bot,
                type: MessageType.error,
                text: 'Found a YouTube link but could not extract the Video ID.'));
            debugPrint("Study Generation: Could not extract YT ID from: $youtubeUrlResponse");
          }
        } else {
          _addMessageToChat(ChatMessage(
              sender: Sender.bot,
              type: MessageType.error,
              text: 'Received an invalid format for the YouTube URL.'));
          debugPrint("Study Generation: Invalid YouTube URL format received: $youtubeUrlResponse");
        }
      } else if (mounted) {
        _addMessageToChat(ChatMessage(
            sender: Sender.bot,
            type: MessageType.text, // Use text
            text: 'Could not find a relevant YouTube video for "$safePrompt".'));
        debugPrint("Study Generation: YouTube video not found or fetch failed.");
      }

    } catch (e, stackTrace) { // Catch errors from Future.wait or helpers
      debugPrint('!!! Study Generation Error: $e\n$stackTrace');
      if (mounted) {
        _addMessageToChat(ChatMessage(
            sender: Sender.bot,
            type: MessageType.error,
            text: 'An unexpected error occurred while generating the study response.'));
      }
    }
    // No need for explicit loading removal here, as the `finally` block in
    // _sendMessage handles it after _performStudyGeneration completes.
    // Adding specific messages above ensures the loading indicator is replaced.
  }
  Future<GenerateContentResponse?> _performCodeGenerationInternal(String prompt) async { /* ... */
    if (prompt.trim().isEmpty) { _addMessageToChat(ChatMessage(sender: Sender.bot, type: MessageType.error, text: "Please provide description for code generation.")); return null; } if (!_geminiInitialized) return null;
    final codePrompt = "Generate only code for:\n$prompt\nOutput raw code, preferably in one markdown block.";
    try { final content = [Content.text(codePrompt)]; return await _textModel.generateContent(content); } catch (e) { debugPrint('!!! Code Generation Error: $e'); return null; }
  }
  Future<String?> _generateContentHelper(String prompt) async { /* ... */
    if (!_geminiInitialized) return null; try { final content = [Content.text(prompt)]; final response = await _textModel.generateContent(content); return response.text; } catch (e) { debugPrint("!!! Gemini Helper Error '$prompt': $e"); return null; }
  }

  // --- UI Management ---
  // ... (Keep _scrollToBottom, _startShowOptionsTimer, _cancelShowOptionsTimer, _dismissOptionsPanel) ...
  void _scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) { _scrollController.animateTo( _scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut,); }}); }
  void _startShowOptionsTimer() { _cancelShowOptionsTimer(); if (!_canSend || _isLoading || _isMenuOpen || _isOptionsPanelVisible) return; _showOptionsTimer = Timer(_longPressDuration, () { if (mounted && !_isOptionsPanelVisible && !_isMenuOpen) { HapticFeedback.mediumImpact(); setState(() => _isOptionsPanelVisible = true); }}); }
  void _cancelShowOptionsTimer() { _showOptionsTimer?.cancel(); }
  void _dismissOptionsPanel() { _cancelShowOptionsTimer(); if (_isOptionsPanelVisible && mounted) { setState(() => _isOptionsPanelVisible = false); } }

  // --- Menu and Dark Mode Toggles ---
  // ... (Keep _toggleMenu, _toggleStudZone, _toggleDarkMode) ...
  void _toggleMenu() { if (!mounted) return; FocusScope.of(context).unfocus(); _dismissOptionsPanel(); if (!_isMenuOpen && _recentChatsBox.isOpen) { _loadRecentChatsMetadata(); } setState(() { _isMenuOpen = !_isMenuOpen; if (_isMenuOpen) _menuAnimationController.forward(); else _menuAnimationController.reverse(); }); }
  void _toggleStudZone() { if (mounted) setState(() => _isStudZoneOpen = !_isStudZoneOpen); }
  void _toggleDarkMode() { if (mounted) setState(() => _isDarkMode = !_isDarkMode); /* TODO: Persist */ }

  // --- Sidemenu & Top Bar Actions ---
  // ... (Keep _handleNewChat, _handleNavigateToBookmarks, _handleSaveChat,
  //      _handleLoadPastChat, _loadSavedChat, _checkIfChatIsSaved,
  //      _findRecentChatIdForMessages from previous response) ...
  void _handleNewChat() { if (_isMenuOpen) _toggleMenu(); if (mounted) { setState(() { _chatHistory.clear(); _pickedImage = null; _imageBytes = null; _promptController.clear(); _isLoading = false; _isOptionsPanelVisible = false; _currentChatId = null; _isChatSaved = false; _lastWords = ''; _isListening = false; _updateCanSendState(); }); if(_speechToText.isListening) _stopListening(); } debugPrint("New Chat Started action handled."); }
  Future<void> _handleNavigateToBookmarks() async { if (_isMenuOpen) _toggleMenu(); final result = await Navigator.push<String?>( context, MaterialPageRoute(builder: (context) => const BookmarksScreen()),); if (result?.isNotEmpty == true && mounted) { _loadSavedChat(result!); } }
  Future<void> _handleSaveChat() async { if (_chatHistory.isEmpty || _isLoading) { _showErrorSnackBar("Cannot save empty/loading chat."); return; } if (_currentChatId == null && _chatHistory.isNotEmpty) { _showErrorSnackBar("Cannot save chat. ID missing."); return; } if (_isChatSaved) { _showSuccessSnackBar("Chat already saved."); return; } debugPrint("Saving chat..."); final firstMsg = _chatHistory.firstWhere((m) => m.sender == Sender.user && m.text?.isNotEmpty == true, orElse: () => _chatHistory.first); String title = firstMsg.text ?? "Chat ${DateFormat('MMM d').format(firstMsg.timestamp)}"; if (title.length > 50) title = '${title.substring(0, 50)}...'; try { final session = SavedChatSession.create(title: title, timestamp: DateTime.now(), messages: _chatHistory); if (_savedChatsBox.isOpen) { await _savedChatsBox.put(session.sessionId, session); if (mounted) setState(() => _isChatSaved = true); _showSuccessSnackBar("Chat saved!"); } else { _showErrorSnackBar("Failed to save (Storage Error)."); } } catch (e) { debugPrint("!!! Error saving chat: $e"); _showErrorSnackBar("Failed to save chat."); if (mounted) setState(() => _isChatSaved = false); } }
  Future<void> _handleLoadPastChat(String chatIdToLoad) async { if (_isLoading) { _showErrorSnackBar("Please wait."); return; } if (_isMenuOpen) _toggleMenu(); if (!mounted) return; if (_currentChatId == chatIdToLoad) { _showSuccessSnackBar("Chat already loaded."); return; } if (!_fullChatsBox.isOpen) { _showErrorSnackBar("Failed load (Storage Error)."); return; } final List<dynamic>? dynList = _fullChatsBox.get(chatIdToLoad); if (dynList?.isNotEmpty == true) { try { final List<ChatMessageHive> hiveList = dynList!.cast<ChatMessageHive>().toList(); final loaded = convertFromHiveMessages(hiveList); if (mounted) { setState(() { _chatHistory = loaded; _currentChatId = chatIdToLoad; _promptController.clear(); _pickedImage = null; _imageBytes = null; _isLoading = false; _isOptionsPanelVisible = false; _lastWords = ''; _isChatSaved = _checkIfChatIsSaved(loaded); _updateCanSendState(); }); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom()); _showSuccessSnackBar("Loaded past chat."); } } catch (e) { debugPrint("!!! Err loading past chat: $e"); _showErrorSnackBar("Failed load format."); _handleNewChat(); } } else { _showErrorSnackBar("Could not find chat."); _loadRecentChatsMetadata(); _handleNewChat(); } }
  Future<void> _loadSavedChat(String sessionId) async { if (_isLoading) { _showErrorSnackBar("Please wait."); return; } if (!mounted) return; if (!_savedChatsBox.isOpen) { _showErrorSnackBar("Failed load bookmark (Storage Error)."); return; } final session = _savedChatsBox.get(sessionId); if (session != null) { final loaded = convertFromHiveMessages(session.chatMessages); String? recentId = _findRecentChatIdForMessages(loaded); if (mounted) { setState(() { _chatHistory = loaded; _currentChatId = recentId; _promptController.clear(); _pickedImage = null; _imageBytes = null; _isLoading = false; _isOptionsPanelVisible = false; _isChatSaved = true; _lastWords = ''; _updateCanSendState(); }); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom()); _showSuccessSnackBar("Loaded bookmark."); } } else { _showErrorSnackBar("Failed load bookmark."); } }
  bool _checkIfChatIsSaved(List<ChatMessage> msgs) { if (msgs.isEmpty || !_savedChatsBox.isOpen) return false; final id = msgs.first.id; return _savedChatsBox.values.any((s) => s.chatMessages.isNotEmpty && s.chatMessages.first.id == id); }
  String? _findRecentChatIdForMessages(List<ChatMessage> msgs) { if (msgs.isEmpty || !_fullChatsBox.isOpen || !_recentChatsBox.isOpen) return null; final id = msgs.first.id; for (var meta in _recentChatsMetadata) { final List<dynamic>? chat = _fullChatsBox.get(meta.chatId); if (chat?.isNotEmpty == true) { try { if (chat!.first is ChatMessageHive && (chat.first as ChatMessageHive).id == id) return meta.chatId; } catch (e) { debugPrint("Err checking recent chat ${meta.chatId}: $e"); }}} return null; }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // --- Theme Setup --- (Define colors based on _isDarkMode)
    final Brightness currentBrightness = _isDarkMode ? Brightness.dark : Brightness.light;
    final ColorScheme colorScheme = ColorScheme.fromSeed( seedColor: _isDarkMode ? Colors.cyanAccent : Colors.blueAccent, brightness: currentBrightness,).copyWith(/* ... customizations ... */ background: _isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F7FA), surface: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white, surfaceVariant: _isDarkMode ? const Color(0xFF303030) : Colors.grey[200], onSurfaceVariant: _isDarkMode ? Colors.white70 : Colors.black87, primary: _isDarkMode ? Colors.cyanAccent[100] : Colors.blueAccent[700], onPrimary: _isDarkMode ? Colors.black : Colors.white, primaryContainer: _isDarkMode ? Colors.blueGrey[800] : Colors.blue[100], onPrimaryContainer: _isDarkMode ? Colors.lightBlue[100] : Colors.blue[900], outline: _isDarkMode ? Colors.grey[600] : Colors.grey[400], outlineVariant: _isDarkMode ? Colors.grey[700] : Colors.grey[300], error: _isDarkMode ? Colors.redAccent[100] : Colors.redAccent[700], onError: _isDarkMode ? Colors.black : Colors.white,);
    final Color textFieldBackgroundColor = _isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFE9EEF6);
    final Color textFieldTextColor = colorScheme.onSurface;
    final Color iconColor = colorScheme.onSurface.withOpacity(0.7);
    final Color chatBubbleUserColor = colorScheme.primaryContainer;
    final Color chatBubbleBotColor = colorScheme.surfaceVariant;
    final Color chatTextColorUser = colorScheme.onPrimaryContainer;
    final Color chatTextColorBot = colorScheme.onSurfaceVariant;
    final Color menuButtonSelectedColor = colorScheme.onSurface.withOpacity(0.1);
    final Color menuBackgroundColor = colorScheme.surface;
    final Color panelButtonColor = colorScheme.onSurface.withOpacity(0.8);
    final Color disabledButtonColor = Colors.grey.withOpacity(0.5); // Color for disabled state
    final Color disabledIconColor = Colors.white.withOpacity(0.7); // Color for icon on disabled button

    // --- UI Structure ---
    return Theme(
      data: ThemeData( colorScheme: colorScheme, useMaterial3: true, snackBarTheme: SnackBarThemeData( behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4,),),
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: Stack(
          children: [
            // --- Main Content Area ---
            GestureDetector( onTap: () { FocusScope.of(context).unfocus(); if (_isMenuOpen) _toggleMenu(); _dismissOptionsPanel(); },
              child: SafeArea( bottom: false,
                child: Padding( padding: const EdgeInsets.only( left: 12.0, right: 12.0, top: 8.0),
                  child: Column(
                    children: [
                      // --- Top Bar ---
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        IconButton( icon: Icon(Icons.menu, color: iconColor, size: 28), onPressed: _toggleMenu, tooltip: 'Open Menu',),
                        Text("StudGPT ", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onBackground)),
                        IconButton( icon: Icon( _isChatSaved ? Icons.bookmark_added : Icons.bookmark_border, color: _isChatSaved ? colorScheme.primary : iconColor, size: 28), onPressed: (_chatHistory.isEmpty || _isLoading) ? null : _handleSaveChat, tooltip: _isChatSaved ? 'Chat Saved' : 'Save Chat',),
                      ],
                      ),
                      const SizedBox(height: 8),
                      // --- Chat History ---
                      Expanded(
                        child: ListView.builder( controller: _scrollController, padding: EdgeInsets.only( bottom: 110 + MediaQuery.of(context).padding.bottom + (_isOptionsPanelVisible ? _optionsPanelHeight : 0)), itemCount: _chatHistory.length,
                          itemBuilder: (context, index) { if(index >= _chatHistory.length) return const SizedBox.shrink(); final message = _chatHistory[index]; return ChatBubble( key: ValueKey(message.id), message: message, userColor: chatBubbleUserColor, botColor: chatBubbleBotColor, userTextColor: chatTextColorUser, botTextColor: chatTextColorBot,); },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ), // End Main Content

            // --- Selected Image Preview (Positioned) ---
            if (_imageBytes != null) Positioned( bottom: 85 + MediaQuery.of(context).padding.bottom + (_isOptionsPanelVisible ? _optionsPanelHeight : 0), left: _inputRowPadding,
              child: Stack( alignment: Alignment.topRight, children: [ ClipRRect( borderRadius: BorderRadius.circular(8), child: Image.memory( _imageBytes!, height: 60, width: 60, fit: BoxFit.cover,),), GestureDetector( onTap: _clearImageSelection, child: Container( margin: const EdgeInsets.all(1), padding: const EdgeInsets.all(0), decoration: BoxDecoration( color: Colors.black.withOpacity(0.7), shape: BoxShape.circle,), child: const Icon(Icons.close, color: Colors.white, size: 14),),)],),
            ),

            // --- Input Area (Positioned) ---
            Positioned( left: 0, right: 0, bottom: 0,
              child: Material( color: colorScheme.background, elevation: _isOptionsPanelVisible ? 0 : 4.0,
                child: Padding( padding: EdgeInsets.only( left: _inputRowPadding, right: _inputRowPadding, bottom: MediaQuery.of(context).padding.bottom + 10, top: 10),
                  child: Row( crossAxisAlignment: CrossAxisAlignment.end, children: [
                    // Text Input Field
                    Expanded( child: Container( decoration: BoxDecoration( color: textFieldBackgroundColor, borderRadius: BorderRadius.circular(_buttonRadius), border: Border.all(color: colorScheme.outline.withOpacity(0.5), width: 0.5),),
                      child: TextField( controller: _promptController, style: TextStyle(color: textFieldTextColor, fontSize: 16), maxLines: 5, minLines: 1, textInputAction: TextInputAction.newline, keyboardType: TextInputType.multiline,
                        decoration: InputDecoration( hintText: 'Message Gemini...', hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)), contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14), border: InputBorder.none,
                          prefixIcon: IconButton( icon: Icon(Icons.add_photo_alternate_outlined, color: iconColor), onPressed: (_isLoading || !_geminiInitialized) ? null : _pickImage, tooltip: 'Attach Image',), // Attach Image
                          suffixIcon: IconButton( icon: Icon( _isListening ? Icons.mic : Icons.mic_none, color: _isListening ? colorScheme.primary : iconColor), onPressed: (_isLoading || !_geminiInitialized || !_speechEnabled) ? null : (_isListening ? _stopListening : _startListening), tooltip: _isListening ? 'Stop Listening' : (_speechEnabled ? 'Start Listening' : 'Speech unavailable'),), // Mic
                        ),
                      ),
                    ),
                    ),
                    const SizedBox(width: 8),
                    // Send Button
                    GestureDetector( onTap: _canSend ? () { if (_isOptionsPanelVisible) _dismissOptionsPanel(); else _sendMessage(prompt: _promptController.text, mode: 'Standard'); } : null,
                      onLongPressStart: (_) { if (_canSend) _startShowOptionsTimer(); }, onLongPressEnd: (_) => _cancelShowOptionsTimer(), onLongPressCancel: _cancelShowOptionsTimer,
                      child: Container( width: _buttonSize, height: _buttonSize, decoration: BoxDecoration( color: _canSend ? colorScheme.primary : disabledButtonColor, borderRadius: BorderRadius.circular(_buttonRadius),),
                        child: Center( child: _isLoading ? SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2.5, color: colorScheme.onPrimary)) : Icon( Icons.arrow_upward_rounded, color: _canSend ? colorScheme.onPrimary : disabledIconColor, size: 24,),),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ), // End Input Area

            // --- Sliding Options Panel ---
            AnimatedPositioned( duration: _optionsPanelAnimationDuration, curve: Curves.easeInOutQuad, bottom: _isOptionsPanelVisible ? (MediaQuery.of(context).padding.bottom + 70) : -(_optionsPanelHeight + 100), left: 0, right: 0, // Hide further down
              child: Material( elevation: 8.0, color: colorScheme.surface, borderRadius: const BorderRadius.only( topLeft: Radius.circular(20), topRight: Radius.circular(20),), shadowColor: Colors.black.withOpacity(0.2),
                child: Container( height: _optionsPanelHeight, padding: const EdgeInsets.symmetric(horizontal: _inputRowPadding), decoration: BoxDecoration( borderRadius: const BorderRadius.only( topLeft: Radius.circular(20), topRight: Radius.circular(20),), color: colorScheme.surface, border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),),
                  child: Row( mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.center, children: [
                    _buildOptionsPanelButton( label: 'Standard', icon: Icons.chat_bubble_outline, onPressed: () => _sendMessage(prompt: _promptController.text, mode: 'Standard'), color: panelButtonColor,),
                    _buildOptionsPanelButton( label: 'Study', icon: Icons.school_outlined, onPressed: () => _sendMessage(prompt: _promptController.text, mode: 'Study'), color: panelButtonColor,),
                    _buildOptionsPanelButton( label: 'Code', icon: Icons.code_outlined, onPressed: () => _sendMessage(prompt: _promptController.text, mode: 'Code'), color: panelButtonColor,),
                  ],
                  ),
                ),
              ),
            ), // End Options Panel

            // --- Side Menu ---
            if (_isMenuOpen) GestureDetector( onTap: _toggleMenu, child: Container(color: Colors.black.withOpacity(0.5)), ), // Dimming
            SlideTransition( position: Tween<Offset>( begin: const Offset(-1.0, 0.0), end: Offset.zero,).animate(CurvedAnimation( parent: _menuAnimationController, curve: Curves.easeInOutCubic,)),
              child: Align( alignment: Alignment.centerLeft,
                child: Sidemenu( isStudZoneOpen: _isStudZoneOpen, isDarkMode: _isDarkMode, recentChats: _recentChatsMetadata, onToggleMenu: _toggleMenu, onToggleStudZone: _toggleStudZone, onToggleDarkMode: _toggleDarkMode, onNewChat: _handleNewChat, onShowBookmarks: _handleNavigateToBookmarks, onLoadPastChat: _handleLoadPastChat, menuBackgroundColor: menuBackgroundColor, textFieldTextColor: textFieldTextColor, iconColor: iconColor, textFieldBackgroundColor: textFieldBackgroundColor, menuButtonSelectedColor: menuButtonSelectedColor,),
              ),
            ), // End Menu

          ], // End Stack Children
        ), // End Stack
      ), // End Scaffold
    ); // End Theme
  }

  // --- Helper Widget for Options Panel Buttons ---
  Widget _buildOptionsPanelButton({ required String label, required IconData icon, required VoidCallback onPressed, required Color color, }) {
    final bool isDisabled = !_canSend || _isLoading; // Disable if cannot send or currently loading
    final Color effectiveColor = isDisabled ? color.withOpacity(0.4) : color;
    return TextButton( style: TextButton.styleFrom( foregroundColor: effectiveColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(70, 55),),
      onPressed: isDisabled ? null : () { onPressed(); _dismissOptionsPanel(); }, // Dismiss panel on tap
      child: Column( mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(icon, size: 24, color: effectiveColor), const SizedBox(height: 4), Text( label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: effectiveColor), overflow: TextOverflow.ellipsis, maxLines: 1,),],),
    );
  }

} // End _MainScreenState


// --- ChatBubble Widget --- (No changes needed from previous version)
// ... (Keep the ChatBubble class definition as provided before) ...
class ChatBubble extends StatelessWidget { /* ... same as before ... */
  final ChatMessage message; final Color userColor; final Color botColor; final Color userTextColor; final Color botTextColor;
  const ChatBubble({ super.key, required this.message, required this.userColor, required this.botColor, required this.userTextColor, required this.botTextColor,});
  @override Widget build(BuildContext context) { bool isUser = message.sender == Sender.user; Color bubbleColor = isUser ? userColor : (message.type == MessageType.loading ? Colors.transparent : botColor); Color textColor = isUser ? userTextColor : botTextColor; Alignment alignment = isUser ? Alignment.centerRight : Alignment.centerLeft; BorderRadius borderRadius = isUser ? const BorderRadius.only( topLeft: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4), topRight: Radius.circular(16),) : const BorderRadius.only( topLeft: Radius.circular(4), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16), topRight: Radius.circular(16),); final theme = Theme.of(context); if (message.type == MessageType.loading) { return Align( alignment: Alignment.centerLeft, child: Padding( padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 18.0), child: SizedBox( width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary)),),); } return Align( alignment: alignment, child: Container( padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0), margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8), decoration: BoxDecoration( color: bubbleColor, borderRadius: borderRadius, boxShadow: (message.type != MessageType.loading) ? [ BoxShadow( color: Colors.black.withOpacity(0.06), blurRadius: 4.0, offset: const Offset(0, 2),),] : [], ), child: _buildMessageContent(context, textColor, bubbleColor, theme),),); }
  Widget _buildMessageContent(BuildContext context, Color textColor, Color bubbleColor, ThemeData theme) { final bool isDarkMode = theme.brightness == Brightness.dark; switch (message.type) { case MessageType.text: case MessageType.error: return SelectableText( message.text ?? (message.type == MessageType.error ? 'An error occurred.' : ''), style: TextStyle(color: textColor, fontSize: 15.5, height: 1.4),); case MessageType.image: if (message.imageUrl != null) { return Column( crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [ if (message.text != null && message.text!.isNotEmpty) Padding( padding: const EdgeInsets.only(bottom: 8.0), child: SelectableText(message.text!, style: TextStyle(color: textColor)),), ClipRRect( borderRadius: BorderRadius.circular(12), child: Image.network( message.imageUrl!, loadingBuilder: (context, child, loadingProgress) { if (loadingProgress == null) return child; return AspectRatio( aspectRatio: 16/9, child: Center( child: CircularProgressIndicator( strokeWidth: 2, value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null, color: theme.colorScheme.primary,),),); }, errorBuilder: (context, error, stackTrace) { debugPrint("Image load error: $error"); return Container( padding: const EdgeInsets.all(10), decoration: BoxDecoration( color: theme.colorScheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12),), child: Row( mainAxisSize: MainAxisSize.min, children: [ Icon(Icons.broken_image_outlined, color: theme.colorScheme.error, size: 20), const SizedBox(width: 8), Text('Image failed', style: TextStyle(color: theme.colorScheme.error)),]));},),),],); } else if (message.imageData != null) { return ClipRRect( borderRadius: BorderRadius.circular(12), child: Image.memory(message.imageData!, fit: BoxFit.contain));} return Text('[Invalid Image Data]', style: TextStyle(color: textColor, fontStyle: FontStyle.italic)); case MessageType.youtube: if (message.youtubeVideoId != null && message.youtubeVideoId!.isNotEmpty) { return YoutubePlayerBubble( key: ValueKey("youtube_${message.id}"), videoId: message.youtubeVideoId!, textColor: textColor, optionalText: message.text,);} return Text('[Invalid YouTube Video ID]', style: TextStyle(color: textColor, fontStyle: FontStyle.italic)); case MessageType.code: final String codeText = message.text ?? ''; final codeBackgroundColor = theme.colorScheme.onSurface.withOpacity(isDarkMode ? 0.15 : 0.08); final codeTextColor = theme.colorScheme.onSurface.withOpacity(0.9); return Container( decoration: BoxDecoration( color: codeBackgroundColor, borderRadius: BorderRadius.circular(8),), padding: const EdgeInsets.all(1.0), child: Column( mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [ Padding( padding: const EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 4), child: SelectableText( codeText, style: TextStyle( fontFamily: 'monospace', fontSize: 13.5, color: codeTextColor, height: 1.35,),),), Align( alignment: Alignment.centerRight, child: Padding( padding: const EdgeInsets.only(right: 4.0, bottom: 0), child: IconButton( icon: Icon(Icons.copy_all_rounded, size: 18, color: textColor.withOpacity(0.7)), tooltip: 'Copy Code', visualDensity: VisualDensity.compact, padding: const EdgeInsets.all(6), onPressed: () { Clipboard.setData(ClipboardData(text: codeText)); ScaffoldMessenger.of(context).showSnackBar( const SnackBar( content: Text('Code copied!'), duration: Duration(seconds: 1)),);},),),),],),); case MessageType.loading: return SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)); default: return Text('[Unsupported Message Type]', style: TextStyle(color: textColor, fontStyle: FontStyle.italic)); } }
}

// --- YoutubePlayerBubble Widget --- (No changes needed from previous version)
// ... (Keep the YoutubePlayerBubble class definition as provided before) ...
class YoutubePlayerBubble extends StatefulWidget { /* ... same as before ... */ final String videoId; final Color textColor; final String? optionalText; const YoutubePlayerBubble({ super.key, required this.videoId, required this.textColor, this.optionalText,}); @override _YoutubePlayerBubbleState createState() => _YoutubePlayerBubbleState();}
class _YoutubePlayerBubbleState extends State<YoutubePlayerBubble> { late YoutubePlayerController _controller; bool _showPlayer = false; @override void initState() { super.initState(); _controller = YoutubePlayerController( initialVideoId: widget.videoId, flags: const YoutubePlayerFlags( autoPlay: false, mute: false,),);} @override void dispose() { _controller.dispose(); super.dispose();} @override Widget build(BuildContext context) { final theme = Theme.of(context); final ColorScheme colorScheme = theme.colorScheme; return Column( crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [ if (widget.optionalText != null && widget.optionalText!.isNotEmpty) Padding( padding: const EdgeInsets.only(bottom: 8.0), child: SelectableText(widget.optionalText!, style: TextStyle(color: widget.textColor)),), AnimatedCrossFade( duration: const Duration(milliseconds: 300), crossFadeState: _showPlayer ? CrossFadeState.showSecond : CrossFadeState.showFirst, firstChild: GestureDetector( onTap: () { if (mounted) setState(() => _showPlayer = true); }, child: Stack( alignment: Alignment.center, children: [ ClipRRect( borderRadius: BorderRadius.circular(12), child: Image.network( YoutubePlayer.getThumbnail(videoId: widget.videoId), fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : AspectRatio(aspectRatio: 16/9, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))), errorBuilder: (context, error, stack) => AspectRatio( aspectRatio: 16/9, child: Container( decoration: BoxDecoration( color: Colors.grey[300], borderRadius: BorderRadius.circular(12)), child: Icon(Icons.play_circle_outline, color: Colors.grey[700], size: 40,))),),), Container( decoration: BoxDecoration( color: Colors.black.withOpacity(0.6), shape: BoxShape.circle,), padding: const EdgeInsets.all(10), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),)],),), secondChild: ClipRRect( borderRadius: BorderRadius.circular(12), child: YoutubePlayer( controller: _controller, showVideoProgressIndicator: true, progressIndicatorColor: colorScheme.primary, progressColors: ProgressBarColors( playedColor: colorScheme.primary, handleColor: colorScheme.primary.withOpacity(0.8), bufferedColor: colorScheme.primary.withOpacity(0.3),),),),),],); }
}