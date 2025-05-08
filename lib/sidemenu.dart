// lib/sidemenu.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart'; // For date formatting

import 'loginpage.dart';
import 'daily_quiz_screen.dart';
import 'time_based.dart';
import 'models/chat_data.dart'; // Import metadata model
import 'stud_stats.dart'; // <-- Import the new screen

class Sidemenu extends StatelessWidget {
  // --- Callbacks for actions handled by MainScreen ---
  final VoidCallback onToggleMenu;
  final VoidCallback onNewChat;
  final VoidCallback onShowBookmarks; // Navigates to BookmarksScreen
  final VoidCallback onToggleStudZone;
  final VoidCallback onToggleDarkMode;
  final Function(String) onLoadPastChat; // Parameter changed to String (chatId)

  // --- State needed from MainScreen ---
  final bool isStudZoneOpen;
  final bool isDarkMode;
  final List<RecentChatMetadata> recentChats; // Receive recent chats list

  // --- Theming values from MainScreen ---
  final Color menuBackgroundColor;
  final Color textFieldTextColor;
  final Color iconColor;
  final Color textFieldBackgroundColor;
  final Color menuButtonSelectedColor;


  const Sidemenu({
    super.key,
    required this.onToggleMenu,
    required this.onNewChat,
    required this.onShowBookmarks,
    required this.onToggleStudZone,
    required this.onToggleDarkMode,
    required this.onLoadPastChat, // Expects Function(String)
    required this.isStudZoneOpen,
    required this.isDarkMode,
    required this.recentChats, // Receive the list
    required this.menuBackgroundColor,
    required this.textFieldTextColor,
    required this.iconColor,
    required this.textFieldBackgroundColor,
    required this.menuButtonSelectedColor,
  });


