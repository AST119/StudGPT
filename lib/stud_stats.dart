// lib/stud_stats.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'gemini_service.dart'; // For classifying questions
import 'daily_quiz_screen.dart'; // For SharedPreferences keys and constants
import 'time_based.dart'; // For SharedPreferences keys and constants

// --- Data Models for Charts ---
class DailyQuizAttemptData {
  final int day;
  final bool attempted;
  DailyQuizAttemptData(this.day, this.attempted);
}

class TimeBasedMarkData {
  final int day; // Day of the month
  final double averageMarksPercentage; // 0.0 to 1.0
  TimeBasedMarkData(this.day, this.averageMarksPercentage);
}

enum PieChartCategory { theory, code, numerical, visual, unknown }

class PieChartDataPoint {
  final PieChartCategory category;
  final int count;
  final Color color;
  PieChartDataPoint(this.category, this.count, this.color);
}

// --- Main Widget ---
class StudStatsScreen extends StatefulWidget {
  const StudStatsScreen({Key? key}) : super(key: key);
  static const String quizAnalysisBoxName = 'quiz_analysis_results_box';
  static const String chatAnalysisBoxName = 'chat_analysis_results_box';
  @override
  State<StudStatsScreen> createState() => _StudStatsScreenState();
}

class _StudStatsScreenState extends State<StudStatsScreen> {
  bool _isLoading = true;
  String? _selectedMonthDailyQuiz;
  String? _selectedMonthTimeBased;
  String? _selectedMonthPieChart;

  List<String> _availableDailyQuizMonths = [];
  List<String> _availableTimeBasedMonths = [];

  List<DailyQuizAttemptData> _dailyQuizChartData = [];
  List<TimeBasedMarkData> _timeBasedChartData = [];
  List<PieChartDataPoint> _pieChartSourceData = [];
  List<PieChartSectionData> _actualPieChartData = [];

  bool _showCorrectPieAnswers = true;
  Map<String, List<String>> _monthlyQuestionClassifications = {};
  List<bool?> _currentMonthDailyQuizCorrectness = [];

  late final GeminiService _geminiService;
  final String apiKey = 'AIzaSyBbJV4iAmnwq2eXJVtQmE8iOLlLCx6RAbU'; // <<< YOUR API KEY

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService(apiKey);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadAvailableDailyQuizMonths();
    await _loadAvailableTimeBasedMonths();

    final now = DateTime.now();
    final currentMonthYear = DateFormat('yyyy-MM').format(now);

    _selectedMonthDailyQuiz = _availableDailyQuizMonths.isNotEmpty ? _availableDailyQuizMonths.first : currentMonthYear;
    _selectedMonthTimeBased = _availableTimeBasedMonths.isNotEmpty ? _availableTimeBasedMonths.first : currentMonthYear;
    _selectedMonthPieChart = _availableDailyQuizMonths.isNotEmpty ? _availableDailyQuizMonths.first : currentMonthYear;

    await _updateDailyQuizChartData();
    await _updateTimeBasedChartData();
    await _updatePieChartData(); // This depends on _updateDailyQuizChartData for correctness

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAvailableDailyQuizMonths() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> months = [];
    final keys = prefs.getKeys();
    for (String key in keys) {
      if (key.startsWith('dailyQuiz_archived_')) {
        months.add(key.replaceFirst('dailyQuiz_archived_', ''));
      }
    }
    months.sort((a, b) => b.compareTo(a)); // Most recent first

