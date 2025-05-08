// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'loginpage.dart';
import 'models/chat_data.dart'; // For ChatMessageHiveAdapter, SavedChatSessionAdapter, RecentChatMetadataAdapter
import 'firebase_options.dart'; // ENSURE THIS FILE IS GENERATED

// Import screen files ONLY IF they define static consts for box names that you WILL use with HIVE.
import 'daily_quiz_screen.dart'; // Keep IF DailyQuizScreen.archivedQuizzesBoxName is defined AND you use Hive for it
// import 'stud_stats.dart'; // Not strictly needed here unless it defines its own box names

// --- Placeholder for Hive Models that might be defined later ---
// You would define these as @HiveType classes and generate adapters.
// For example, in a new file like lib/models/stats_data.dart

// @HiveType(typeId: 4) // Ensure unique typeId
// class ArchivedQuizMonth extends HiveObject { /* ... fields ... */ }
// class ArchivedQuizMonthAdapter extends TypeAdapter<ArchivedQuizMonth> { /* ... generated ... */ }

// Example models that might be used if StudStatsScreen had its own boxes
// @HiveType(typeId: 5)
// class QuizAnalysisResults extends HiveObject { /* ... fields ... */ }
// class QuizAnalysisResultsAdapter extends TypeAdapter<QuizAnalysisResults> { /* ... generated ... */ }

// @HiveType(typeId: 6)
// class ChatAnalysisResults extends HiveObject { /* ... fields ... */ }
// class ChatAnalysisResultsAdapter extends TypeAdapter<ChatAnalysisResults> { /* ... generated ... */ }


Future<void> main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("Firebase initialized successfully.");
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }

  // Initialize Hive for Flutter
  try {
    await Hive.initFlutter();
    debugPrint("Hive initialized successfully.");
  } catch (e) {
    debugPrint("Hive initialization failed: $e");
    return;
  }

  // --- Register Core Hive Adapters (from models/chat_data.dart) ---
  try {
    if (!Hive.isAdapterRegistered(ChatMessageHiveAdapter().typeId)) {
      Hive.registerAdapter(ChatMessageHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(SavedChatSessionAdapter().typeId)) {
      Hive.registerAdapter(SavedChatSessionAdapter());
    }
    if (!Hive.isAdapterRegistered(RecentChatMetadataAdapter().typeId)) {
      Hive.registerAdapter(RecentChatMetadataAdapter());
    }
    debugPrint("Core Hive adapters registered.");
  } catch (e) {
    debugPrint("Error registering core Hive adapters: $e");
    return;
  }

  // --- Register Additional Hive Adapters (Stats related - DEFINE THESE MODELS FIRST) ---
  // TODO: If you create Hive models for ArchivedQuizMonth, QuizAnalysisResults, etc.,
  //       define them, generate their adapters, and uncomment their registration here.
  /*
  // Example for ArchivedQuizMonth (if you use Hive for daily quiz archives)
  // Ensure ArchivedQuizMonthAdapter and its typeId are defined.
  // if (!Hive.isAdapterRegistered(ArchivedQuizMonthAdapter().typeId)) {
  //   Hive.registerAdapter(ArchivedQuizMonthAdapter());
  // }
  // ... and for other potential stats models
  */

  // --- Open All Necessary Hive Boxes ---
  try {
    // Common Boxes for MainScreen (from chat_data.dart models)
    if (!Hive.isBoxOpen('savedChats')) {
      await Hive.openBox<SavedChatSession>('savedChats');
    }
    if (!Hive.isBoxOpen('recentChats')) {
      await Hive.openBox<RecentChatMetadata>('recentChats');
    }
    if (!Hive.isBoxOpen('fullChats')) {
      await Hive.openBox<List<dynamic>>('fullChats');
    }

    // --- Daily Quiz Archive Box (OPTIONAL - if using Hive for this) ---
    // TODO: 1. Define `static const String archivedQuizzesBoxName = 'your_box_name';` in DailyQuizScreen.
    //       2. Define the `ArchivedQuizMonth` @HiveType model.
    //       3. Generate `ArchivedQuizMonthAdapter`.
    //       4. Register `ArchivedQuizMonthAdapter` above.
    //       5. Then uncomment and use this:
    /*
    try { // Add specific try-catch for optional boxes
      // Check if the constant is defined and not empty to prevent errors if not set up
      // This requires DailyQuizScreen to be imported and the constant to be defined.
      // A more robust way would be to pass box names as configurations if they are truly optional.
      const String dailyQuizArchiveBox = DailyQuizScreen.archivedQuizzesBoxName; // Access it first
      if (!Hive.isBoxOpen(dailyQuizArchiveBox)) {
         await Hive.openBox<ArchivedQuizMonth>(dailyQuizArchiveBox);
      }
    } catch (e) {
      // This specific catch can help identify if DailyQuizScreen.archivedQuizzesBoxName is the issue
      if (e.toString().contains("isn't defined for the type 'DailyQuizScreen'")) {
          debugPrint("Warning: DailyQuizScreen.archivedQuizzesBoxName is not defined. Skipping its Hive box.");
      } else {
          debugPrint("Error opening Daily Quiz archive box: $e");
      }
    }
    */


    // --- VVV REMOVE OR COMMENT OUT THESE LINES for StudStatsScreen boxes VVV ---
    // Since StudStatsScreen currently reads from SharedPreferences and doesn't define these
    // static box name constants, these lines will cause errors.
    /*
    // Make sure StudStatsScreen.quizAnalysisBoxName is a valid static const String
    if (!Hive.isBoxOpen(StudStatsScreen.quizAnalysisBoxName)) {
      await Hive.openBox<QuizAnalysisResults>(StudStatsScreen.quizAnalysisBoxName);
    }
    // Make sure StudStatsScreen.chatAnalysisBoxName is a valid static const String
    if (!Hive.isBoxOpen(StudStatsScreen.chatAnalysisBoxName)) {
      await Hive.openBox<ChatAnalysisResults>(StudStatsScreen.chatAnalysisBoxName);
    }
    */
    // --- ^^^ REMOVE OR COMMENT OUT THESE LINES for StudStatsScreen boxes ^^^ ---

    debugPrint("Core Hive boxes opened successfully.");
  } catch (e) {
    debugPrint("Error opening Hive boxes: $e");
    return; // Critical error
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Chat App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyanAccent,
          brightness: Brightness.dark,
          background: const Color(0xFF121212),
          surface: const Color(0xFF1E1E1E),
          onBackground: Colors.white.withOpacity(0.87),
          onSurface: Colors.white.withOpacity(0.87),
          primary: Colors.cyanAccent[200],
          secondary: Colors.tealAccent[200],
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}