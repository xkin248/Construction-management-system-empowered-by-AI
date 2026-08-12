import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/ai_chat.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});
  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  bool _loadingMessages = false;
  bool _sending = false;

  List<AiChatMessage> _messages = [];
  List<AiChatSession> _sessions = [];
  List<Map<String, dynamic>> _projects = [];

  int? _activeSessionId;
  int? _selectedProjectId;

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final results = await Future.wait([
        ApiService().getAiSessions(),
        ApiService().getProjects(),
      ]);
      _sessions = (results[0] as dynamic)
          .map((e) => AiChatSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _projects = (results[1] as dynamic).cast<Map<String, dynamic>>();
      _selectedProjectId ??=
          _projects.isNotEmpty ? _projects.first['project_id'] : null;

      if (_sessions.isNotEmpty && _activeSessionId == null) {
        _activeSessionId = _sessions.first.sessionId;
        _loadMessages();
      }
    } catch (e) {
      toast('Failed to load sessions: $e');
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMessages() async {
    if (_activeSessionId == null) return;
    setState(() => _loadingMessages = true);
    try {
      final raw =
          await ApiService().getAiMessages(_activeSessionId!);
      _messages = raw
          .map((e) =>
              AiChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      toast('Failed to load messages: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingMessages = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending || _selectedProjectId == null) return;

    // Optimistic user message
    final userMsg = AiChatMessage(
      messageId: DateTime.now().millisecondsSinceEpoch,
      sessionId: _activeSessionId ?? 0,
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages.add(userMsg);
      _msgCtrl.clear();
    });
    _scrollToBottom();

    setState(() => _sending = true);
    try {
      final result = await ApiService().sendAiChat(
        _selectedProjectId!,
        text,
        sessionId: _activeSessionId,
      );
      final reply = result['reply'] as String? ?? '';
      final sid = result['session_id'] as int?;
      if (sid != null && _activeSessionId == null) {
        _activeSessionId = sid;
        _loadSessions();
      }
      final aiMsg = AiChatMessage(
        messageId: DateTime.now().millisecondsSinceEpoch + 1,
        sessionId: sid ?? _activeSessionId ?? 0,
        role: 'assistant',
        content: reply,
        createdAt: DateTime.now(),
      );
      setState(() => _messages.add(aiMsg));
      _scrollToBottom();
    } catch (e) {
      toast('AI reply failed: $e');
      // Remove the optimistic user message on failure
      if (mounted && _messages.isNotEmpty && _messages.last.isUser) {
        setState(() => _messages.removeLast());
        _msgCtrl.text = text;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _newSession() {
    setState(() {
      _activeSessionId = null;
      _messages = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSession = _activeSessionId != null;
    final hasMessages = _messages.isNotEmpty;
    final showEmpty = !_loadingMessages && !hasMessages;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: Column(children: [
        // ── Top bar: session selector + new chat ──
        _buildTopBar(),
        // ── Messages ──
        Expanded(
          child: showEmpty
              ? _emptyState()
              : _loadingMessages
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) =>
                          _messageBubble(_messages[i]),
                    ),
        ),
        // ── Input bar ──
        _buildInputBar(hasSession),
      ]),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          // Project selector
          if (_projects.isNotEmpty)
            Expanded(
              flex: 3,
              child: _compactDropdown<int?>(
                value: _selectedProjectId,
                hint: 'Select project',
                items: _projects
                    .map((p) => DropdownMenuItem<int?>(
                        value: p['project_id'],
                        child: Text(
                          p['project_name'] ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(fontSize: 13),
                        )))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedProjectId = v),
              ),
            ),
          const SizedBox(width: 8),
          // Session selector
          Expanded(
            flex: 4,
            child: _compactDropdown<int?>(
              value: _activeSessionId,
              hint: 'New conversation',
              items: _sessions
                  .map((s) => DropdownMenuItem<int?>(
                      value: s.sessionId,
                      child: Text(
                        s.title,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(fontSize: 13),
                      )))
                  .toList(),
              onChanged: (v) {
                setState(() => _activeSessionId = v);
                if (v != null) _loadMessages();
              },
            ),
          ),
          const SizedBox(width: 6),
          // New chat button
          SizedBox(
            height: 38,
            child: TextButton.icon(
              onPressed: _newSession,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _compactDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>>? items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.bgMain,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items != null && items.any((i) => i.value == value)
              ? value
              : null,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded,
              size: 18, color: AppColors.textMuted),
          style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600),
          hint: Text(hint,
              style: GoogleFonts.outfit(
                  fontSize: 13, color: AppColors.textMuted)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.15),
                    AppColors.blue.withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text('BuildSmart AI',
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Ask me anything about your projects —\ntask planning, worker assignments, reports...',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ]),
        ),
      );

  Widget _messageBubble(AiChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.blue : AppColors.bgCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUser)
              Text(msg.content,
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.45))
            else
              MarkdownBody(
                data: msg.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.45),
                  code: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      backgroundColor: AppColors.bgMain),
                  codeblockDecoration: BoxDecoration(
                    color: AppColors.bgMain,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  h1: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  h2: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  strong: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                          color: AppColors.accent, width: 3),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _fmtTime(msg.createdAt),
              style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: isUser
                      ? Colors.white70
                      : AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool hasSession) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: TextField(
                  controller: _msgCtrl,
                  focusNode: _focusNode,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _selectedProjectId == null
                        ? 'Select a project first...'
                        : 'Ask about tasks, workers, reports...',
                    hintStyle: GoogleFonts.outfit(
                        fontSize: 13.5, color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.bgMain,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppColors.accent, width: 1.4),
                    ),
                  ),
                  style: GoogleFonts.outfit(
                      fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: Material(
                color: (_msgCtrl.text.trim().isNotEmpty &&
                        !_sending &&
                        _selectedProjectId != null)
                    ? AppColors.accent
                    : AppColors.border,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _msgCtrl.text.trim().isNotEmpty && !_sending
                      ? _send
                      : null,
                  child: _sending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
