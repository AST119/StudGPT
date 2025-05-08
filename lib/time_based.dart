// lib/time_based.dart

import 'dart:async';
import 'dart:convert'; // For jsonEncode/Decode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for Clipboard
import 'package:shared_preferences/shared_preferences.dart'; // For saving results
import 'gemini_service.dart'; // Ensure this service uses JSON

// --- Color Palette ---
const Color colorBackground = Color(0xFFF5F7FA);
const Color colorButton = Color(0xFF4A90E2);
const Color colorButtonText = Color(0xFFFFFFFF);
const Color colorTextFieldBackground = Color(0xFFE9EEF6);
const Color colorTextDark = Color(0xFF333333);
const Color colorCodeBackground = Color(0xFF2D2D2D); // Dark background for code
const Color colorCodeText = Color(0xFFCCCCCC);     // Light gray text for code
const Color colorCodeBorder = Color(0xFF444444);    // Subtle border for code block
const Color colorCorrect = Colors.green;            // Green for correct answers
const Color colorIncorrect = Colors.red;            // Red for incorrect answers
const Color colorNeutral = Color(0xFFE0E0E0);       // Neutral bg for non-selected post-submit
const Color colorCorrectText = Colors.white;
const Color colorIncorrectText = Colors.white;
const Color colorNeutralText = Color(0xFF666666);
const Color colorSubmitButton = Colors.teal;        // <<< NEW: Distinct color for submit button
// --- ---

class TimeBasedScreen extends StatefulWidget {
  const TimeBasedScreen({Key? key}) : super(key: key);

  // Static key for SharedPreferences, accessible from stud_stats.dart
  static const String prefTimeBasedTestResults = 'timeBased_testResults_v1';

  @override
  State<TimeBasedScreen> createState() => _TimeBasedState();
}

