// lib/models/chat_data.dart

import 'package:flutter/foundation.dart'; // For Uint8List
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
// *** IMPORTANT: Ensure this path correctly points to your mainscreen.dart ***
// *** where the ChatMessage class (with non-final id/timestamp) is defined ***
import '../mainscreen.dart'; // Assuming mainscreen.dart is in lib/

part 'chat_data.g.dart'; // Make sure this line exists and file is generated

const uuid = Uuid(); // Ensure uuid is initialized if used

// --- Hive Compatible Chat Message ---
@HiveType(typeId: 1)
class ChatMessageHive extends HiveObject {
  @HiveField(0)
  late int senderValue;

  @HiveField(1)
  late int typeValue;

  @HiveField(2)
  String? text;

  @HiveField(3)
  Uint8List? imageData;

  @HiveField(4)
  String? imageUrl;

  @HiveField(5)
  String? youtubeVideoId;

  @HiveField(6)
  late DateTime timestamp;

  @HiveField(7)
  late String id;

  Sender get sender => Sender.values[senderValue];
  MessageType get type => MessageType.values[typeValue];

  ChatMessageHive();

  ChatMessageHive.fromChatMessage(ChatMessage message) {
    senderValue = message.sender.index;
    typeValue = message.type.index;
    text = message.text;
    imageData = message.imageData;
    imageUrl = message.imageUrl;
    youtubeVideoId = message.youtubeVideoId;
    timestamp = message.timestamp;
    id = message.id;
  }

  ChatMessage toChatMessage() {
    var message = ChatMessage(
      sender: sender,
      type: type,
      text: text,
      imageData: imageData,
      imageUrl: imageUrl,
      youtubeVideoId: youtubeVideoId,
    );
    message.timestamp = timestamp;
    message.id = id;
    return message;
  }
}

// --- SavedChatSession ---
@HiveType(typeId: 2)
class SavedChatSession extends HiveObject {
  @HiveField(0)
  late String sessionId;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late DateTime timestamp;

  @HiveField(3)
  late List<ChatMessageHive> chatMessages;

  SavedChatSession();

  SavedChatSession.create({
    required this.title,
    required this.timestamp,
    required List<ChatMessage> messages,
  }) {
    sessionId = uuid.v4();
    chatMessages = messages.map((msg) => ChatMessageHive.fromChatMessage(msg)).toList();
  }
}

// --- RecentChatMetadata ---
@HiveType(typeId: 3)
class RecentChatMetadata extends HiveObject {
  @HiveField(0)
  late String chatId;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late DateTime lastUpdated;

  RecentChatMetadata();

  RecentChatMetadata.create({
    required this.chatId,
    required this.title,
    required this.lastUpdated,
  });
}

// --- NEW: Archived Question Data ---
@HiveType(typeId: 4)
class ArchivedQuestionData extends HiveObject {
  @HiveField(0)
  late String questionText;

  @HiveField(1)
  String? codeSnippet;

  @HiveField(2)
  late bool attempted;

  @HiveField(3)
  bool? answeredCorrectly; // Null if not attempted

  @HiveField(4)
  String? category; // For Gemini analysis: theory, numerical, coding, graphical

  @HiveField(5)
  List<String>? identifiedTopics; // Topics from this specific question

  ArchivedQuestionData();

  ArchivedQuestionData.create({
    required this.questionText,
    this.codeSnippet,
    required this.attempted,
    this.answeredCorrectly,
    this.category,
    this.identifiedTopics,
  });
}

// --- NEW: Archived Quiz Month ---
@HiveType(typeId: 5)
class ArchivedQuizMonth extends HiveObject {
  @HiveField(0)
  late String monthYear; // e.g., "2023-10" (YYYY-MM)

  @HiveField(1)
  late List<ArchivedQuestionData> questions; // List of 30 questions

  @HiveField(2)
  late String topic; // The topic for this month's quiz

  ArchivedQuizMonth();

  ArchivedQuizMonth.create({
    required this.monthYear,
    required this.topic,
    required this.questions,
  });
}

// --- NEW: Topic Proficiency (for stats) ---
@HiveType(typeId: 6)
class TopicProficiency extends HiveObject {
  @HiveField(0)
  late String topicName;

  @HiveField(1)
  late int correctAnswers;

  @HiveField(2)
  late int totalAttemptedQuestions;

  double get proficiency => totalAttemptedQuestions > 0 ? (correctAnswers / totalAttemptedQuestions) : 0.0;

  TopicProficiency();

  TopicProficiency.create({
    required this.topicName,
    this.correctAnswers = 0,
    this.totalAttemptedQuestions = 0,
  });
}


// --- NEW: Quiz Stats Analysis (stored results from Gemini for quizzes) ---
@HiveType(typeId: 7)
class QuizAnalysisResults extends HiveObject {
  // We might store overall analysis or per-month analysis if needed.
  // For now, let's consider overall.
  @HiveField(0)
  late String analysisId; // e.g., "overall_quiz_analysis" or "YYYY-MM_quiz_analysis"

  @HiveField(1)
  Map<String, int>? questionCategoryCounts; // e.g., {"theory": 10, "coding": 5}

  @HiveField(2)
  List<String>? topQuizTopics; // Top 5 topics derived from all quiz questions

  @HiveField(3)
  List<TopicProficiency>? topicProficiencies; // Overall proficiency in different topics

  // Timestamp of last analysis
  @HiveField(4)
  DateTime? lastAnalyzed;


  QuizAnalysisResults();

  QuizAnalysisResults.create({
    required this.analysisId,
    this.questionCategoryCounts,
    this.topQuizTopics,
    this.topicProficiencies,
    this.lastAnalyzed,
  });
}

// --- NEW: Chat Analysis Results (stored results from Gemini for chats) ---
@HiveType(typeId: 8)
class ChatAnalysisResults extends HiveObject {
  @HiveField(0)
  late String analysisId; // e.g., "overall_chat_topic_analysis"

  @HiveField(1)
  List<String>? topChatPromptTopics; // Top 5 topics from user prompts in chats

  @HiveField(2)
  DateTime? lastAnalyzed;

  ChatAnalysisResults();

  ChatAnalysisResults.create({
    required this.analysisId,
    this.topChatPromptTopics,
    this.lastAnalyzed,
  });
}


// --- Helper Functions ---
List<ChatMessageHive> convertToHiveMessages(List<ChatMessage> messages) {
  return messages.map((msg) => ChatMessageHive.fromChatMessage(msg)).toList();
}

List<ChatMessage> convertFromHiveMessages(List<ChatMessageHive> hiveMessages) {
  return hiveMessages.map((hiveMsg) => hiveMsg.toChatMessage()).toList();
}