  // --- Function to handle Sign Out (remains largely the same) ---
  Future<void> _signOut(BuildContext context) async {
    try {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Confirm Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (confirm == true) {
        onToggleMenu();
        await Future.delayed(const Duration(milliseconds: 200));

        await FirebaseAuth.instance.signOut();
        try { // Add try-catch specifically for Google Sign Out as it might fail if not used
          await GoogleSignIn().signOut();
        } catch(e) {
          debugPrint("Google Sign Out skipped or failed: $e");
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('user_email');
        debugPrint('Stored email removed.');

        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
                (Route<dynamic> route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint("Error during sign out: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error signing out: ${e.toString()}'))
        );
      }
    }
  }

  // Helper to get display name (remains the same)
  String _getDisplayName(User user) {
    String? name = user.displayName;
    if (name != null && name.isNotEmpty) {
      return name;
    }
    if (user.email != null && user.email!.isNotEmpty) {
      String emailPrefix = user.email!.split('@')[0];
      return emailPrefix.isNotEmpty
          ? emailPrefix[0].toUpperCase() + (emailPrefix.length > 1 ? emailPrefix.substring(1) : '')
          : 'User';
    }
    return 'User';
  }

  // Helper to get the first initial (remains the same)
  String _getInitial(User user, String displayName) {
    if (displayName.isNotEmpty && displayName != 'User') {
      return displayName[0].toUpperCase();
    }
    if (user.email != null && user.email!.isNotEmpty) {
      return user.email![0].toUpperCase();
    }
    return 'U';
  }


  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    String displayName = 'Guest';
    String displayInitial = 'G';
    String? photoUrl;

    if (currentUser != null) {
      displayName = _getDisplayName(currentUser);
      photoUrl = currentUser.photoURL;
      displayInitial = _getInitial(currentUser, displayName);
    }

    // Date formatter for past chats subtitle
    final DateFormat subtitleFormat = DateFormat('MMM d, HH:mm');

    return Material(
      elevation: 16,
      child: Container(
        height: double.infinity,
        width: MediaQuery.of(context).size.width * 0.85, // Adjust width as needed
        color: menuBackgroundColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0), // Adjust padding
            child: Column( // Use Column directly, SingleChildScrollView if needed
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- User Profile Section ---
                if (currentUser != null)
                  InkWell(
                    onTap: () => _signOut(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: iconColor.withOpacity(0.2),
                            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                ? NetworkImage(photoUrl) : null,
                            child: (photoUrl == null || photoUrl.isEmpty)
                                ? Text(displayInitial, style: TextStyle(fontWeight: FontWeight.bold, color: iconColor, fontSize: 20))
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              displayName,
                              style: TextStyle(color: textFieldTextColor, fontSize: 16, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.logout, color: iconColor.withOpacity(0.7), size: 20),
                        ],
                      ),
                    ),
                  )
                else // Optional: Show guest state
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 22, backgroundColor: Colors.grey[300], child: Icon(Icons.person_off, color: Colors.grey[600])),
                          const SizedBox(width: 16),
                          Text("Not Logged In", style: TextStyle(color: textFieldTextColor)),
                        ],
                      )
                  ),

                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // --- Menu Buttons ---
                _buildMenuButton(
                  icon: Icons.add_circle_outline,
                  text: 'New Chat',
                  onTap: onNewChat,
                  iconColor: iconColor,
                  textColor: textFieldTextColor,
                  bgColor: menuBackgroundColor,
                ),
                _buildMenuButton(
                  icon: Icons.bookmark_outline,
                  text: 'Bookmarks',
                  onTap: onShowBookmarks,
                  iconColor: iconColor,
                  textColor: textFieldTextColor,
                  bgColor: menuBackgroundColor,
                ),

                // --- Stud Zone (Updated) ---
                _buildMenuButton(
                  icon: Icons.school_outlined,
                  text: 'Stud Zone',
                  trailing: Icon(
                    isStudZoneOpen ? Icons.expand_less : Icons.expand_more,
                    color: iconColor,
                  ),
                  isSelected: isStudZoneOpen,
                  selectedColor: menuButtonSelectedColor,
                  onTap: onToggleStudZone,
                  iconColor: iconColor,
                  textColor: textFieldTextColor,
                  bgColor: menuBackgroundColor,
                ),
                AnimatedCrossFade(
                  firstChild: Container(), // Empty container when closed
                  secondChild: Padding(
                    padding: const EdgeInsets.only(left: 16.0), // Indent sub-items
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMenuButton(
                          text: 'Daily Quiz',
                          onTap: () {
                            onToggleMenu(); // Close menu before navigating
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const DailyQuizScreen()),
                            );
                          },
                          isSubItem: true,
                          textColor: textFieldTextColor,
                          bgColor: menuBackgroundColor,
                          selectedColor: menuButtonSelectedColor,
                        ),
                        _buildMenuButton(
                          text: 'Time Based Test',
                          onTap: () {
                            onToggleMenu(); // Close menu before navigating
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const TimeBasedScreen()),
                            );
                          },
                          isSubItem: true,
                          textColor: textFieldTextColor,
                          bgColor: menuBackgroundColor,
                          selectedColor: menuButtonSelectedColor,
                        ),
                        // --- VVV NEW STUD STATS BUTTON VVV ---
                        _buildMenuButton(
                          text: 'Study Stats', // <<< NEW
                          onTap: () {
                            onToggleMenu(); // Close menu
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const StudStatsScreen()),
                            );
                          },
                          isSubItem: true,
                          textColor: textFieldTextColor,
                          bgColor: menuBackgroundColor,
                          selectedColor: menuButtonSelectedColor,
                        ),
                        // --- ^^^ NEW STUD STATS BUTTON ^^^ ---
                      ],
                    ),
                  ),
                  crossFadeState: isStudZoneOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                  sizeCurve: Curves.easeInOut,
                ),

                const Divider(height: 24), // Adjusted spacing

                // --- Dark Mode Toggle ---
                _buildMenuButton(
                  icon: isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  text: isDarkMode ? 'Light Mode' : 'Dark Mode',
                  onTap: onToggleDarkMode,
                  iconColor: iconColor,
                  textColor: textFieldTextColor,
                  bgColor: menuBackgroundColor,
                ),

                const Spacer(), // Push past chats to the bottom

                // --- Past Chats Section (Updated) ---
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text(
                      'Recent Chats', // Renamed for clarity
                      style: TextStyle(color: iconColor.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w500)
                  ),
                ),
                Expanded( // Allow list to take remaining space
                  child: recentChats.isEmpty
                      ? Center(
                      child: Text(
                        "No recent chats yet.",
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      )
                  )
                      : ListView.builder(
                    shrinkWrap: true,
                    itemCount: recentChats.length,
                    itemBuilder: (context, index) {
                      final chatMeta = recentChats[index];
                      return _buildMenuButton( // Use helper for consistent look
                        icon: Icons.chat_bubble_outline,
                        text: chatMeta.title,
                        subText: subtitleFormat.format(chatMeta.lastUpdated), // Add formatted date
                        onTap: () => onLoadPastChat(chatMeta.chatId), // Pass chatId
                        iconColor: iconColor,
                        textColor: textFieldTextColor,
                        bgColor: menuBackgroundColor,
                        selectedColor: menuButtonSelectedColor,
                        isPastChat: true, // Flag for styling
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10), // Padding at the bottom
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper Widget for Menu Buttons (Updated for subtitle and styling)
  Widget _buildMenuButton({
    IconData? icon,
    required String text,
    String? subText, // Optional subtitle for past chats
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
    Color? bgColor,
    Color? selectedColor,
    Widget? trailing,
    bool isSelected = false,
    bool isSubItem = false,
    bool isPastChat = false, // Flag for past chat styling
  }) {
    final effectiveBgColor = isSelected ? (selectedColor ?? Colors.grey.withOpacity(0.2)) : bgColor;
    final double leftPadding = isSubItem ? 32.0 : (isPastChat ? 0 : 8.0); // Adjust padding
    final double verticalPadding = isPastChat ? 6.0 : 12.0; // Less vertical padding for chats

    return Material(
      color: effectiveBgColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.only(
              left: leftPadding, top: verticalPadding, bottom: verticalPadding, right: 8.0),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: iconColor, size: isPastChat ? 20 : 22),
                SizedBox(width: isPastChat ? 12 : 16),
              ] else if (!isSubItem && !isPastChat) ...[
                // Add placeholder only if NOT a subitem/pastchat and NO icon
              ],
              Expanded(
                  child: Column( // Use column for title and optional subtitle
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        text,
                        style: TextStyle(
                            color: textColor,
                            fontSize: isPastChat ? 15 : 16,
                            fontWeight: isSelected ? FontWeight.w500: FontWeight.normal
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subText,
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]
                    ],
                  )
              ),
              if (trailing != null) Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: trailing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}