class _TimeBasedState extends State<TimeBasedScreen> {
  // State variables
  bool _isLoading = false;
  bool _isTestStarted = false;
  bool _isSubmitted = false;
  int _selectedHours = 1; // Default is already 1 hour
  String _enteredTopic = '';
  Duration _remainingTime = const Duration(seconds: 0);
  Timer? _timer;
  final TextEditingController _topicController = TextEditingController();
  List<Map<String, dynamic>> _questions = [];
  int _totalMarks = 0;
  // IMPORTANT: Secure your API key
  final String apiKey = 'AIzaSyBbJV4iAmnwq2eXJVtQmE8iOLlLCx6RAbU'; // <<< YOUR API KEY
  late final GeminiService _geminiService;
  String _selectedDifficulty = 'Medium';

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService(apiKey);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _topicController.dispose();
    super.dispose();
  }

  // --- Core Logic ---

  void _startTimer() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a topic.')));
      return;
    }
    if (_isLoading) return;

    setState(() {
      _enteredTopic = topic;
      _isLoading = true;
      _isSubmitted = false;
      _questions = [];
      _totalMarks = 0;
    });

    _remainingTime = Duration(hours: _selectedHours);
    int numQuestions = _selectedHours == 1 ? 10 : (_selectedHours == 2 ? 20 : 30);

    try {
      List<Map<String, dynamic>> fetchedQuestions = await _geminiService.generateMCQs(
          _enteredTopic, numQuestions, _selectedDifficulty);

      if (!mounted) return;

      _questions = fetchedQuestions.map((q) => {...q, 'selected_option': null}).toList();

      if (_questions.isEmpty) {
        throw Exception("No questions were generated or parsed successfully.");
      }

      setState(() {
        _isTestStarted = true;
        _isLoading = false;
      });

      // Start timer
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        if (_remainingTime.inSeconds > 0 && !_isSubmitted) {
          setState(() { _remainingTime -= const Duration(seconds: 1); });
        } else if (_remainingTime.inSeconds <= 0 && !_isSubmitted) {
          debugPrint("Timer ran out, auto-submitting.");
          _submitTest(isAutoSubmit: true);
        } else if (_isSubmitted) {
          timer.cancel();
        }
      });

    } catch (e) {
      if (!mounted) return;
      debugPrint("Error starting test: $e");
      setState(() { _isLoading = false; _isTestStarted = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load questions: ${e.toString()}. Please try again.')),
      );
    }
  }

  void _calculateMarks() {
    _totalMarks = 0;
    for (var question in _questions) {
      if (question['selected_option'] != null &&
          question['selected_option'] == question['correct_option']) {
        _totalMarks += 2;
      }
    }
  }

  void _submitTest({bool isAutoSubmit = false}) async { // Make it async
    if (!mounted || _isSubmitted) return;
    debugPrint("Submitting test...");
    _timer?.cancel();
    _calculateMarks();

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> existingResultsJson = prefs.getStringList(TimeBasedScreen.prefTimeBasedTestResults) ?? [];
      final List<Map<String, dynamic>> existingResults = existingResultsJson
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList(); // Corrected here

      final newResult = {
        'date': DateTime.now().toIso8601String(),
        'topic': _enteredTopic,
        'score': _totalMarks,
        'possibleScore': _questions.length * 2,
        'durationHours': _selectedHours,
        'difficulty': _selectedDifficulty,
      };
      existingResults.add(newResult);

      await prefs.setStringList(
          TimeBasedScreen.prefTimeBasedTestResults,
          existingResults.map((r) => jsonEncode(r)).toList()
      );
      debugPrint("TimeBased: Saved test result for $_enteredTopic.");
    } catch (e) {
      debugPrint("TimeBased: Error saving test result: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error saving test result.')));
    }

    setState(() { _isSubmitted = true; _remainingTime = Duration.zero; });
    if (isAutoSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Time's up! Test submitted automatically.")),
      );
    }
  }


  void _resetAndGoToSetup() {
    if (!mounted) return;
    setState(() {
      _isLoading = false; _isTestStarted = false; _isSubmitted = false;
      _questions = []; _totalMarks = 0; _remainingTime = Duration.zero;
      _timer?.cancel(); _timer = null;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  // --- UI Building Methods ---

  final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: colorButton, foregroundColor: colorButtonText,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    disabledBackgroundColor: colorButton.withOpacity(0.5),
    disabledForegroundColor: colorButtonText.withOpacity(0.7),
  );

  Widget _buildOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4) )]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text( 'Configure Your Test', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorTextDark), ),
                  const SizedBox(height: 24),
                  TextField(
                      controller: _topicController,
                      style: const TextStyle(color: colorTextDark),
                      decoration: InputDecoration(
                        labelText: 'Enter Topic', labelStyle: const TextStyle(color: colorTextDark),
                        filled: true, fillColor: colorTextFieldBackground,
                        border: OutlineInputBorder( borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide.none, ),
                        focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: colorButton, width: 1.5), ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (value) {
                        setState(() {});
                      }
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    decoration: BoxDecoration( color: colorTextFieldBackground, borderRadius: BorderRadius.circular(8.0), ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedHours, isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: colorTextDark),
                        items: List.generate(3, (index) => index + 1).map((int hours) {
                          return DropdownMenuItem<int>( value: hours, child: Text('$hours Hour${hours > 1 ? 's' : ''}', style: const TextStyle(color: colorTextDark)), );
                        }).toList(),
                        onChanged: _isLoading ? null : (int? newValue) {
                          if (newValue != null) { setState(() { _selectedHours = newValue; }); }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    decoration: BoxDecoration( color: colorTextFieldBackground, borderRadius: BorderRadius.circular(8.0), ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDifficulty, isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: colorTextDark),
                        items: <String>['Easy', 'Medium', 'Hard'].map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>( value: value, child: Text(value, style: const TextStyle(color: colorTextDark)), );
                        }).toList(),
                        onChanged: _isLoading ? null : (String? newValue) {
                          if (newValue != null) { setState(() { _selectedDifficulty = newValue; }); }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator(color: colorButton))
                      : ElevatedButton(
                    style: elevatedButtonStyle,
                    onPressed: (_isLoading || _topicController.text.trim().isEmpty) ? null : _startTimer,
                    child: const Text('Start Test'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    int possibleMarks = _questions.length * 2;
    String timerText = _isSubmitted ? "Test Finished" : 'Time Remaining: ${_formatDuration(_remainingTime)}';

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          decoration: BoxDecoration(
              color: _isSubmitted ? colorNeutral : colorTextFieldBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _isSubmitted ? Colors.grey.shade400 : colorButton.withOpacity(0.3))
          ),
          child: Text( timerText, textAlign: TextAlign.center, style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: _isSubmitted ? colorNeutralText : colorTextDark, ), ),
        ),
        Expanded(
          child: _questions.isEmpty
              ? const Center(child: Text("Loading questions...", style: TextStyle(color: colorTextDark)))
              : ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 16.0),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              return _buildQuestionCard(index, _isSubmitted);
            },
          ),
        ),
        if (_isTestStarted)
          Container(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
            decoration: BoxDecoration(
                color: colorBackground,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0,-2))]
            ),
            child: _isSubmitted
                ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text( 'Your Score: $_totalMarks / $possibleMarks', style: const TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: colorTextDark, ), ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18), label: const Text('New Test'),
                  style: elevatedButtonStyle.copyWith(
                      padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      textStyle: MaterialStateProperty.all(const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
                  ),
                  onPressed: _resetAndGoToSetup,
                ),
              ],
            )
                : ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: const Text('Submit Test'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorSubmitButton,
                foregroundColor: colorButtonText,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                elevation: 3,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Submit Test?'),
                    content: const Text('Are you sure you want to submit your answers?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                      TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                            _submitTest();
                          },
                          child: const Text('Submit', style: TextStyle(color: Colors.red))
                      ), // Ensure comma if it's not the last widget, or trailing comma for the list
                    ], // Corrected: Ensure this closing bracket is present
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildQuestionCard(int index, bool isSubmitted) {
    final question = _questions[index];
    final String questionText = question['question'] as String? ?? 'Error: Missing question text.';
    final String? codeSnippet = question['code_snippet'] as String?;
    final bool hasCode = codeSnippet != null && codeSnippet.isNotEmpty;
    final Map<String, dynamic> options = (question['options'] is Map)
        ? Map<String, dynamic>.from(question['options'])
        : {};

    return Card(
      color: Colors.white,
      elevation: isSubmitted ? 1.0 : 2.0,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'Question ${index + 1}: $questionText',
              style: const TextStyle( fontSize: 16, fontWeight: FontWeight.w500, color: colorTextDark, height: 1.3, ),
            ),
            if (hasCode) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration( color: colorCodeBackground, borderRadius: BorderRadius.circular(6), border: Border.all(color: colorCodeBorder, width: 0.8), ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250.0),
                  child: SingleChildScrollView( child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                    child: SelectableText( codeSnippet!, style: const TextStyle( fontFamily: 'monospace', color: colorCodeText, fontSize: 13.5, height: 1.4, ), ),
                  ),),),),
              Align( alignment: Alignment.centerRight, child: IconButton(
                icon: const Icon(Icons.copy_all_outlined, size: 18, color: Colors.grey), tooltip: 'Copy Code', visualDensity: VisualDensity.compact, splashRadius: 20,
                onPressed: () { Clipboard.setData(ClipboardData(text: codeSnippet!)); ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied!'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating, width: 150,), ); }, ), ),
            ],
            const SizedBox(height: 12),
            ..._buildFixedOptions(options, index, isSubmitted),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFixedOptions(Map<String, dynamic> options, int questionIndex, bool isSubmitted) {
    List<Widget> optionWidgets = [];
    const List<String> optionKeys = ['a', 'b', 'c', 'd'];
    final String? selectedOption = _questions[questionIndex]['selected_option'];
    final String? correctOption = _questions[questionIndex]['correct_option'];

    for (String key in optionKeys) {
      final String optionText = options[key] as String? ?? 'Error: Missing option $key';
      bool isSelected = selectedOption == key;
      bool isCorrect = correctOption == key;
      Color bgColor; Color fgColor; double elevation = 0;

      if (isSubmitted) {
        if (isCorrect) { bgColor = colorCorrect; fgColor = colorCorrectText; elevation = isSelected ? 2 : 1; }
        else if (isSelected && !isCorrect) { bgColor = colorIncorrect; fgColor = colorIncorrectText; elevation = 2; }
        else { bgColor = colorNeutral; fgColor = colorNeutralText; elevation = 0; }
      } else { bgColor = isSelected ? colorButton : colorTextFieldBackground; fgColor = isSelected ? colorButtonText : colorTextDark; elevation = isSelected ? 2 : 0; }

      optionWidgets.add( Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: SizedBox( width: double.infinity, child: ElevatedButton(
        onPressed: isSubmitted ? null : () { if (!isSubmitted) { setState(() { _questions[questionIndex]['selected_option'] = key; }); } },
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor, foregroundColor: fgColor, disabledBackgroundColor: bgColor, disabledForegroundColor: fgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          alignment: Alignment.centerLeft, elevation: elevation,
        ),
        child: Text('${key.toUpperCase()}. $optionText', textAlign: TextAlign.left),
      ),),), );
    }
    return optionWidgets;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBackground,
      appBar: AppBar(
        backgroundColor: colorButton, foregroundColor: colorButtonText,
        elevation: 1.0, title: Text(_isTestStarted ? _enteredTopic : 'Time Based Test'),
        leading: IconButton( icon: const Icon(Icons.arrow_back), tooltip: 'Exit Test / Go Back',
          onPressed: () {
            if (!_isTestStarted || _isSubmitted) { if (Navigator.canPop(context)) { Navigator.pop(context); } return; }
            showDialog( context: context, builder: (context) => AlertDialog(
              title: const Text('Exit Test?'), content: const Text('Are you sure you want to exit? Your current progress will be lost.'),
              actions: [ TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')), TextButton(
                  onPressed: () { _timer?.cancel(); Navigator.of(context).pop(true); }, child: const Text('Exit', style: TextStyle(color: Colors.red)) ), ], ),
            ).then((exitConfirmed) { if (exitConfirmed ?? false) {
              setState(() { _isLoading = false; _isTestStarted = false; _isSubmitted = false; _questions = []; _totalMarks = 0; _remainingTime = Duration.zero; _timer = null; });
              if (Navigator.canPop(context)) { Navigator.pop(context); } } });
          }, ), ),
      body: SafeArea( child: Stack( children: [ if (_isTestStarted) _buildMainContent(), if (!_isTestStarted) _buildOverlay(), ], ), ),
    );
  }
}