import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:async';
import '../models/project.dart';
import '../models/ai_chat_message.dart';
import '../models/hub_member.dart';
import '../services/gemini_service.dart';
import '../services/github_service.dart';
import '../services/supabase_service.dart';
import 'app_dialogs.dart';
import 'package:url_launcher/url_launcher.dart';
import 'code_file_view.dart';

class AiAssistantPanel extends StatefulWidget {
  final Project? projectContext;
  final HubMember? myMembership;

  const AiAssistantPanel({
    super.key,
    this.projectContext,
    this.myMembership,
  });

  @override
  State<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

class _AiAssistantPanelState extends State<AiAssistantPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // --- RE-ADDED: GeminiService instance for client-side calls ---
  final GeminiService _geminiService = GeminiService();
  final SupabaseService _supabaseService = SupabaseService();
  final GitHubService _githubService = GitHubService();

  bool _isAnalyzingCode = false;
  // --- RE-ADDED: Code context is needed for the Gemini call ---
  String? _codeContext; 

  Stream<List<AiChatMessage>>? _chatStream;
  List<AiChatMessage> _messages = []; 

  @override
  void initState() {
    super.initState();
    _setupChatStream();
    if (widget.projectContext?.githubUrl?.isNotEmpty ?? false) {
      _analyzeCodebase();
    }
  }

