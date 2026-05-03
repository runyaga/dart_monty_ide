import 'package:dart_monty_ide/src/llm/llm_service.dart';
import 'package:dart_monty_ide/src/ui/chat_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('approxTokenCount', () {
    test('empty list returns 0', () {
      expect(approxTokenCount([]), 0);
    });

    test('counts user message content', () {
      // 40 chars / 4 = 10 tokens
      final msg = ChatMessage(role: 'user', content: 'a' * 40);
      expect(approxTokenCount([msg]), 10);
    });

    test('counts assistant message content', () {
      final msg = ChatMessage(role: 'assistant', content: 'b' * 80);
      expect(approxTokenCount([msg]), 20);
    });

    test('counts tool-result (role=tool) content', () {
      final msg = ChatMessage(
        role: 'tool',
        content: '{"status":"success"}', // 20 chars → 5 tokens
        toolCallId: 'call-1',
      );
      expect(approxTokenCount([msg]), 5);
    });

    test('skips isUiOnly messages entirely', () {
      final real = ChatMessage(role: 'user', content: 'a' * 40);
      final ui = ChatMessage(
        role: 'assistant',
        content: '⚙️ Calling run_python...',
        isUiOnly: true,
      );
      // Only the real message's 40 chars should count.
      expect(approxTokenCount([real, ui]), 10);
    });

    test('counts tool-call id + name + arguments, not just content', () {
      final tc = LlmToolCall(
        id: 'i' * 8,   // 8 chars
        name: 'n' * 8, // 8 chars
        arguments: {'code': 'x' * 16}, // key=4, value=16 → 20 chars
      );
      // Total chars = 8+8+20 = 36 → 9 tokens
      final msg = ChatMessage(
        role: 'assistant',
        content: '',
        toolCalls: [tc],
      );
      expect(approxTokenCount([msg]), 9);
    });

    test('content AND tool-calls are both counted on assistant messages', () {
      final tc = LlmToolCall(
        id: 'i' * 4,
        name: 'n' * 4,
        arguments: {'k': 'v' * 4}, // key=1, value=4 → 5 chars
      );
      // content: 40 chars, tool call: 4+4+5 = 13 chars → total 53 → 13 tokens
      final msg = ChatMessage(
        role: 'assistant',
        content: 'a' * 40,
        toolCalls: [tc],
      );
      expect(approxTokenCount([msg]), 13);
    });

    test('multiple tool calls on one message are all counted', () {
      LlmToolCall tc(String id) => LlmToolCall(
            id: id,
            name: 'n' * 4,
            arguments: {'k': 'v'},
          );
      // Each tc: id(4)+name(4)+key(1)+val(1)=10 chars → 3 tcs = 30 chars
      // content: 20 chars → total 50 → (50/4).round() = 13 tokens
      final msg = ChatMessage(
        role: 'assistant',
        content: 'c' * 20,
        toolCalls: [tc('i' * 4), tc('j' * 4), tc('k' * 4)],
      );
      expect(approxTokenCount([msg]), 13);
    });

    test('sums correctly across multiple messages', () {
      final messages = [
        ChatMessage(role: 'user', content: 'a' * 40),        // 10 tok
        ChatMessage(role: 'assistant', content: 'b' * 40),    // 10 tok
        ChatMessage(role: 'tool', content: 'c' * 40),         // 10 tok
        ChatMessage(role: 'assistant', content: '', isUiOnly: true), // skipped
      ];
      expect(approxTokenCount(messages), 30);
    });

    test('returns 0 for all-isUiOnly list', () {
      final messages = [
        ChatMessage(role: 'assistant', content: 'status...', isUiOnly: true),
        ChatMessage(role: 'assistant', content: 'more...', isUiOnly: true),
      ];
      expect(approxTokenCount(messages), 0);
    });

    test('systemPromptChars are included in token count', () {
      // 800 chars system prompt → 200 tokens
      expect(approxTokenCount([], systemPromptChars: 800), 200);
    });

    test('systemPromptChars added to message chars', () {
      // 400 chars sys prompt + 40 chars message = 440 → 110 tokens
      final msg = ChatMessage(role: 'user', content: 'a' * 40);
      expect(
        approxTokenCount([msg], systemPromptChars: 400),
        110,
      );
    });

    test('isUiOnly messages skipped even with systemPromptChars', () {
      final ui = ChatMessage(
        role: 'assistant',
        content: 'x' * 40,
        isUiOnly: true,
      );
      // Only system prompt chars should count (400 → 100 tokens).
      expect(approxTokenCount([ui], systemPromptChars: 400), 100);
    });
  });
}