    final currentTopic = prefs.getString(DailyQuizScreen.prefTopic);
    final currentTopicDateStr = prefs.getString(DailyQuizScreen.prefTopicDate);
    if (currentTopic != null && currentTopic.isNotEmpty && currentTopicDateStr != null) {
      final currentTopicDate = DateTime.tryParse(currentTopicDateStr);
      if (currentTopicDate != null) {
        final currentMonthYear = DateFormat('yyyy-MM').format(currentTopicDate);
        if (!months.contains(currentMonthYear)) {
          months.insert(0, currentMonthYear);
        }
      }
    }
    if (months.isEmpty) {
      months.add(DateFormat('yyyy-MM').format(DateTime.now())); // Add current if nothing else
    }
    _availableDailyQuizMonths = months;
  }

  Future<void> _updateDailyQuizChartData() async {
    if (_selectedMonthDailyQuiz == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    List<DailyQuizAttemptData> data = [];
    _currentMonthDailyQuizCorrectness = List.filled(30, null);

    final currentSystemMonthYear = DateFormat('yyyy-MM').format(DateTime.now());
    bool isSelectedMonthTheCurrentActiveQuizMonth = false;

    final activeTopic = prefs.getString(DailyQuizScreen.prefTopic);
    final activeTopicDateStr = prefs.getString(DailyQuizScreen.prefTopicDate);
    if (activeTopic != null && activeTopic.isNotEmpty && activeTopicDateStr != null) {
      final activeTopicDate = DateTime.tryParse(activeTopicDateStr);
      if (activeTopicDate != null && DateFormat('yyyy-MM').format(activeTopicDate) == _selectedMonthDailyQuiz) {
        isSelectedMonthTheCurrentActiveQuizMonth = true;
      }
    }

    if (isSelectedMonthTheCurrentActiveQuizMonth) {
      final List<String> answers = prefs.getStringList(DailyQuizScreen.prefAnswers) ?? List.filled(30, 'null');
      final List<String> correctnessStr = prefs.getStringList(DailyQuizScreen.prefAnswersCorrectness) ?? List.filled(30, 'null');
      for (int i = 0; i < 30; i++) {
        data.add(DailyQuizAttemptData(i + 1, answers.length > i && answers[i] != 'null' && answers[i].isNotEmpty));
        if (correctnessStr.length > i) {
          if (correctnessStr[i] == 'true') _currentMonthDailyQuizCorrectness[i] = true;
          else if (correctnessStr[i] == 'false') _currentMonthDailyQuizCorrectness[i] = false;
        }
      }
    } else {
      final String? jsonData = prefs.getString('dailyQuiz_archived_$_selectedMonthDailyQuiz');
      if (jsonData != null) {
        try {
          final Map<String, dynamic> archive = jsonDecode(jsonData);
          final List<dynamic> answers = archive['userAnswers'] ?? [];
          final List<dynamic> correctness = archive['userAnswersCorrectness'] ?? [];
          for (int i = 0; i < 30; i++) {
            data.add(DailyQuizAttemptData(i + 1, (i < answers.length && answers[i] != null && answers[i].toString().isNotEmpty)));
            if (i < correctness.length && correctness[i] != null) {
              if (correctness[i] == true) _currentMonthDailyQuizCorrectness[i] = true;
              else if (correctness[i] == false) _currentMonthDailyQuizCorrectness[i] = false;
            }
          }
        } catch (e) {
          debugPrint("Error loading daily quiz archive for $_selectedMonthDailyQuiz: $e");
          data = List.generate(30, (i) => DailyQuizAttemptData(i + 1, false));
        }
      } else {
        data = List.generate(30, (i) => DailyQuizAttemptData(i + 1, false));
      }
    }
    if (mounted) setState(() => _dailyQuizChartData = data);
  }

  Future<void> _loadAvailableTimeBasedMonths() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> resultsJson = prefs.getStringList(TimeBasedScreen.prefTimeBasedTestResults) ?? [];
    Set<String> months = {};
    for (String resultStr in resultsJson) {
      try {
        final Map<String, dynamic> result = jsonDecode(resultStr);
        final DateTime date = DateTime.parse(result['date'] as String);
        months.add(DateFormat('yyyy-MM').format(date));
      } catch (e) {
        debugPrint("Error parsing time based test result for month detection: $e");
      }
    }
    _availableTimeBasedMonths = months.toList();
    _availableTimeBasedMonths.sort((a, b) => b.compareTo(a));
    if (_availableTimeBasedMonths.isEmpty) {
      _availableTimeBasedMonths.add(DateFormat('yyyy-MM').format(DateTime.now()));
    }
  }

  Future<void> _updateTimeBasedChartData() async {
    if (_selectedMonthTimeBased == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> resultsJson = prefs.getStringList(TimeBasedScreen.prefTimeBasedTestResults) ?? [];
    Map<int, List<double>> dailyPercentages = {};

    for (String resultStr in resultsJson) {
      try {
        final Map<String, dynamic> result = jsonDecode(resultStr);
        final DateTime date = DateTime.parse(result['date'] as String);
        if (DateFormat('yyyy-MM').format(date) == _selectedMonthTimeBased) {
          final int dayOfMonth = date.day;
          final int score = result['score'] as int;
          final int possibleScore = result['possibleScore'] as int;
          if (possibleScore > 0) {
            double percentage = score / possibleScore;
            dailyPercentages.putIfAbsent(dayOfMonth, () => []).add(percentage);
          }
        }
      } catch (e) {
        debugPrint("Error processing time based result for chart: $e");
      }
    }
    List<TimeBasedMarkData> chartData = [];
    int daysInMonth = DateUtils.getDaysInMonth(
        int.parse(_selectedMonthTimeBased!.split('-')[0]),
        int.parse(_selectedMonthTimeBased!.split('-')[1]));
    for (int i = 1; i <= daysInMonth; i++) {
      if (dailyPercentages.containsKey(i)) {
        List<double> percentagesForDay = dailyPercentages[i]!;
        double avgPercentage = percentagesForDay.reduce((a, b) => a + b) / percentagesForDay.length;
        chartData.add(TimeBasedMarkData(i, avgPercentage));
      } else {
        chartData.add(TimeBasedMarkData(i, 0.0));
      }
    }
    if (mounted) setState(() => _timeBasedChartData = chartData);
  }

  Future<List<Map<String, dynamic>>> _getQuestionsForPieChart(String yearMonth) async {
    final prefs = await SharedPreferences.getInstance();
    bool isSelectedMonthTheCurrentActiveQuizMonth = false;
    final activeTopic = prefs.getString(DailyQuizScreen.prefTopic);
    final activeTopicDateStr = prefs.getString(DailyQuizScreen.prefTopicDate);
    if (activeTopic != null && activeTopic.isNotEmpty && activeTopicDateStr != null) {
      final activeTopicDate = DateTime.tryParse(activeTopicDateStr);
      if (activeTopicDate != null && DateFormat('yyyy-MM').format(activeTopicDate) == yearMonth) {
        isSelectedMonthTheCurrentActiveQuizMonth = true;
      }
    }

    if (isSelectedMonthTheCurrentActiveQuizMonth) {
      final List<String> qJson = prefs.getStringList(DailyQuizScreen.prefQuestions) ?? [];
      return qJson.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    } else {
      final String? jsonData = prefs.getString('dailyQuiz_archived_$yearMonth');
      if (jsonData != null) {
        try {
          final Map<String, dynamic> archive = jsonDecode(jsonData);
          List<dynamic>? questionsDynamic = archive['questions'] as List<dynamic>?;
          // Check if 'classifications' exist in archive, if so, store them
          List<dynamic>? classificationsDynamic = archive['classifications'] as List<dynamic>?;
          if (classificationsDynamic != null && classificationsDynamic.every((c) => c is String)) {
            _monthlyQuestionClassifications[yearMonth] = classificationsDynamic.cast<String>();
          }
          return questionsDynamic?.map((q) => q as Map<String, dynamic>).toList() ?? [];
        } catch (e) { return []; }
      }
    }
    return [];
  }

  Future<void> _updatePieChartData() async {
    if (_selectedMonthPieChart == null || !mounted) return;
    if (mounted) setState(() => _isLoading = true);

    List<Map<String, dynamic>> questions = await _getQuestionsForPieChart(_selectedMonthPieChart!);
    if (questions.isEmpty) {
      if (mounted) setState(() { _pieChartSourceData = []; _actualPieChartData = []; _isLoading = false; });
      return;
    }

    List<String> classifications;
    if (_monthlyQuestionClassifications.containsKey(_selectedMonthPieChart!)) {
      classifications = _monthlyQuestionClassifications[_selectedMonthPieChart!]!;
    } else {
      classifications = await _classifyQuestionsWithGemini(questions.map((q) => q['question'] as String? ?? "").toList());
      if (classifications.length == questions.length) {
        _monthlyQuestionClassifications[_selectedMonthPieChart!] = classifications;
        await _saveClassificationsToArchive(_selectedMonthPieChart!, classifications);
      } else {
        classifications = List.filled(questions.length, PieChartCategory.unknown.name);
      }
    }

    Map<PieChartCategory, int> categoryCounts = Map.fromIterable(PieChartCategory.values, key: (e) => e, value: (e) => 0);
    for (int i = 0; i < questions.length; i++) {
      bool? isCorrect = _currentMonthDailyQuizCorrectness.length > i ? _currentMonthDailyQuizCorrectness[i] : null;
      if ((_showCorrectPieAnswers && isCorrect == true) || (!_showCorrectPieAnswers && isCorrect == false)) {
        PieChartCategory category = PieChartCategory.values.firstWhere(
                (e) => e.name.toLowerCase() == classifications[i].toLowerCase(),
            orElse: () => PieChartCategory.unknown);
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }
    }

    _pieChartSourceData = categoryCounts.entries.map((entry) {
      Color color;
      switch (entry.key) {
        case PieChartCategory.theory: color = Colors.blue.shade300; break;
        case PieChartCategory.code: color = Colors.orange.shade300; break;
        case PieChartCategory.numerical: color = Colors.green.shade300; break;
        case PieChartCategory.visual: color = Colors.purple.shade300; break;
        default: color = Colors.grey.shade400;
      }
      return PieChartDataPoint(entry.key, entry.value, color);
    }).where((p) => p.count > 0).toList();

    _prepareActualPieChartData();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveClassificationsToArchive(String yearMonth, List<String> classifications) async {
    final prefs = await SharedPreferences.getInstance();
    final String archiveKey = 'dailyQuiz_archived_$yearMonth';
    final String? jsonData = prefs.getString(archiveKey);

    if (jsonData != null) {
      try {
        Map<String, dynamic> archive = jsonDecode(jsonData);
        archive['classifications'] = classifications; // Add/update classifications
        await prefs.setString(archiveKey, jsonEncode(archive));
        debugPrint("Saved classifications to archive for $yearMonth");
      } catch (e) {
        debugPrint("Error saving classifications to archive $yearMonth: $e");
      }
    } else {
      // This case should ideally not happen if _getQuestionsForPieChart implies an archive exists
      // Or, if it's the current month, save to a different key like 'dailyQuiz_current_classifications'
      debugPrint("Archive for $yearMonth not found to save classifications.");
    }
  }


  void _prepareActualPieChartData() {
    double total = _pieChartSourceData.fold(0, (sum, item) => sum + item.count);
    if (total == 0) {
      _actualPieChartData = [PieChartSectionData(value: 1, title: 'No Data', color: Colors.grey.shade300, radius: 50, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))];
      return;
    }
    _actualPieChartData = _pieChartSourceData.map((data) {
      final percentage = (data.count / total) * 100;
      return PieChartSectionData(
          color: data.color, value: data.count.toDouble(),
          title: '${data.category.name}\n${percentage.toStringAsFixed(1)}%', radius: 70,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 2)]));
    }).toList();
  }

  Future<List<String>> _classifyQuestionsWithGemini(List<String> questionsText) async {
    if (questionsText.isEmpty) return [];
    String prompt = "For each of the following ${questionsText.length} questions, classify it into ONLY ONE of these categories: Theory, Code, Numerical, or Visual. If a question doesn't fit well or you are unsure, classify it as 'Unknown'.\nRespond with ONLY a valid JSON array of strings, where each string is the category for the corresponding question. The array must have ${questionsText.length} elements.\nExample JSON array format: [\"Theory\", \"Code\", \"Numerical\", \"Visual\", \"Unknown\"]\n\nQuestions to classify:\n";
    for (int i = 0; i < questionsText.length; i++) {
      prompt += "${i + 1}. \"${questionsText[i]}\"\n";
    }
    try {
      String response = await _geminiService.getGeminiResponse(prompt);
      debugPrint("Gemini classification raw response: $response");
      final cleanedResponse = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final List<dynamic> decoded = jsonDecode(cleanedResponse);
      if (decoded is List && decoded.every((item) => item is String) && decoded.length == questionsText.length) {
        return decoded.cast<String>();
      }
      debugPrint("Gemini classification: Mismatch in length or type. Expected ${questionsText.length}, Got ${decoded.length}. Response: $cleanedResponse");
      return List.filled(questionsText.length, PieChartCategory.unknown.name);
    } catch (e) {
      debugPrint("Error classifying questions with Gemini: $e");
      return List.filled(questionsText.length, PieChartCategory.unknown.name);
    }
  }

  Widget _buildMonthSelector(String? selectedValue, List<String> availableMonths, String chartTitlePrefix, Function(String?) onChanged) {
    if (availableMonths.isEmpty) return Text("$chartTitlePrefix: No Data Available", style: const TextStyle(fontStyle: FontStyle.italic));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("$chartTitlePrefix Month: ", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        DropdownButton<String>(
          value: availableMonths.contains(selectedValue) ? selectedValue : (availableMonths.isNotEmpty ? availableMonths.first : null),
          items: availableMonths.map((String month) {
            return DropdownMenuItem<String>(value: month, child: Text(DateFormat('MMMM yyyy').format(DateFormat('yyyy-MM').parse(month))));
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDailyQuizAttemptChart() {
    if (_dailyQuizChartData.isEmpty && !_isLoading) return Card(elevation: 2, margin: const EdgeInsets.all(16), child: Padding(padding:const EdgeInsets.all(16.0), child:Center(child: Text("No daily quiz attempt data for $_selectedMonthDailyQuiz."))));
    return Card(
      elevation: 4, margin: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Daily Quiz Attempts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMonthSelector(_selectedMonthDailyQuiz, _availableDailyQuizMonths, "Attempts", (newValue) {
              if (newValue != null) {
                setState(() { _selectedMonthDailyQuiz = newValue; _selectedMonthPieChart = newValue; }); // Sync pie chart month
                _updateDailyQuizChartData().then((_) => _updatePieChartData());
              }
            }),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround, maxY: 1,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (BarChartGroupData group) => Colors.blueGrey.shade700,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          'Day ${group.x.toInt()}\n', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          children: <TextSpan>[TextSpan(text: rod.toY == 1 ? 'Attempted' : 'Not Attempted', style: TextStyle(color: rod.toY == 1 ? Colors.lightGreenAccent : Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.w500))],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) { if (value.toInt() % 5 == 0 || value.toInt() == 1 || value.toInt() == 30) return Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(value.toInt().toString(), style: const TextStyle(fontSize: 10))); return const SizedBox.shrink();}, reservedSize: 30)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _dailyQuizChartData.map((data) {
                    return BarChartGroupData(x: data.day, barRods: [BarChartRodData(toY: data.attempted ? 1 : 0, color: data.attempted ? Colors.cyan.shade300 : Colors.grey.shade300, width: 7, borderRadius: BorderRadius.circular(3))]);
                  }).toList(),
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.25),
                ),
                swapAnimationDuration: const Duration(milliseconds: 500), swapAnimationCurve: Curves.easeInOutCubic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBasedMarksChart() {
    if (_timeBasedChartData.isEmpty && !_isLoading) return Card(elevation:2, margin: const EdgeInsets.all(16), child: Padding(padding: const EdgeInsets.all(16.0),child: Center(child: Text("No time-based test data for $_selectedMonthTimeBased."))));
    int daysInSelectedMonth = _selectedMonthTimeBased != null ? DateUtils.getDaysInMonth(int.parse(_selectedMonthTimeBased!.split('-')[0]), int.parse(_selectedMonthTimeBased!.split('-')[1])) : 30;
    return Card(
      elevation: 4, margin: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Time-Based Test Performance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMonthSelector(_selectedMonthTimeBased, _availableTimeBasedMonths, "Performance", (newValue) { if (newValue != null) { setState(() => _selectedMonthTimeBased = newValue); _updateTimeBasedChartData(); }}),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround, maxY: 100,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (BarChartGroupData group) => Colors.teal.shade700,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem('Day ${group.x.toInt()}\n', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), children: <TextSpan>[TextSpan(text: '${(rod.toY).toStringAsFixed(0)}% Avg Score', style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.w500))]);
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) { if (value.toInt() % 5 == 0 || value.toInt() == 1 || value.toInt() == daysInSelectedMonth) return Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(value.toInt().toString(), style: const TextStyle(fontSize: 10))); return const SizedBox.shrink();}, reservedSize: 30)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) => Text('${value.toInt()}%', style: const TextStyle(fontSize: 10)), reservedSize: 40, interval: 25)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _timeBasedChartData.map((data) {
                    return BarChartGroupData(x: data.day, barRods: [BarChartRodData(toY: data.averageMarksPercentage * 100, color: data.averageMarksPercentage > 0 ? Colors.deepOrange.shade300 : Colors.grey.shade300, width: 7, borderRadius: BorderRadius.circular(3))]);
                  }).toList(),
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 25),
                ),
                swapAnimationDuration: const Duration(milliseconds: 500), swapAnimationCurve: Curves.easeInOutCubic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChartSection() {
    if (_actualPieChartData.isEmpty || (_actualPieChartData.length == 1 && _actualPieChartData.first.title == 'No Data') && !_isLoading) {
      return Card(elevation: 2, margin: const EdgeInsets.all(16), child: Padding(padding: const EdgeInsets.all(16.0), child: Center(child: Text("No daily quiz data for pie chart in $_selectedMonthPieChart for ${_showCorrectPieAnswers ? 'correct' : 'incorrect'} answers."))));
    }
    return Card(
      elevation: 4, margin: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Daily Quiz Question Types", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMonthSelector(_selectedMonthPieChart, _availableDailyQuizMonths, "Types for", (newValue) {
              if (newValue != null) {
                setState(() { _selectedMonthDailyQuiz = newValue; _selectedMonthPieChart = newValue; }); // Sync
                _updateDailyQuizChartData().then((_) => _updatePieChartData());
              }
            }),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Radio<bool>(value: true, groupValue: _showCorrectPieAnswers, onChanged: (val) { if (val != null) setState(() => _showCorrectPieAnswers = val); _updatePieChartData(); }), const Text('Correct'),
                Radio<bool>(value: false, groupValue: _showCorrectPieAnswers, onChanged: (val) { if (val != null) setState(() => _showCorrectPieAnswers = val); _updatePieChartData(); }), const Text('Incorrect'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220, // Increased height for better title display
              child: PieChart(
                PieChartData(
                  sections: _actualPieChartData, borderData: FlBorderData(show: false),
                  centerSpaceRadius: 50, sectionsSpace: 2,
                  pieTouchData: PieTouchData(touchCallback: (FlTouchEvent event, pieTouchResponse) { /* Handle touch */ }),
                ),
                swapAnimationDuration: const Duration(milliseconds: 600), swapAnimationCurve: Curves.easeInOutQuart,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Statistics'),
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadInitialData, // Allow pull to refresh all data
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // Ensure scroll even if content is small
          child: Column(
            children: [
              _buildDailyQuizAttemptChart(),
              _buildTimeBasedMarksChart(),
              _buildPieChartSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}