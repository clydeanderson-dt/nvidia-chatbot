import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0066CC) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'YOU' : 'ASSISTANT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: isUser
                    ? Colors.white.withValues(alpha: 0.65)
                    : Colors.black.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 4),
            if (isStreaming && content.isEmpty)
              const _TypingIndicator()
            else if (isUser)
              Text(
                content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.55,
                ),
              )
            else
              MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 15,
                    height: 1.55,
                  ),
                  code: TextStyle(
                    backgroundColor: Colors.black.withValues(alpha: 0.08),
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  blockquotePadding: const EdgeInsets.only(left: 12),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Colors.black.withValues(alpha: 0.2),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        duration: const Duration(milliseconds: 1200),
        vsync: this,
      )..repeat(reverse: false);
    });

    _animations = List.generate(3, (i) {
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 30),
        TweenSequenceItem(tween: Tween(begin: -6, end: 0), weight: 30),
        TweenSequenceItem(tween: ConstantTween(0.0), weight: 40),
      ]).animate(
        CurvedAnimation(
          parent: _controllers[i],
          curve: Interval(i * 0.167, 1.0),
        ),
      );
    });

    for (final c in _controllers) {
      c.forward();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (_, child) => Transform.translate(
            offset: Offset(0, _animations[i].value),
            child: child,
          ),
          child: Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: const BoxDecoration(
              color: Color(0xFF555555),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}
