import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'session.dart';
import 'venue_detail.dart';

String _suffix(String uid) =>
    uid.length > 8 ? uid.substring(uid.length - 8) : uid;
String _role(String? role) => switch (role) {
  'manager' => '施設責任者',
  'editor' => '担当者',
  'none' => '権限なし',
  _ => '確認待ち',
};
String _date(Object? raw) =>
    DateTime.tryParse('$raw')?.toLocal().toString().substring(0, 16) ?? '';
String accessLink(String token) =>
    Uri.base.resolve('/').replace(fragment: 'access=$token').toString();
String accessError(Object e) =>
    e is RulesApiException ? e.message : '接続できませんでした。再試行してください。';

class IssuedAccessLink extends StatelessWidget {
  const IssuedAccessLink({
    super.key,
    required this.link,
    required this.verification,
  });
  final Map<String, dynamic> link;
  final bool verification;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verification ? '公式窓口へ送る確認リンク' : '担当者へ送る招待リンク',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            verification
                ? '運営が確認した公式窓口へ、メールなどで手動共有してください。この画面からの自動送信はありません。申請者には渡さないでください。'
                : '招待したい相手へ直接共有してください。相手の氏名・メールアドレスの入力は不要です。',
          ),
          Text('期限：${_date(link['expiresAt'])}／1回限り'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: accessLink(link['token'] as String)),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('リンクをコピーしました。')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('リンクをコピー'),
          ),
          const Text('リンクはこの画面を閉じると再表示できません。再発行した確認リンクは古いものを無効にします。'),
        ],
      ),
    ),
  );
}

class FacilityAccessPage extends StatefulWidget {
  const FacilityAccessPage({
    super.key,
    required this.api,
    required this.venueId,
  });
  final RulesApi api;
  final String venueId;
  @override
  State<FacilityAccessPage> createState() => _FacilityAccessPageState();
}

class _FacilityAccessPageState extends State<FacilityAccessPage> {
  Map<String, dynamic>? view, link;
  String error = '', inviteRole = 'editor';
  bool busy = false, requested = false;
  @override
  void initState() {
    super.initState();
    run(() async {
      view = await widget.api.access(widget.venueId);
    });
  }

  Future<void> run(Future<void> Function() op) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await op();
    } catch (e) {
      if (mounted) setState(() => error = accessError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(Map<String, dynamic> m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この権限を解除しますか？'),
        content: Text('アカウント末尾 ${_suffix(m['uid'])} の施設へのアクセスを終了します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('解除する'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await run(() async {
        view = await widget.api.revoke(widget.venueId, m['uid']);
        link = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = view?['role'] as String?;
    final members = (view?['members'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final managerCount = members.where((m) => m['role'] == 'manager').length;
    return Scaffold(
      appBar: AppBar(title: const Text('施設の管理権限')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error.isNotEmpty) InfoBox(error, warning: true),
          if (view != null) ...[
            Text(
              view!['name'] ?? '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('現在の権限：${_role(role)}'),
            SelectableText('自分の確認ID（末尾）：${_suffix(view!['uid'])}'),
            if (view!['expiresAt'] != null)
              Text('期限：${_date(view!['expiresAt'])}'),
            const SizedBox(height: 16),
            if (role == 'unverified') ...[
              const InfoBox(
                '公開には施設責任者の確認が必要です。運営が公式窓口へ承認リンクを送り、その窓口で委任が確認されると申請できます。',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy || requested
                    ? null
                    : () => run(() async {
                        await widget.api.requestVerification(widget.venueId);
                        requested = true;
                      }),
                child: Text(requested ? '確認を依頼しました' : '運営に責任者確認を依頼'),
              ),
              const SizedBox(height: 8),
              SelectableText('施設ID：${widget.venueId}'),
              const Text('公式窓口へ確認IDを伝え、委任先が一致しているか確認してもらってください。'),
              TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        view = await widget.api.access(widget.venueId);
                      }),
                child: const Text('確認結果を再読み込み'),
              ),
            ],
            if (role == 'manager') ...[
              const Text('責任者は担当者の招待と解除ができます。権限はこの施設に限り、最長90日です。'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: inviteRole,
                decoration: const InputDecoration(labelText: '招待する権限'),
                items: const [
                  DropdownMenuItem(
                    value: 'editor',
                    child: Text('担当者：ルール編集・申請'),
                  ),
                  DropdownMenuItem(
                    value: 'manager',
                    child: Text('施設責任者：担当者の管理も可能'),
                  ),
                ],
                onChanged: busy ? null : (v) => setState(() => inviteRole = v!),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        link = await widget.api.invite(
                          widget.venueId,
                          inviteRole,
                        );
                      }),
                child: const Text('招待リンクを発行'),
              ),
              if (link != null)
                IssuedAccessLink(link: link!, verification: false),
              const SizedBox(height: 24),
              const Text('現在の責任者・担当者'),
              for (final m in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_role(m['role'])}／ID末尾 ${_suffix(m['uid'])}'),
                  subtitle: Text(
                    '期限：${_date(m['expiresAt'])}${m['uid'] == view!['uid'] ? '（自分）' : ''}',
                  ),
                  trailing: TextButton(
                    onPressed:
                        busy || (m['role'] == 'manager' && managerCount <= 1)
                        ? null
                        : () => revoke(m),
                    child: const Text('解除'),
                  ),
                ),
              const Text('最後の責任者は解除できません。引き継ぐ場合は別の責任者を招待してください。'),
            ],
            if (role == 'editor')
              const InfoBox('この施設のルールを編集・申請できます。担当者の招待や解除は施設責任者が行います。'),
          ],
        ],
      ),
    );
  }
}

