import 'package:flutter/material.dart';
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
  final GeminiService _geminiService = GeminiService();
  final SupabaseService _supabaseService = SupabaseService();
  final GitHubService _githubService = GitHubService();

  bool _isLoading = false;
  bool _isAnalyzingCode = false;
  String? _codeContext;

  Stream<List<AiChatMessage>>? _chatStream;

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
    } catch (e) {
      showErrorDialog(context, 'فشل تحليل الكود: $e');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingCode = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final canChat = widget.myMembership?.canUseChat ?? false;
    if (!canChat) {
      showPermissionDeniedDialog(context);
      return;
    }

    if (_controller.text.trim().isEmpty || widget.projectContext == null)
      return;

    final userMessage = _controller.text.trim();
    final projectId = widget.projectContext!.id;
    _controller.clear();

    await _supabaseService.addChatMessage(
        projectId: projectId, role: 'user', content: userMessage);

    setState(() => _isLoading = true);
    _scrollToBottom();

    final bugs = await _supabaseService.getBugsForProject(projectId);
    final history = await _supabaseService.getRecentChatHistory(projectId);

    final response = await _geminiService.generalChat(
      userMessage: userMessage,
      project: widget.projectContext,
      bugs: bugs,
      history: history,
      codeContext: _codeContext,
    );

    await _supabaseService.addChatMessage(
        projectId: projectId, role: 'model', content: response);

    if (mounted) {
      setState(() => _isLoading = false);
    }
    _scrollToBottom();
  }

  // ✨ --- Function to clear chat history --- ✨
  Future<void> _clearChatHistory() async {
    if (widget.projectContext == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح المحادثة'),
        content: const Text('هل أنت متأكد من رغبتك في مسح جميع رسائل هذه المحادثة؟ لا يمكن التراجع عن هذا الإجراء.'),
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
    // ✨ --- Check if the user is the leader --- ✨
    final bool isLeader = widget.myMembership?.role == 'leader';

    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ✨ --- Clear chat button, only visible to the leader --- ✨
                  if(isLeader && hasProject)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: _clearChatHistory,
                      tooltip: 'مسح سجل المحادثة',
                    )
                  else
                    const SizedBox(width: 48), // Placeholder for alignment
                  
                  Column(
                    children: [
                      Text('المساعد الذكي', style: Theme.of(context).textTheme.headlineSmall),
                      if (hasProject)
                        Text('مشروع: ${widget.projectContext!.name}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(width: 48), // Placeholder for alignment
                ],
              ),
              const Divider(height: 24),
              if (_isAnalyzingCode)
                const Padding(
                    padding: EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 4),
                        Text('جاري قراءة الملفات...')
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
                                child: Text(
                                    'خطأ في تحميل المحادثة: ${snapshot.error}'));
                          }

                          final messages = snapshot.data ?? [];

                          if (messages.isEmpty && !_isLoading) {
                            return const Center(
                                child: Text('مرحباً! كيف يمكنني مساعدتك؟'));
                          }

                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => _scrollToBottom());

                          final itemCount =
                              messages.length + (_isLoading ? 1 : 0);

                          return ListView.builder(
                            controller: _scrollController,
                            itemCount: itemCount,
                            itemBuilder: (context, index) {
                              if (index == messages.length && _isLoading) {
                                return _buildTypingIndicator();
                              }
                              final message = messages[index];
                              return _buildMessageBubble(message);
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: _controller,
                  enabled: !_isLoading && hasProject && canChat,
                  decoration: InputDecoration(
                    hintText: !hasProject
                        ? 'اختر مشروعاً أولاً'
                        : (canChat
                            ? 'اسأل عن مشروعك...'
                            : 'ليس لديك صلاحية للمحادثة'),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: (_isLoading || !hasProject || !canChat)
                          ? null
                          : _sendMessage,
                    ),
                  ),
                  onSubmitted: (_isLoading || !hasProject || !canChat)
                      ? null
                      : (_) => _sendMessage(),
                ),
              ),
            ],
          ),
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
            const Text("...يكتب"),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(AiChatMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment:
          isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).primaryColor
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: MarkdownBody(
          data: message.content,
          selectable: true,
          onTapLink: (text, href, title) async {
            if (href != null) {
              final uri = Uri.parse(href);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }
          },
        ),
      ),
    );
  }
}
