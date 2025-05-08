import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert'; // Now essential for JSON decoding
import 'package:flutter/foundation.dart'; // For debugPrint

class GeminiService {
  final GenerativeModel _model;

  // Consider gemini-1.5-flash or gemini-1.5-pro. Pro might be better for complex JSON.
  GeminiService(String apiKey)
      : _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);

  // --- getGeminiResponse (unchanged, but crucial for error handling) ---
  Future<String> getGeminiResponse(String prompt) async {
    try {
      final content = [Content.text(prompt)];
      // Reduced safety settings slightly for potentially less blocking of code/technical content
      // Monitor if harmful content becomes an issue.
      final safetySettings = [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ];
      final response = await _model.generateContent(
          content,
          safetySettings: safetySettings,
          // Optional: Generation Config
          generationConfig: GenerationConfig(
            // Consider adjusting temperature if JSON formatting is inconsistent
            // temperature: 0.5,
            // Enforce JSON output mode if using a supporting model (like gemini-1.5-pro)
            // responseMimeType: "application/json", // Uncomment if using Pro or a model supporting this
          )
      );

      debugPrint("--- Gemini Raw Response Text ---");
      debugPrint(response.text);
      debugPrint("------------------------------");

      // Clean potential markdown backticks around the entire JSON output
      String cleanedText = response.text?.trim() ?? "";
      if (cleanedText.startsWith('```json') && cleanedText.endsWith('```')) {
        cleanedText = cleanedText.substring(7, cleanedText.length - 3).trim();
      } else if (cleanedText.startsWith('```') && cleanedText.endsWith('```')) {
        cleanedText = cleanedText.substring(3, cleanedText.length - 3).trim();
      }

      // Add basic validation: Does it look like a JSON array?
      if (!cleanedText.startsWith('[') || !cleanedText.endsWith(']')) {
        debugPrint("Warning: Gemini response doesn't look like a JSON array. Raw text returned.");
        // Optionally return an error string here instead if strict JSON is required
        // return "Error: Response was not a valid JSON array format.";
      }

      return cleanedText.isEmpty ? "Error: Received empty response from AI." : cleanedText;

    } catch (e) {
      debugPrint('Error getting Gemini response: $e');
      if (e is GenerativeAIException) {
        return "Error from AI Service: ${e.message}"; // More specific error
      }
      return "Error generating content: $e";
    }
  }

  // --- generateMCQs - MODIFIED TO REQUEST AND PARSE JSON ---
  Future<List<Map<String, dynamic>>> generateMCQs(
      String topic, int numQuestions, String difficulty) async {

    // *** MODIFIED PROMPT TO REQUEST JSON ARRAY ***
    final prompt = """
Generate exactly $numQuestions multiple-choice questions about "$topic" with $difficulty difficulty.

Respond ONLY with a single valid JSON array where each element is an object representing a question.
Each question object MUST have the following keys:
- "question": (String) The question text.
- "code_snippet": (String or Null) A relevant code snippet formatted as a string (use markdown backticks within the string if needed for internal formatting, e.g., "```dart\\nvoid main() {}\\n```"), or null if no code is applicable.
- "options": (Object/Map) An object where keys are "a", "b", "c", "d" and values are the corresponding option strings.
- "correct_option": (String) The key ('a', 'b', 'c', or 'd') of the correct option from the "options" object.

Example of a single question object in the array:
{
  "question": "What is the output of this Dart code?",
  "code_snippet": "```dart\\nvoid main() {\\n  print('Hello, World!');\\n}```",
  "options": {
    "a": "Hello, World!",
    "b": "Compilation Error",
    "c": "Runtime Error",
    "d": "Hello, Dart!"
  },
  "correct_option": "a"
}

Ensure the entire output is ONLY the JSON array, starting with '[' and ending with ']'. Do not include any explanatory text before or after the JSON array.
""";

    debugPrint("--- Sending JSON MCQ Prompt to Gemini ---");
    debugPrint(prompt);
    debugPrint("-----------------------------------------");

    final responseString = await getGeminiResponse(prompt);

    // Check for errors returned by getGeminiResponse itself
    if (responseString.startsWith("Error")) {
      debugPrint("Gemini service returned an error message: $responseString");
      throw Exception("Failed to generate MCQs: $responseString"); // Throw exception to handle in UI
    }

    // *** MODIFIED PARSING LOGIC USING jsonDecode ***
    try {
      // Decode the JSON string into a List
      final decodedList = jsonDecode(responseString) as List<dynamic>;

      final List<Map<String, dynamic>> questions = [];
      int index = 0; // For debugging which item failed validation

      // Validate and structure each item in the list
      for (final item in decodedList) {
        index++;
        if (item is Map<String, dynamic>) {
          // Basic validation of required keys and types
          final String? questionText = item['question'] as String?;
          final dynamic codeSnippetData = item['code_snippet']; // Can be String or null
          final Map<String, dynamic>? optionsMap = (item['options'] is Map)
              ? Map<String, dynamic>.from(item['options'] as Map)
              : null;
          final String? correctOptionKey = item['correct_option'] as String?;

          // Check for required fields
          if (questionText != null &&
              optionsMap != null &&
              optionsMap.containsKey('a') && optionsMap.containsKey('b') &&
              optionsMap.containsKey('c') && optionsMap.containsKey('d') &&
              correctOptionKey != null && ['a', 'b', 'c', 'd'].contains(correctOptionKey))
          {
            // Clean up potential markdown in the snippet value itself (if Gemini added extra)
            String? finalCodeSnippet = (codeSnippetData is String) ? codeSnippetData.trim() : null;
            if (finalCodeSnippet != null && finalCodeSnippet.isNotEmpty) {
              if (finalCodeSnippet.startsWith('```') && finalCodeSnippet.endsWith('```')) {
                finalCodeSnippet = finalCodeSnippet.substring(3, finalCodeSnippet.length - 3).trim();
                // Remove potential language identifier like 'dart\n' at the start
                finalCodeSnippet = finalCodeSnippet.replaceFirst(RegExp(r'^[a-zA-Z]+\s*\n'), '');
              }
              // If after cleaning it's empty, set to null
              if (finalCodeSnippet.isEmpty) finalCodeSnippet = null;
            } else {
              finalCodeSnippet = null; // Ensure explicitly null if not a non-empty string
            }


            questions.add({
              'question': questionText, // Use the new key name
              'code_snippet': finalCodeSnippet, // Use the new key name
              'options': optionsMap,       // Use the new key name (already a map)
              'correct_option': correctOptionKey, // Use the new key name
              // 'selected_option' will be added later in the Flutter UI
            });
          } else {
            debugPrint("--- Invalid MCQ Item Structure (Index $index) ---");
            debugPrint("Item Data: ${jsonEncode(item)}"); // Log the invalid item
            // Optionally add an error placeholder question or just skip
            questions.add({
              'question': 'Error: Invalid question format received (Index $index).',
              'code_snippet': null,
              'options': {'a': 'N/A', 'b': 'N/A', 'c': 'N/A', 'd': 'N/A'},
              'correct_option': 'a', // Placeholder
            });
          }
        } else {
          debugPrint("--- Skipped non-map item in JSON array (Index $index) ---");
          debugPrint("Item Data: ${item.toString()}");
        }
      }

      // Check if we got the expected number of questions after validation
      if (questions.length != numQuestions) {
        debugPrint("Warning: Expected $numQuestions questions, but parsed/validated ${questions.length}.");
        // Optionally throw an error or return partial list based on requirements
      }

      debugPrint("--- Successfully Parsed ${questions.length} JSON Questions ---");
      return questions;

    } catch (e) {
      debugPrint("--- Error Decoding/Parsing Gemini JSON Response ---");
      debugPrint("Error: $e");
      debugPrint("Raw Response String:\n$responseString");
      debugPrint("----------------------------------------------------");
      throw Exception("Failed to parse questions JSON: $e"); // Throw exception
    }
  }

// --- Old parser removed ---
// List<Map<String, dynamic>> _parseMCQsWithNewStructure(String response) { ... }
}