class VerificationRequestsPage extends StatefulWidget {
  const VerificationRequestsPage({
    super.key,
    required this.api,
    required this.operator,
  });
  final RulesApi api;
  final bool operator;
  @override
  State<VerificationRequestsPage> createState() =>
      _VerificationRequestsPageState();
}

class _VerificationRequestsPageState extends State<VerificationRequestsPage> {
  List<Map<String, dynamic>> requests = [];
  Map<String, dynamic>? issued;
  String error = '';
  bool busy = false;
  final facilityId = TextEditingController();
  @override
  void initState() {
    super.initState();
    run(() async {
      requests = await widget.api.accessRequests();
    });
  }

  @override
  void dispose() {
    facilityId.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() op) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await op();
    } catch (e) {
      if (mounted) setState(() => error = accessError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> issue(Map<String, dynamic> r) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _OfficialChannelDialog(name: r['name']),
    );
    if (url != null) {
      await run(() async {
        issued = await widget.api.issueVerification(r['id'], url);
        requests = await widget.api.accessRequests();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.operator ? '施設責任者の確認' : '責任者確認の依頼')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) InfoBox(error, warning: true),
        if (widget.operator)
          const InfoBox(
            '確認リンクは、独立に確認した公式窓口だけへ手動送信してください。アカウントIDの末尾を照合し、本人の委任を確認します。ルール内容の承認は、その後に別途行います。',
          ),
        if (!widget.operator) ...[
          const Text(
            '施設の編集画面から確認を依頼できます。期限切れなどで一覧に施設が出ない場合は、施設IDで再確認を依頼してください。',
          ),
          TextField(
            controller: facilityId,
            decoration: const InputDecoration(labelText: '施設ID'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.api.requestVerification(
                      facilityId.text.trim(),
                    );
                    requests = await widget.api.accessRequests();
                  }),
            child: const Text('再確認を依頼'),
          ),
        ],
        if (issued != null) IssuedAccessLink(link: issued!, verification: true),
        const SizedBox(height: 20),
        if (requests.isEmpty) const Text('確認依頼はありません。'),
        for (final r in requests)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['name'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('確認ID末尾：${_suffix(r['uid'])}'),
                  Text(
                    '状態：${switch (r['status']) {
                      'confirmed' => '確認済み',
                      'issued' => 'リンク発行済み（送信は手動）',
                      _ => '依頼中',
                    }}',
                  ),
                  if ((r['website'] ?? '').isNotEmpty)
                    TextButton(
                      onPressed: () => openSource(r['website']),
                      child: const Text('申請に記載されたサイトを開く'),
                    ),
                  if (widget.operator && r['status'] != 'confirmed')
                    FilledButton(
                      onPressed: busy ? null : () => issue(r),
                      child: const Text('公式窓口を確認してリンク発行'),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _OfficialChannelDialog extends StatefulWidget {
  const _OfficialChannelDialog({required this.name});
  final String name;
  @override
  State<_OfficialChannelDialog> createState() => _OfficialChannelDialogState();
}

class _OfficialChannelDialogState extends State<_OfficialChannelDialog> {
  final source = TextEditingController();
  bool checked = false;
  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('公式窓口を確認'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.name),
          const SizedBox(height: 12),
          const Text('申請者が入力したURLだけで判断せず、運営が公式サイトと窓口を確認してください。連絡先の入力・保存は不要です。'),
          TextField(
            controller: source,
            decoration: const InputDecoration(
              labelText: '独立に確認した公式サイトURL',
              hintText: 'https://...',
            ),
          ),
          CheckboxListTile(
            value: checked,
            onChanged: (v) => setState(() => checked = v ?? false),
            title: const Text('公式サイト・窓口と、申請者の確認IDを照合しました'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('戻る'),
      ),
      FilledButton(
        onPressed: checked
            ? () => Navigator.pop(context, source.text.trim())
            : null,
        child: const Text('確認リンクを発行'),
      ),
    ],
  );
}