  @override
  void didUpdateWidget(covariant AiAssistantPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.projectContext?.id != oldWidget.projectContext?.id) {
      _setupChatStream();
      _codeContext = null; 
      if (widget.projectContext?.githubUrl?.isNotEmpty ?? false) {
        _analyzeCodebase();
      }
    }
  }

  void _setupChatStream() {
    setState(() {
      if (widget.projectContext != null) {
        _chatStream =
            _supabaseService.getChatHistoryStream(widget.projectContext!.id);
      } else {
        _chatStream = null;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Timer(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _analyzeCodebase() async {
    if (widget.projectContext?.githubUrl == null ||
        widget.projectContext!.githubUrl!.isEmpty) return;

    setState(() => _isAnalyzingCode = true);
    try {
      final code = await _githubService
          .fetchRepositoryCodeAsString(widget.projectContext!.githubUrl!);
      setState(() {
         _codeContext = code; 
      });
      if(mounted) showSuccessDialog(context, 'تم تحليل الكود بنجاح. يمكنك الآن طرح أسئلة حوله.');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'فشل تحليل الكود: $e');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingCode = false);
      }
    }
  }

  // --- REWRITTEN: New `sendMessage` logic ---
  Future<void> _sendMessage() async {
    final canChat = widget.myMembership?.canUseChat ?? false;
    if (!canChat) {
      showPermissionDeniedDialog(context);
      return;
    }

    if (_controller.text.trim().isEmpty || widget.projectContext == null) return;

    final userMessage = _controller.text.trim();
    final projectId = widget.projectContext!.id;
    _controller.clear();
    FocusScope.of(context).unfocus();

    try {
      // Step 1: Add user message to DB immediately
      await _supabaseService.addChatMessage(
          projectId: projectId, role: 'user', content: userMessage);
      
      _scrollToBottom();

      // Step 2: Trigger the AI response generation but DON'T await it.
      // This lets the UI continue without waiting for the network call to finish.
      _triggerGeminiResponse(projectId, userMessage);

    } catch(e) {
      if (mounted) {
        showErrorDialog(context, "فشل إرسال الرسالة: $e");
      }
    }
  }

  /// This function runs in the background to get and save the AI's response.
  Future<void> _triggerGeminiResponse(String projectId, String userMessage) async {
     try {
      final bugs = await _supabaseService.getBugsForProject(projectId);
      final history = await _supabaseService.getRecentChatHistory(projectId);

      final response = await _geminiService.generalChat(
        userMessage: userMessage,
        project: widget.projectContext,
        bugs: bugs,
        history: history,
        codeContext: _codeContext,
      );

      // Important: Check if the widget is still alive before saving the response
      if (!mounted) return;

      await _supabaseService.addChatMessage(
          projectId: projectId, role: 'model', content: response);

    } catch(e) {
      if (!mounted) return; // Don't show dialog if widget is disposed
      
      showTryAgainLaterDialog(context);
      await _supabaseService.addChatMessage(
          projectId: projectId, role: 'model', content: 'عذراً، حدث خطأ ولم أتمكن من إكمال الطلب.');
    }
  }


  Future<void> _clearChatHistory() async {
    if (widget.projectContext == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('مسح المحادثة'),
        content:
            const Text('هل أنت متأكد من رغبتك في مسح جميع رسائل هذه المحادثة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مسح', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabaseService.clearChatHistory(widget.projectContext!.id);
        if (mounted) {
          showSuccessDialog(context, 'تم مسح المحادثة بنجاح.');
        }
      } catch (e) {
        if (mounted) {
          showErrorDialog(context, 'فشل مسح المحادثة: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasProject = widget.projectContext != null;
    final bool canChat = widget.myMembership?.canUseChat ?? false;
    final bool isLeader = widget.myMembership?.role == 'leader';
    final bool hasGithubLink =
        widget.projectContext?.githubUrl?.isNotEmpty ?? false;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isLeader && hasProject)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: _clearChatHistory,
                      tooltip: 'مسح سجل المحادثة',
                    )
                  else
                    const SizedBox(width: 48),
                  Column(
                    children: [
                      Text('المساعد الذكي',
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (hasProject)
                        Text('مشروع: ${widget.projectContext!.name}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  if (hasGithubLink)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _isAnalyzingCode ? null : _analyzeCodebase,
                      tooltip: 'إعادة قراءة وتحليل الكود من GitHub',
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_isAnalyzingCode)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 4),
                      Text('جاري قراءة وتحليل الكود...')
                    ],
                  )),
            Expanded(
              child: !hasProject
                  ? const Center(
                      child: Text('الرجاء اختيار مشروع لبدء المحادثة.'))
                  : StreamBuilder<List<AiChatMessage>>(
                      stream: _chatStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                              child: Text('خطأ: ${snapshot.error}'));
                        }

                        _messages = snapshot.data ?? [];

                        if (_messages.isEmpty) {
                          return const Center(
                              child: Text('مرحباً! كيف يمكنني مساعدتك؟'));
                        }

                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _scrollToBottom());
                        
                        final bool showTypingIndicator = _messages.isNotEmpty && _messages.last.role == 'user';

                        final itemCount =
                            _messages.length + (showTypingIndicator ? 1 : 0);

                        return ListView.builder(
                          controller: _scrollController,
                          itemCount: itemCount,
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length && showTypingIndicator) {
                              return _buildTypingIndicator();
                            }
                            final message = _messages[index];
                            return _buildMessageBubble(message);
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 16,
                  right: 16,
                  top: 8),
              child: TextField(
                controller: _controller,
                enabled: hasProject && canChat && !_isAnalyzingCode,
                decoration: InputDecoration(
                  hintText: !hasProject
                      ? 'اختر مشروعاً أولاً'
                      : (_isAnalyzingCode
                          ? 'جاري تحليل الكود...'
                          : (canChat
                              ? 'اسأل عن مشروعك...'
                              : 'ليس لديك صلاحية للمحادثة')),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: (
                           !hasProject ||
                            !canChat ||
                            _isAnalyzingCode)
                        ? null
                        : _sendMessage,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.grey.shade400),
            ),
            const SizedBox(width: 10),
            const Text("...يفكر"),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(AiChatMessage message) {
    final isUser = message.role == 'user';
    final content = message.content;
    
    // This logic to handle code blocks can be removed if you are certain the AI won't send them.
    // However, it's safer to leave it to gracefully handle any accidental code snippets.
    final fileRegex = RegExp(
      r'--- START FILE: (.*?) ---\s*(.*?)\s*--- END FILE ---',
      dotAll: true, caseSensitive: false);

    final matches = fileRegex.allMatches(content);
    if (matches.isNotEmpty) {
      // If the AI accidentally sends code, show a placeholder message.
      return _buildMessageBubble(
        AiChatMessage(
          id: message.id, 
          userId: message.userId,
          projectId: message.projectId, 
          role: message.role, 
          content: '[تم استلام محتوى برمجي، ولكن تم حجبه بناءً على طلبك.]', 
          createdAt: message.createdAt
        )
      );
    }

    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).primaryColor
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isUser
              ? null
              : Border.all(color: Colors.grey.shade700, width: 0.5),
        ),
        child: MarkdownBody(
            data: content,
            selectable: true,
            onTapLink: (text, href, title) async {
              if (href != null) {
                final uri = Uri.parse(href);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              }
            },
          )
      ),
    );
  }
}

