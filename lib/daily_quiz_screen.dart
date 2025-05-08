// lib/daily_quiz_screen.dart

import 'dart:convert'; // For jsonDecode, jsonEncode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // For date formatting

import 'gemini_service.dart'; // Assuming this is in the same directory or correctly imported

class DailyQuizScreen extends StatefulWidget {
  const DailyQuizScreen({Key? key}) : super(key: key);

  // Static keys for SharedPreferences, accessible from stud_stats.dart
  static const String prefTopic = 'dailyQuiz_topic_v2';
  static const String prefTopicDate = 'dailyQuiz_topicSelectionDate_v2';
  static const String prefQuestions = 'dailyQuiz_structuredQuestions_v2';
  static const String prefAnswers = 'dailyQuiz_userAnswers_v2';
  static const String prefAnswersCorrectness = 'dailyQuiz_userAnswersCorrectness_v3';
  static const String prefAnswersFeedback = 'dailyQuiz_userAnswersFeedback_v3';
  static const String prefAttemptStreak = 'dailyQuiz_attemptStreak_v2';
  static const String prefWinningStreak = 'dailyQuiz_winningStreak_v2';
  static const String prefLastArchivedMonth = 'dailyQuiz_lastArchivedMonth_v1'; // YYYY-MM
  static const String archivedQuizzesBoxName = 'archived_daily_quizzes_box';

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> {
  // --- State Variables ---
  String? _selectedTopic;
  int _currentDay = 1;
  List<Map<String, dynamic>> _questions = [];
  List<String?> _userAnswers = List.filled(30, null);
  List<bool?> _userAnswersCorrectness = List.filled(30, null);
  List<String?> _userAnswersFeedback = List.filled(30, null);
  int _attemptStreak = 0;
  int _winningStreak = 0;
  bool _isAnswerSubmittedToday = false;
  bool _isCorrectAnswerToday = false;
  bool _isLoading = true;
  bool _isCheckingAnswer = false;
  bool _isGeneratingQuestions = false;
  bool _quizCompleted = false;
  String? _correctAnswerForFeedback;
  DateTime? _topicSelectionDate;

  bool get _hasSubmittedAnswerForCurrentDay =>
      _currentDay > 0 &&
          _currentDay <= _userAnswers.length &&
          _userAnswers[_currentDay - 1] != null;

  bool get _isSubmitButtonEnabled =>
      !_hasSubmittedAnswerForCurrentDay &&
          !_isCheckingAnswer &&
          !_isGeneratingQuestions &&
          !_isLoading;

  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _answerController = TextEditingController();

  final String apiKey = 'AIzaSyBbJV4iAmnwq2eXJVtQmE8iOLlLCx6RAbU'; // <--- REPLACE
  late final GeminiService _geminiService;


  @override
  void initState() {
    super.initState();
    _userAnswers = List.filled(30, null);
    _userAnswersCorrectness = List.filled(30, null);
    _userAnswersFeedback = List.filled(30, null);
    _geminiService = GeminiService(apiKey);
    _initializeQuiz();
  }

  @override
  void dispose() {
    _topicController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _initializeQuiz() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadData();
    await _calculateCurrentDayAndStatus(); // Make it awaitable
    if (_selectedTopic != null &&
        _selectedTopic!.isNotEmpty &&
        _questions.isEmpty &&
        !_quizCompleted) {
      await _generateQuestions();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedTopic = prefs.getString(DailyQuizScreen.prefTopic);
      final dateString = prefs.getString(DailyQuizScreen.prefTopicDate);
      _topicSelectionDate = dateString != null && dateString.isNotEmpty
          ? DateTime.tryParse(dateString)
          : null;

      final List<String> loadedQuestionsJson =
          prefs.getStringList(DailyQuizScreen.prefQuestions) ?? [];

      if (_selectedTopic == null || _selectedTopic!.isEmpty || loadedQuestionsJson.isEmpty) {
        _questions = [];
      } else {
        _questions = loadedQuestionsJson.map((jsonString) {
          try {
            return jsonDecode(jsonString) as Map<String, dynamic>;
          } catch (e) {
            debugPrint("Error decoding question JSON: $e, String: $jsonString");
            return {'question': 'Error loading question', 'code_snippet': null};
          }
        }).toList();

        if (_questions.length != 30 && _questions.isNotEmpty) {
          debugPrint("Warning: Loaded ${_questions.length} questions, expected 30. Clearing to regenerate.");
          _questions = [];
        }
      }

      _userAnswers = List.filled(30, null);
      List<String> loadedAnswers = prefs.getStringList(DailyQuizScreen.prefAnswers) ?? [];
      for (int i = 0; i < 30; i++) {
        if (i < loadedAnswers.length && loadedAnswers[i] != 'null' && loadedAnswers[i].isNotEmpty) {
          _userAnswers[i] = loadedAnswers[i];
        }
      }

      _userAnswersCorrectness = List.filled(30, null);
      List<String> loadedCorrectness = prefs.getStringList(DailyQuizScreen.prefAnswersCorrectness) ?? [];
      for (int i = 0; i < 30; i++) {
        if (i < loadedCorrectness.length) {
          if (loadedCorrectness[i] == 'true') _userAnswersCorrectness[i] = true;
          else if (loadedCorrectness[i] == 'false') _userAnswersCorrectness[i] = false;
          else _userAnswersCorrectness[i] = null;
        }
      }

      _userAnswersFeedback = List.filled(30, null);
      List<String> loadedFeedback = prefs.getStringList(DailyQuizScreen.prefAnswersFeedback) ?? [];
      for (int i = 0; i < 30; i++) {
        if (i < loadedFeedback.length && loadedFeedback[i] != 'null' && loadedFeedback[i].isNotEmpty) {
          _userAnswersFeedback[i] = loadedFeedback[i];
        }
      }
      _attemptStreak = prefs.getInt(DailyQuizScreen.prefAttemptStreak) ?? 0;
      _winningStreak = prefs.getInt(DailyQuizScreen.prefWinningStreak) ?? 0;
    } catch (e) {
      debugPrint("Error loading daily quiz data: $e");
      if (mounted) _showErrorSnackBar("Failed to load quiz data.");
      _resetQuizState(clearTopic: true);
      await _saveData();
    }
  }

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DailyQuizScreen.prefTopic, _selectedTopic ?? '');
      await prefs.setString(DailyQuizScreen.prefTopicDate, _topicSelectionDate?.toIso8601String() ?? '');
      final List<String> questionsJson = _questions.map((q) => jsonEncode(q)).toList();
      await prefs.setStringList(DailyQuizScreen.prefQuestions, questionsJson);
      await prefs.setStringList(DailyQuizScreen.prefAnswers, _userAnswers.map((e) => e ?? 'null').toList());
      await prefs.setStringList(
        DailyQuizScreen.prefAnswersCorrectness,
        _userAnswersCorrectness.map((c) => c == true ? 'true' : (c == false ? 'false' : 'null')).toList(),
      );
      await prefs.setStringList(DailyQuizScreen.prefAnswersFeedback, _userAnswersFeedback.map((f) => f ?? 'null').toList());
      await prefs.setInt(DailyQuizScreen.prefAttemptStreak, _attemptStreak);
      await prefs.setInt(DailyQuizScreen.prefWinningStreak, _winningStreak);
    } catch (e) {
      debugPrint("Error saving daily quiz data: $e");
      if (mounted) _showErrorSnackBar("Failed to save quiz progress.");
    }
  }

  Future<void> _generateQuestions() async {
    if (_selectedTopic == null || _selectedTopic!.isEmpty || !mounted) return;
    if (mounted) setState(() => _isGeneratingQuestions = true);
    bool generationSuccessful = false;
    String currentTopicForErrorMessage = _selectedTopic!;

    try {
      final prompt = """
      Generate exactly 30 unique questions about '$currentTopicForErrorMessage'.The difficulty might be mentioned. So generate question based on entered difficulty in prompt, if not then choose difficulty as easy.
      Respond ONLY with a single valid JSON array where each element is an object.
      Each object must have two keys:
      1. "question": A string containing the question text (be concise and clear).
      2. "code_snippet": A string containing code snippet (use markdown backticks for formatting if possible, e.g., ```dart\\ncode here\\n```), or null if no code is needed for the question.
      Example format of the array:
      [
        {"question": "What is Flutter?", "code_snippet": null},
        {"question": "Explain this Dart code's output:", "code_snippet": "```dart\\nvoid main() {\\n  print('Hello');\\n}```"}
      ]
      Ensure the output is only the JSON array and nothing else. Do not add introductory text or explanations outside the JSON.
      """;

      String response = await _geminiService.getGeminiResponse(prompt);
      debugPrint("Gemini structured questions raw response string: $response");
      List<Map<String, dynamic>> tempParsedQuestions = [];
      try {
        final cleanedResponse = response.replaceAll('```json', '').replaceAll('```', '').trim();
        final decodedJson = jsonDecode(cleanedResponse);
        if (decodedJson is! List) {
          throw FormatException("AI response was not a JSON list. Received: ${decodedJson.runtimeType}");
        }
        final decodedList = decodedJson as List<dynamic>;
        tempParsedQuestions = decodedList.map((item) {
          if (item is Map<String, dynamic> && item.containsKey('question') && item['question'] is String) {
            String? snippet = item['code_snippet'] as String?;
            if (snippet != null) {
              snippet = snippet.trim();
              if (snippet.startsWith('```') && snippet.endsWith('```')) {
                snippet = snippet.substring(3, snippet.length - 3).trim();
                snippet = snippet.replaceFirst(RegExp(r'^[a-zA-Z]+\s*\n'), '');
              }
            }
            return {'question': item['question'] as String, 'code_snippet': snippet?.isEmpty ?? true ? null : snippet,};
          }
          debugPrint("Invalid item format in JSON array: $item");
          throw FormatException("Invalid question format received from AI: $item");
        }).toList();
        if (tempParsedQuestions.length < 30) throw Exception("AI provided ${tempParsedQuestions.length} questions, but 30 were required.");
        if (tempParsedQuestions.length > 30) tempParsedQuestions = tempParsedQuestions.sublist(0, 30);
        _questions = tempParsedQuestions;
        _userAnswers = List.filled(30, null);
        _userAnswersCorrectness = List.filled(30, null);
        _userAnswersFeedback = List.filled(30, null);
        generationSuccessful = true;
      } catch (e) {
        debugPrint("Error parsing/validating Gemini questions: $e\nRaw response: $response");
        throw Exception("Failed to process questions from AI. Details: $e");
      }
      if (generationSuccessful) {
        await _saveData();
        debugPrint("Generated and saved ${_questions.length} questions for topic: $currentTopicForErrorMessage");
      }
    } catch (e) {
      debugPrint("Overall error generating questions for '$currentTopicForErrorMessage': $e");
      if (mounted) _showErrorSnackBar("Could not generate quiz for '$currentTopicForErrorMessage'. Please check connection/topic.");
    } finally {
      if (mounted) {
        setState(() {
          if (!generationSuccessful) _resetQuizState(clearTopic: true);
          _isGeneratingQuestions = false;
        });
        if (!generationSuccessful) await _saveData();
      }
    }
  }

  Future<void> _calculateCurrentDayAndStatus() async { // Made async
    if (_topicSelectionDate == null || _selectedTopic == null || _selectedTopic!.isEmpty) {
      _currentDay = 1; _quizCompleted = false; _isAnswerSubmittedToday = false;
      _isCorrectAnswerToday = false; _correctAnswerForFeedback = null;
      if (mounted) setState(() {}); return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectionDate = DateTime(_topicSelectionDate!.year, _topicSelectionDate!.month, _topicSelectionDate!.day);
    final difference = today.difference(selectionDate).inDays;
    int newCalculatedDay; bool newQuizCompleted = false;

    if (difference < 0) {
      // Topic date is in the future, implies a clock change or error
      if (_selectedTopic != null && _topicSelectionDate != null && _questions.isNotEmpty) { // Only archive if there's valid data
        await _archiveCurrentMonthData();
      }
      _resetQuizState(clearTopic: true);
      newCalculatedDay = 1;
      newQuizCompleted = false; // Ensure quiz is not marked completed
      await _saveData(); // Save the reset state
    } else if (difference < 29) { // Day 1 to Day 29 (0 to 28 difference)
      newCalculatedDay = difference + 1;
    } else { // Day 30 or beyond (difference 29+)
      newCalculatedDay = 30;
      if (!_quizCompleted) { // Only archive if it wasn't already marked as completed
        newQuizCompleted = true;
        if (_selectedTopic != null && _topicSelectionDate != null && _questions.length == 30) {
          await _archiveCurrentMonthData();
        }
      } else {
        newQuizCompleted = true; // Keep it completed if already was
      }
    }
    _currentDay = newCalculatedDay;
    _quizCompleted = newQuizCompleted;
    _isAnswerSubmittedToday = false; _isCorrectAnswerToday = false; _correctAnswerForFeedback = null;

    if (!_quizCompleted && _currentDay > 0 && _currentDay <= 30) {
      final questionIndex = _currentDay - 1;
      if (_userAnswers[questionIndex] != null) {
        _isAnswerSubmittedToday = true;
        if (questionIndex < _userAnswersCorrectness.length && _userAnswersCorrectness[questionIndex] != null) {
          _isCorrectAnswerToday = _userAnswersCorrectness[questionIndex]!;
        }
        if (!_isCorrectAnswerToday && questionIndex < _userAnswersFeedback.length) {
          _correctAnswerForFeedback = _userAnswersFeedback[questionIndex];
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _selectTopic() async {
    if (_topicController.text.trim().isEmpty) {
      _showErrorSnackBar("Please enter a topic."); return;
    }
    final newTopic = _topicController.text.trim();
    _topicController.clear(); FocusScope.of(context).unfocus();
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _resetQuizState(clearTopic: false);
      _selectedTopic = newTopic;
      _topicSelectionDate = DateTime.now();
      // Optionally reset streaks for a new topic
      // _attemptStreak = 0; _winningStreak = 0;
    });
    await _generateQuestions();
    if (mounted) {
      setState(() => _isLoading = false);
      await _calculateCurrentDayAndStatus(); // Make it awaitable
    }
  }

  Future<void> _submitAnswer() async {
    if (_answerController.text.trim().isEmpty) {
      _showErrorSnackBar("Please enter an answer."); return;
    }
    if (!_isSubmitButtonEnabled || _currentDay <= 0 || _currentDay > 30) return;
    final userAnswer = _answerController.text.trim();
    final questionIndex = _currentDay - 1;
    if (questionIndex < 0 || questionIndex >= _questions.length) {
      _showErrorSnackBar("Error: Cannot find the current question data."); return;
    }
    final currentQuestionData = _questions[questionIndex];
    final String currentQuestionText = currentQuestionData['question'] as String? ?? 'Error: Invalid question text';
    final String? currentCodeSnippet = currentQuestionData['code_snippet'] as String?;
    FocusScope.of(context).unfocus();
    if (!mounted) return;
    setState(() {
      _userAnswers[questionIndex] = userAnswer; _isAnswerSubmittedToday = true;
      _isCheckingAnswer = true; _attemptStreak++; _correctAnswerForFeedback = null;
      _isCorrectAnswerToday = false;
    });
    Map<String, dynamic> evaluationResult = await _checkAnswerWithGemini(currentQuestionText, userAnswer, currentCodeSnippet);
    if (!mounted) return;
    bool isCorrect = evaluationResult['is_correct'] as bool;
    String correctAnswerFeedback = evaluationResult['correct_answer'] as String;
    _userAnswersCorrectness[questionIndex] = isCorrect;
    if (!isCorrect) _userAnswersFeedback[questionIndex] = correctAnswerFeedback;
    else _userAnswersFeedback[questionIndex] = null;
    setState(() {
      _isCorrectAnswerToday = isCorrect; _correctAnswerForFeedback = correctAnswerFeedback;
      if (isCorrect) _winningStreak++; else _winningStreak = 0;
      _isCheckingAnswer = false;
    });
    _answerController.clear();
    await _saveData();
  }

  Future<Map<String, dynamic>> _checkAnswerWithGemini(String questionText, String userAnswer, String? codeSnippet) async {
    if (!mounted) return {'is_correct': false, 'correct_answer': 'Error: Widget not mounted.'};
    const String jsonFormatInstruction = """Respond ONLY with a valid JSON object matching this structure: {\"is_correct\": boolean, \"correct_answer\": \"string (Provide the ideal concise answer)\"}. Ensure the output is only the JSON object.""";
    String promptContext = 'Question: $questionText';
    if (codeSnippet != null && codeSnippet.isNotEmpty) promptContext += '\nCode provide with question:\n```\n$codeSnippet\n```';
    promptContext += '\nUser\'s Answer: $userAnswer';
    final prompt = "Evaluate the following answer. Also make sure if the question contains code check if the answer is output of the code if it is correct output and the answer do not contain theory answer should still be considered correct\n$promptContext\n$jsonFormatInstruction";
    Map<String, dynamic> result = {'is_correct': false, 'correct_answer': 'Could not determine the correct answer.'};
    debugPrint("--- Sending Evaluation Prompt to Gemini ---\n$prompt\n-----------------------------------------");
    try {
      final responseString = await _geminiService.getGeminiResponse(prompt);
      debugPrint("Gemini JSON evaluation response string: $responseString");
      try {
        final cleanedResponse = responseString.replaceAll('```json', '').replaceAll('```', '').trim();
        final jsonStart = cleanedResponse.indexOf('{'); final jsonEnd = cleanedResponse.lastIndexOf('}');
        if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
          final potentialJson = cleanedResponse.substring(jsonStart, jsonEnd + 1);
          final decodedJson = jsonDecode(potentialJson) as Map<String, dynamic>;
          final bool? isCorrect = decodedJson['is_correct'] as bool?;
          final String? correctAnswer = decodedJson['correct_answer'] as String?;
          if (isCorrect != null) {
            result['is_correct'] = isCorrect;
            result['correct_answer'] = correctAnswer?.trim() ?? 'Answer not provided by AI.';
          } else {
            debugPrint("Error parsing Gemini JSON: 'is_correct' field missing or not a bool.");
            result['correct_answer'] = 'Error parsing AI evaluation (missing bool).';
          }
        } else {
          debugPrint("Error parsing Gemini JSON: Could not find valid JSON object markers.");
          result['correct_answer'] = 'Error parsing AI evaluation response format.';
        }
      } catch (e) {
        debugPrint("Error parsing Gemini JSON response: $e\nRaw response: $responseString");
        result['correct_answer'] = 'Error parsing AI evaluation response.';
        if (responseString.isNotEmpty && !responseString.contains("Error")) result['correct_answer'] += "\nAI Raw: $responseString";
      }
    } catch (e) {
      debugPrint("Error calling Gemini for answer evaluation: $e");
      if (mounted) _showErrorSnackBar("Failed to verify answer via AI.");
      result['correct_answer'] = 'Failed to contact AI for verification.';
    }
    return result;
  }

  void _resetQuizState({required bool clearTopic}) {
    if (clearTopic) {
      _selectedTopic = null; _topicSelectionDate = null; _topicController.clear();
    }
    _currentDay = 1; _questions = [];
    _userAnswers = List.filled(30, null);
    _userAnswersCorrectness = List.filled(30, null);
    _userAnswersFeedback = List.filled(30, null);
    // Reset streaks only when topic is cleared or explicitly on a full reset.
    if (clearTopic) {
      _attemptStreak = 0; _winningStreak = 0;
    }
    _isAnswerSubmittedToday = false; _isCorrectAnswerToday = false;
    _correctAnswerForFeedback = null; _quizCompleted = false;
    _answerController.clear();
  }

  // --- VVV NEW: Archival Logic VVV ---
  Future<void> _archiveCurrentMonthData() async {
    if (_selectedTopic == null || _topicSelectionDate == null || _questions.isEmpty) {
      debugPrint("DailyQuiz: Not enough data to archive.");
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final String currentMonthYear = DateFormat('yyyy-MM').format(_topicSelectionDate!);
    // final String lastArchived = prefs.getString(DailyQuizScreen.prefLastArchivedMonth) ?? "";
    // Avoid re-archiving if data is identical or for the same day if called multiple times.
    // This basic check prevents immediate re-archive. A more robust check would compare content.
    // if (lastArchived == currentMonthYear && _questions.length == 30 /* and all answers filled for a full archive */) {
    //     debugPrint("DailyQuiz: Month $currentMonthYear might already be archived or data unchanged.");
    //     return;
    // }
    try {
      final archiveData = {
        'topic': _selectedTopic,
        'selectionDate': _topicSelectionDate!.toIso8601String(),
        'questions': _questions.map((q) => Map<String, dynamic>.from(q)).toList(),
        'userAnswers': _userAnswers.map((e) => e).toList(),
        'userAnswersCorrectness': _userAnswersCorrectness.map((e) => e).toList(),
        'userAnswersFeedback': _userAnswersFeedback.map((e) => e).toList(),
        'attemptStreakAtEnd': _attemptStreak,
        'winningStreakAtEnd': _winningStreak,
      };
      final String jsonData = jsonEncode(archiveData);
      await prefs.setString('dailyQuiz_archived_$currentMonthYear', jsonData);
      await prefs.setString(DailyQuizScreen.prefLastArchivedMonth, currentMonthYear);
      debugPrint("DailyQuiz: Archived data for $currentMonthYear successfully.");
    } catch (e) {
      debugPrint("DailyQuiz: Error archiving month data for $currentMonthYear: $e");
    }
  }

  void _startNewCycle() async {
    if (!mounted) return;
    if (_selectedTopic != null && _topicSelectionDate != null && _questions.isNotEmpty) {
      await _archiveCurrentMonthData(); // Archive before resetting for a new cycle
    }
    setState(() {
      _resetQuizState(clearTopic: true);
      _isLoading = false; // Allow topic selection
    });
    await _saveData(); // Save the fully reset state
  }
  // --- ^^^ NEW: Archival Logic ^^^ ---

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 3)),
    );
  }

  // --- Widgets (largely unchanged from previous correct version) ---
  Widget _buildTopicSelectionScreen(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 60, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text('Start Your 30-Day Daily Quiz!', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onBackground)),
            const SizedBox(height: 15),
            Text('Choose a topic to focus on for the next 30 days and build your knowledge streak.', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 30),
            TextField(
              controller: _topicController,
              decoration: InputDecoration(
                labelText: 'Enter Topic', hintText: 'e.g., Flutter State Management',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                prefixIcon: Icon(Icons.topic_outlined, color: theme.colorScheme.primary),
              ),
              onSubmitted: (_) => _selectTopic(),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.play_circle_fill_rounded, color: theme.colorScheme.onPrimary),
              label: Text('Start Quiz Cycle', style: TextStyle(color: theme.colorScheme.onPrimary)),
              onPressed: _selectTopic,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizScreen(ThemeData theme) {
    final colorScheme = theme.colorScheme; final textTheme = theme.textTheme;
    final questionIndex = _currentDay - 1;
    Map<String, dynamic>? currentQuestionData; String questionText = "Loading question..."; String? codeSnippet;

    if (_isLoading) questionText = "Initializing Quiz...";
    else if (_isGeneratingQuestions) questionText = "Generating questions for '$_selectedTopic'...";
    else if (questionIndex >= 0 && questionIndex < _questions.length) {
      currentQuestionData = _questions[questionIndex];
      questionText = currentQuestionData['question'] as String? ?? 'Error: Invalid question format';
      codeSnippet = currentQuestionData['code_snippet'] as String?;
    } else if (_questions.isEmpty && _selectedTopic != null && !_isGeneratingQuestions) {
      questionText = "No questions available. Please try selecting a topic again.";
    } else if (_quizCompleted) {
      questionText = "Quiz cycle completed!";
    } else {
      questionText = "Error: Question not available for Day $_currentDay.";
    }
    final bool alreadyAnsweredThisDay = _hasSubmittedAnswerForCurrentDay;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Text(_selectedTopic ?? "No Topic Selected", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                    Chip(
                      avatar: Icon(Icons.calendar_today_outlined, size: 16, color: colorScheme.primary),
                      label: Text('Day $_currentDay / 30', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onPrimaryContainer)),
                      backgroundColor: colorScheme.primaryContainer.withOpacity(0.8),
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildStreakChip(theme, Icons.local_fire_department_rounded, _attemptStreak, "Attempt", colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                _buildStreakChip(theme, Icons.star_rounded, _winningStreak, "Winning", colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
              ],
            ),
            const SizedBox(height: 20),
            if (!_quizCompleted) Card(
              elevation: 2, margin: const EdgeInsets.symmetric(vertical: 10.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              child: Container(
                padding: const EdgeInsets.all(20.0), width: double.infinity,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12.0), gradient: LinearGradient(colors: [colorScheme.surface, colorScheme.surface.withOpacity(0.95)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: (_isLoading || _isGeneratingQuestions) ? Column(
                  mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
                  children: [ CircularProgressIndicator(color: colorScheme.primary), const SizedBox(height: 15), Text(questionText, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant), textAlign: TextAlign.center)],
                ) : (_questions.isEmpty) ? Text(questionText, textAlign: TextAlign.center, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurfaceVariant))
                    : Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center,
                  children: [ SelectableText(questionText, textAlign: TextAlign.center, style: textTheme.titleLarge?.copyWith(height: 1.4, color: colorScheme.onSurface)),
                    if (codeSnippet != null && codeSnippet.isNotEmpty) ...[ const SizedBox(height: 15), _buildCodeSnippet(theme, codeSnippet)],
                  ],
                ),
              ),
            ),
            if (!_quizCompleted) const SizedBox(height: 20),
            if (!_quizCompleted && _questions.isNotEmpty) ...[
              if (alreadyAnsweredThisDay && !_isCheckingAnswer) ...[
                _buildFeedbackSection(theme), const SizedBox(height: 15),
                Text("Come back tomorrow for the next question!", textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ] else if (!alreadyAnsweredThisDay) ...[
                TextField(
                  controller: _answerController, enabled: _isSubmitButtonEnabled && !_isCheckingAnswer,
                  decoration: InputDecoration(
                    labelText: 'Your Answer', hintText: 'Type your answer for Day $_currentDay',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                    filled: true, fillColor: colorScheme.surfaceVariant.withOpacity(0.5),
                    prefixIcon: Icon(Icons.question_answer_outlined, color: colorScheme.primary),
                  ),
                  textInputAction: TextInputAction.done, onSubmitted: (_) => _isSubmitButtonEnabled ? _submitAnswer() : null,
                  minLines: 1, maxLines: 5,
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  icon: _isCheckingAnswer ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary)) : Icon(Icons.check_circle_outline_rounded, color: colorScheme.onPrimary),
                  label: Text(_isCheckingAnswer ? 'Checking...' : 'Submit Answer', style: TextStyle(color: colorScheme.onPrimary)),
                  onPressed: _isSubmitButtonEnabled ? _submitAnswer : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary, disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
                    disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
                    minimumSize: const Size(double.infinity, 50), padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: _isSubmitButtonEnabled ? 2 : 0,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
            if (_quizCompleted) _buildCompletionSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeSnippet(ThemeData theme, String code) {
    final isDark = theme.brightness == Brightness.dark;
    final codeBgColor = isDark ? Colors.grey.shade900.withOpacity(0.8) : Colors.grey.shade200;
    final codeTextColor = theme.colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(12.0), margin: const EdgeInsets.only(top: 8.0),
      decoration: BoxDecoration(color: codeBgColor, borderRadius: BorderRadius.circular(8.0), border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2))),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: codeTextColor, height: 1.4))),
          Positioned(
            top: -8, right: -8,
            child: IconButton(
              icon: Icon(Icons.copy_all_outlined, size: 18, color: codeTextColor.withOpacity(0.7)), tooltip: 'Copy Code',
              visualDensity: VisualDensity.compact, splashRadius: 18,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating, width: 150));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakChip(ThemeData theme, IconData icon, int value, String label, Color bgColor, Color fgColor) {
    return Chip(
      avatar: Icon(icon, size: 18, color: fgColor.withOpacity(0.8)),
      label: Text('$label: $value', style: theme.textTheme.bodyMedium?.copyWith(color: fgColor, fontWeight: FontWeight.w500)),
      backgroundColor: bgColor, visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      side: BorderSide.none, elevation: 1,
    );
  }

  Widget _buildFeedbackSection(ThemeData theme) {
    final colorScheme = theme.colorScheme; final textTheme = theme.textTheme;
    final bool wasCorrect = _isCorrectAnswerToday;
    final String? aiSuggestedAnswer = _correctAnswerForFeedback;
    String userAnswerText = "Your answer was not recorded.";
    if (_currentDay > 0 && _currentDay <= _userAnswers.length) userAnswerText = _userAnswers[_currentDay - 1] ?? "You did not provide an answer.";
    return Container(
      margin: const EdgeInsets.only(top: 10.0, bottom: 10.0), padding: const EdgeInsets.all(15.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: wasCorrect ? Colors.green.shade300 : colorScheme.error.withOpacity(0.5), width: 1.5),
        gradient: LinearGradient(colors: wasCorrect ? [Colors.green.shade50.withOpacity(0.6), Colors.green.shade100.withOpacity(0.6)] : [colorScheme.errorContainer.withOpacity(0.4), colorScheme.errorContainer.withOpacity(0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Result for Day $_currentDay", textAlign: TextAlign.center, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text("Your Answer:", style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          SelectableText(userAnswerText, style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface, fontStyle: FontStyle.italic)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(wasCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded, color: wasCorrect ? Colors.green.shade600 : colorScheme.error, size: 28),
              const SizedBox(width: 8),
              Text(wasCorrect ? "Correct!" : "Incorrect", style: textTheme.titleLarge?.copyWith(color: wasCorrect ? Colors.green.shade700 : colorScheme.error, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 15),
          if (!wasCorrect && aiSuggestedAnswer != null && aiSuggestedAnswer.isNotEmpty) Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer.withOpacity(0.2), borderRadius: BorderRadius.circular(8.0), border: Border.all(color: theme.colorScheme.tertiaryContainer.withOpacity(0.5))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
                Text("Suggested Answer:", style: textTheme.labelMedium?.copyWith(color: colorScheme.onTertiaryContainer, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ConstrainedBox(constraints: const BoxConstraints(maxHeight: 120), child: SingleChildScrollView(child: SelectableText(aiSuggestedAnswer, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onTertiaryContainer)))),
              ],
            ),
          ),
          if (!wasCorrect) const SizedBox(height: 5),
        ],
      ),
    );
  }

  Widget _buildCompletionSection(ThemeData theme) {
    final colorScheme = theme.colorScheme; final textTheme = theme.textTheme;
    return Center(
      child: Card(
        elevation: 2, margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded, size: 50, color: Colors.amber.shade700),
              const SizedBox(height: 15),
              Text("30-Day Cycle Complete!", style: textTheme.headlineSmall?.copyWith(color: colorScheme.primary), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              Text("You've completed the daily quiz for '$_selectedTopic'. Well done!", style: textTheme.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStreakChip(theme, Icons.local_fire_department_rounded, _attemptStreak, "Attempts", colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
                  const SizedBox(width: 10),
                  _buildStreakChip(theme, Icons.star_rounded, _winningStreak, "Final Wins", colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
                ],
              ),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                icon: Icon(Icons.refresh_rounded, color: colorScheme.onPrimary),
                label: Text("Start New Topic", style: TextStyle(color: colorScheme.onPrimary)),
                onPressed: _startNewCycle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: Text('Daily Quiz Challenge', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500)),
        backgroundColor: theme.colorScheme.surface, elevation: 1.0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface), tooltip: 'Back', onPressed: () => Navigator.of(context).pop()),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_selectedTopic != null && _selectedTopic!.isNotEmpty && !_isLoading && !_isGeneratingQuestions)
            IconButton(
              icon: const Icon(Icons.refresh), tooltip: "Refresh Current Day",
              onPressed: () {
                if (!mounted) return; setState(() => _isLoading = true);
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (!mounted) return; _calculateCurrentDayAndStatus(); setState(() => _isLoading = false);
                });
              },
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
      body: SafeArea(
        child: (_selectedTopic == null || _selectedTopic!.isEmpty) && !_isLoading && !_isGeneratingQuestions
            ? _buildTopicSelectionScreen(theme)
            : (_isLoading || _isGeneratingQuestions)
            ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
            : _buildQuizScreen(theme),
      ),
    );
  }
}