class AccessLinkPage extends StatefulWidget {
  const AccessLinkPage({
    super.key,
    required this.rawToken,
    required this.onDone,
  });
  final String rawToken;
  final VoidCallback onDone;
  @override
  State<AccessLinkPage> createState() => _AccessLinkPageState();
}

class _AccessLinkPageState extends State<AccessLinkPage> {
  final session = AdminSession(
    demo: const bool.fromEnvironment('POSTCHECK_DEMO'),
  );
  Map<String, dynamic>? preview;
  bool checked = false, busy = false, done = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    run(() async {
      preview = await session.api.previewAccess(widget.rawToken);
    });
  }

  @override
  void dispose() {
    session.api.close();
    super.dispose();
  }

  Future<void> run(Future<void> Function() op) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await op();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is RulesApiException && e.status == 404
              ? '期限切れ・使用済み・無効なリンクです。発行元に確認してください。'
              : accessError(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verification = preview?['kind'] == 'verification';
    return Scaffold(
      appBar: AppBar(title: const Text('施設の権限確認')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error.isNotEmpty) InfoBox(error, warning: true),
              if (done) ...[
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 16),
                Text(
                  verification
                      ? '指定の申請アカウントへ施設責任者権限を付与しました。'
                      : 'この施設の招待を受け付けました。',
                ),
                const Text('リンクは使用済みです。管理画面でログインして確認してください。'),
                FilledButton(
                  onPressed: widget.onDone,
                  child: const Text('管理画面へ'),
                ),
              ] else if (preview != null) ...[
                Text(
                  preview!['name'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text('付与する権限：${_role(preview!['role'])}'),
                Text('リンクの期限：${_date(preview!['expiresAt'])}'),
                if (verification) ...[
                  Text('委任先の確認ID末尾：${preview!['accountSuffix']}'),
                  const InfoBox(
                    'この施設の公式窓口として、申請アカウントにルール管理を委任してよいか確認してください。申請者本人から聞いた確認IDとの一致を確かめてください。',
                  ),
                ] else ...[
                  const Text(
                    '招待された本人のGoogleアカウントでログインしてください。権限はこの施設だけに適用されます。',
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await session.login(asStaff: true);
                          }),
                    child: Text(
                      session.actor == null
                          ? 'Googleでログイン'
                          : '別のGoogleアカウントでログイン',
                    ),
                  ),
                  if (session.actor != null)
                    Text('ログイン中の確認ID末尾：${_suffix(session.actor!['uid'])}'),
                ],
                CheckboxListTile(
                  value: checked,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => checked = v ?? false),
                  title: Text(
                    verification
                        ? '指定アカウントへの管理委任を確認しました'
                        : 'この施設の担当者として招待を受けます',
                  ),
                ),
                FilledButton(
                  onPressed:
                      busy ||
                          !checked ||
                          (!verification && session.actor == null)
                      ? null
                      : () => run(() async {
                          await session.api.consumeAccess(widget.rawToken);
                          done = true;
                        }),
                  child: Text(verification ? '管理を委任する' : '招待を受ける'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
