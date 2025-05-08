// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_data.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatMessageHiveAdapter extends TypeAdapter<ChatMessageHive> {
  @override
  final int typeId = 1;

  @override
  ChatMessageHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessageHive()
      ..senderValue = fields[0] as int
      ..typeValue = fields[1] as int
      ..text = fields[2] as String?
      ..imageData = fields[3] as Uint8List?
      ..imageUrl = fields[4] as String?
      ..youtubeVideoId = fields[5] as String?
      ..timestamp = fields[6] as DateTime
      ..id = fields[7] as String;
  }

  @override
  void write(BinaryWriter writer, ChatMessageHive obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.senderValue)
      ..writeByte(1)
      ..write(obj.typeValue)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.imageData)
      ..writeByte(4)
      ..write(obj.imageUrl)
      ..writeByte(5)
      ..write(obj.youtubeVideoId)
      ..writeByte(6)
      ..write(obj.timestamp)
      ..writeByte(7)
      ..write(obj.id);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageHiveAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SavedChatSessionAdapter extends TypeAdapter<SavedChatSession> {
  @override
  final int typeId = 2;

  @override
  SavedChatSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedChatSession()
      ..sessionId = fields[0] as String
      ..title = fields[1] as String
      ..timestamp = fields[2] as DateTime
      ..chatMessages = (fields[3] as List).cast<ChatMessageHive>();
  }

  @override
  void write(BinaryWriter writer, SavedChatSession obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.sessionId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.chatMessages);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedChatSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RecentChatMetadataAdapter extends TypeAdapter<RecentChatMetadata> {
  @override
  final int typeId = 3;

  @override
  RecentChatMetadata read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RecentChatMetadata()
      ..chatId = fields[0] as String
      ..title = fields[1] as String
      ..lastUpdated = fields[2] as DateTime;
  }

  @override
  void write(BinaryWriter writer, RecentChatMetadata obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.chatId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentChatMetadataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ArchivedQuestionDataAdapter extends TypeAdapter<ArchivedQuestionData> {
  @override
  final int typeId = 4;

  @override
  ArchivedQuestionData read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ArchivedQuestionData()
      ..questionText = fields[0] as String
      ..codeSnippet = fields[1] as String?
      ..attempted = fields[2] as bool
      ..answeredCorrectly = fields[3] as bool?
      ..category = fields[4] as String?
      ..identifiedTopics = (fields[5] as List?)?.cast<String>();
  }

  @override
  void write(BinaryWriter writer, ArchivedQuestionData obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.questionText)
      ..writeByte(1)
      ..write(obj.codeSnippet)
      ..writeByte(2)
      ..write(obj.attempted)
      ..writeByte(3)
      ..write(obj.answeredCorrectly)
      ..writeByte(4)
      ..write(obj.category)
      ..writeByte(5)
      ..write(obj.identifiedTopics);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArchivedQuestionDataAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ArchivedQuizMonthAdapter extends TypeAdapter<ArchivedQuizMonth> {
  @override
  final int typeId = 5;

  @override
  ArchivedQuizMonth read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ArchivedQuizMonth()
      ..monthYear = fields[0] as String
      ..questions = (fields[1] as List).cast<ArchivedQuestionData>()
      ..topic = fields[2] as String;
  }

  @override
  void write(BinaryWriter writer, ArchivedQuizMonth obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.monthYear)
      ..writeByte(1)
      ..write(obj.questions)
      ..writeByte(2)
      ..write(obj.topic);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArchivedQuizMonthAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TopicProficiencyAdapter extends TypeAdapter<TopicProficiency> {
  @override
  final int typeId = 6;

  @override
  TopicProficiency read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TopicProficiency()
      ..topicName = fields[0] as String
      ..correctAnswers = fields[1] as int
      ..totalAttemptedQuestions = fields[2] as int;
  }

  @override
  void write(BinaryWriter writer, TopicProficiency obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.topicName)
      ..writeByte(1)
      ..write(obj.correctAnswers)
      ..writeByte(2)
      ..write(obj.totalAttemptedQuestions);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicProficiencyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class QuizAnalysisResultsAdapter extends TypeAdapter<QuizAnalysisResults> {
  @override
  final int typeId = 7;

  @override
  QuizAnalysisResults read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QuizAnalysisResults()
      ..analysisId = fields[0] as String
      ..questionCategoryCounts = (fields[1] as Map?)?.cast<String, int>()
      ..topQuizTopics = (fields[2] as List?)?.cast<String>()
      ..topicProficiencies = (fields[3] as List?)?.cast<TopicProficiency>()
      ..lastAnalyzed = fields[4] as DateTime?;
  }

  @override
  void write(BinaryWriter writer, QuizAnalysisResults obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.analysisId)
      ..writeByte(1)
      ..write(obj.questionCategoryCounts)
      ..writeByte(2)
      ..write(obj.topQuizTopics)
      ..writeByte(3)
      ..write(obj.topicProficiencies)
      ..writeByte(4)
      ..write(obj.lastAnalyzed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuizAnalysisResultsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChatAnalysisResultsAdapter extends TypeAdapter<ChatAnalysisResults> {
  @override
  final int typeId = 8;

  @override
  ChatAnalysisResults read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatAnalysisResults()
      ..analysisId = fields[0] as String
      ..topChatPromptTopics = (fields[1] as List?)?.cast<String>()
      ..lastAnalyzed = fields[2] as DateTime?;
  }

  @override
  void write(BinaryWriter writer, ChatAnalysisResults obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.analysisId)
      ..writeByte(1)
      ..write(obj.topChatPromptTopics)
      ..writeByte(2)
      ..write(obj.lastAnalyzed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatAnalysisResultsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
