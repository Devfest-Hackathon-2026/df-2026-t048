import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:postcheck_rules/postcheck_rules.dart';
import 'app_theme.dart';
import 'access_page.dart';
import 'step_pill.dart';
import 'venue_detail.dart';

class VenueEditor extends StatefulWidget {
  const VenueEditor({super.key, required this.api, this.venue});
  final RulesApi api;
  final ManagedVenue? venue;
  @override
  State<VenueEditor> createState() => _VenueEditorState();
}

class _VenueEditorState extends State<VenueEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  int step = 0;
  bool busy = false, ack = false, dirty = false;
  Future<void>? _saveInFlight;
  int _editRevision = 0;
  Timer? _autoSaveTimer;
  String error = '';
  ManagedVenue? saved;
  late final VenuePolicy originalPolicy;
  String get visibility => originalPolicy.visibility;
  final checkTargets = <String>{};
  double lat = 35.6586, lng = 139.7454;
  @override
  void initState() {
    super.initState();
    saved = widget.venue;
    final p = saved?.draft ?? const VenuePolicy(name: '');
    originalPolicy = p;
    final addressParts = _splitAddress(p.address);
    final values = {
      'applicationName': p.applicationName,
      'name': p.name,
      'postal': addressParts.$1,
      'address': addressParts.$2,
      'website': p.website,
      'lat': saved == null ? '' : p.latitude.toString(),
      'lng': saved == null ? '' : p.longitude.toString(),
    };
    for (final e in values.entries) {
      fields[e.key] = TextEditingController(text: e.value)
        ..addListener(_markDirty);
    }
    checkTargets.addAll(p.checkTargets);
    lat = p.latitude;
    lng = p.longitude;
  }

  String value(String key) => fields[key]!.text.trim();

  /// 施設の住所から郵便番号を分離する。
  static (String, String) _splitAddress(String raw) {
    final m = RegExp(
      r'^〒?\s*(\d{3}-?\d{4})\s*[\n\r\s]*(.*)$',
      dotAll: true,
    ).firstMatch(raw.trim());
    if (m == null) return ('', raw.trim());
    return (m.group(1)!, (m.group(2) ?? '').trim());
  }

  String _joinedAddress() {
    final postal = value('postal').replaceAll(' ', '');
    final address = value('address');
    if (postal.isEmpty) return address;
    final normalized = RegExp(r'^\d{7}$').hasMatch(postal)
        ? '${postal.substring(0, 3)}-${postal.substring(3)}'
        : postal;
    if (address.isEmpty) return '〒$normalized';
    return '〒$normalized\n$address';
  }

  VenuePolicy policy() => VenuePolicy.fromJson({
    // Preserve existing rule details without exposing them as new inputs.
    ...originalPolicy.toJson(),
    'name': value('name'),
    'applicationName': value('applicationName'),
    'address': _joinedAddress(),
    'latitude': double.parse(value('lat')),
    'longitude': double.parse(value('lng')),
    'website': value('website'),
    'checkTargets': venueCheckTargets.where(checkTargets.contains).toList(),
  });
  Widget _checkTargetsEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      const Text(
        'この施設で必ず指摘する項目',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const Text('オンにした項目は、この施設の近くで撮影・投稿する利用者に、本人の設定に関係なく指摘されます。初期値はすべてオフです。'),
      for (final target in venueCheckTargets)
        CheckboxListTile(
          key: ValueKey('checkTarget-$target'),
          contentPadding: EdgeInsets.zero,
          title: Text(venueCheckTargetLabels[target] ?? target),
          value: checkTargets.contains(target),
          onChanged: busy
              ? null
              : (selected) {
                  setState(() {
                    if (selected == true) {
                      checkTargets.add(target);
                    } else {
                      checkTargets.remove(target);
                    }
                  });
                  _markDirty();
                },
        ),
    ],
  );

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!mounted) return;
    _editRevision++;
    setState(() {
      dirty = true;
      ack = false;
    });
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && dirty) unawaited(persist(silent: true));
    });
  }

  Future<bool> confirmLeave() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('保存せずに戻りますか？'),
            content: const Text('未保存の変更が失われます。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('編集を続ける'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('戻る'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _goBack() async {
    if (busy) return;
    if (step > 0) {
      setState(() => step--);
      return;
    }
    _autoSaveTimer?.cancel();
    if (dirty) await persist(silent: true);
    if (!mounted) return;
    if (dirty && !await confirmLeave()) return;
    if (mounted) Navigator.pop(context);
  }

  Future<void> persist({bool submit = false, bool silent = false}) async {
    if (busy || (silent && _saveInFlight != null)) return;
    if (!silent && !form.currentState!.validate()) return;
    _autoSaveTimer?.cancel();
    if (!silent) {
      setState(() {
        busy = true;
        error = '';
      });
    }
    // An explicit save/submit waits for autosave rather than issuing another create.
    final pending = _saveInFlight;
    if (pending != null) await pending;
    if (!mounted) return;
    final done = Completer<void>();
    setState(() {
      _saveInFlight = done.future;
    });
    final revision = _editRevision;
    var succeeded = false;
    try {
      final p = policy();
      if (submit) {
        final missing = <String>[
          if (p.applicationName.isEmpty) '申請名',
          if (p.address.isEmpty) '住所',
        ];
        if (missing.isNotEmpty) {
          throw FormatException('入力を確認してください：${missing.join('、')}');
        }
        if (visibility == 'public' && !ack) {
          throw const FormatException('公開範囲を確認してください。');
        }
      }
      if (utf8
              .encode(
                jsonEncode({
                  'policy': p.toJson(),
                  'version': saved?.version ?? 0,
                }),
              )
              .length >
          64 * 1024) {
        throw const FormatException('入力全体が64KBを超えています。画像や文章を小さくしてください。');
      }
      saved = await widget.api.save(p, existing: saved);
      if (submit) {
        saved = await widget.api.change(
          saved!,
          'submit',
          publicAcknowledged: ack,
        );
      }
      succeeded = true;
      if (mounted) {
        setState(() {
          dirty = _editRevision != revision;
          error = '';
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(submit ? '申請を受け付けました。承認後に反映されます。' : '下書きを保存しました。'),
            ),
          );
        }
        if (submit) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      }
    } catch (e) {
      if (mounted && !(silent && e is FormatException)) {
        setState(
          () => error = e is RulesApiException
              ? e.message
              : e is FormatException && e.message.isNotEmpty
              ? e.message
              : '入力内容を見直してください。座標・日時の形式も確認してください。',
        );
      }
    } finally {
      _saveInFlight = null;
      done.complete();
      if (mounted) {
        setState(() {
          if (!silent) busy = false;
        });
        // Changes made while saving must remain dirty and get a new snapshot.
        if (succeeded && dirty) _scheduleAutoSave();
      }
    }
  }

  Widget _badge({required bool required}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: required
          ? PostCheckPalette.primary.withValues(alpha: 0.12)
          : PostCheckPalette.border,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      required ? '必須' : '任意',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: required ? PostCheckPalette.primary : PostCheckPalette.secondary,
      ),
    ),
  );

  Widget field(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
    String? hint,
    Widget? suffix,
    void Function(String)? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PostCheckPalette.ink,
              ),
            ),
            const SizedBox(width: 8),
            _badge(required: required),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('venue-$key'),
          controller: fields[key],
          enabled: !busy,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 6,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
          validator: (v) {
            if (required && (v ?? '').trim().isEmpty) return '入力してください';
            if (['lat', 'lng'].contains(key)) {
              final n = double.tryParse(v ?? '');
              if (n == null ||
                  !n.isFinite ||
                  n.abs() > (key == 'lat' ? 90 : 180)) {
                return '有効な座標を入力してください';
              }
            }
            if (key == 'website' && (v ?? '').trim().isNotEmpty) {
              final u = Uri.tryParse(v!.trim());
              if (u == null || u.scheme != 'https' || u.host.isEmpty) {
                return 'https:// から始まるURLを入力してください';
              }
            }
            if (key == 'sourceUrl' && (v ?? '').trim().isNotEmpty) {
              final u = Uri.tryParse(v!.trim());
              if (u == null || u.scheme != 'https' || u.host.isEmpty) {
                return 'https:// から始まるURLを入力してください';
              }
            }
            if (key == 'postal' && (required || (v ?? '').trim().isNotEmpty)) {
              final p = v!.trim().replaceAll(' ', '');
              if (!RegExp(r'^\d{3}-?\d{4}$').hasMatch(p)) {
                return '例：100-0001';
              }
            }
            return null;
          },
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && !busy && await confirmLeave() && mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(title: Text(saved == null ? '新規申請' : '施設・ルールを編集')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            if (busy) const LinearProgressIndicator(),
            Text(
              busy || _saveInFlight != null
                  ? '保存中…'
                  : dirty
                  ? '未保存の変更があります'
                  : saved == null
                  ? ''
                  : '下書き保存済み',
              style: const TextStyle(color: PostCheckPalette.secondary),
            ),
            if (error.isNotEmpty) InfoBox(error, warning: true),
            StepPill(step: step),
            const SizedBox(height: 28),
            if (step == 0)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      field(
                        'applicationName',
                        '申請名',
                        required: true,
                        hint: '例：春の展示ルール申請',
                      ),
                      if (const bool.fromEnvironment('MAPS_ENABLED'))
                        SizedBox(
                          height: 280,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(lat, lng),
                                zoom: 15,
                              ),
                              onTap: _position,
                              markers: {
                                Marker(
                                  markerId: const MarkerId('venue'),
                                  position: LatLng(lat, lng),
                                  draggable: true,
                                  onDragEnd: _position,
                                ),
                              },
                            ),
                          ),
                        )
                      else
                        const InfoBox('地図は未設定です。施設の正確な緯度・経度を入力してください。'),
                      const SizedBox(height: 16),
                      field('lat', '緯度', required: true, hint: '例：34.6937'),
                      field('lng', '経度', required: true, hint: '例：135.5023'),
                      const SizedBox(height: 28),
                      field('name', '施設名', required: true, hint: '例：架空アリーナ'),
                      field('website', '公式サイト', hint: 'https://example.com'),
                      field('postal', '郵便番号', required: true, hint: '100-0001'),
                      field('address', '住所', required: true, hint: '東京都千代田区…'),
                      const Text(
                        '担当者の氏名・電話・メールは入力不要です。Googleログインの情報はFirebase Authenticationで管理します。',
                        style: TextStyle(
                          color: PostCheckPalette.secondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (step == 1)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _checkTargetsEditor(),
                ),
              ),
            if (step == 2) _preview(),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : _goBack,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('戻る'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          busy || (step == 2 && visibility == 'public' && !ack)
                          ? null
                          : () async {
                              if (step < 2) {
                                if (form.currentState!.validate()) {
                                  _autoSaveTimer?.cancel();
                                  if (dirty) await persist(silent: true);
                                  if (!mounted || dirty || saved == null) {
                                    return;
                                  }
                                  setState(() {
                                    error = '';
                                    step++;
                                  });
                                }
                              } else {
                                await persist(submit: true);
                              }
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(step < 2 ? '次へ' : '申請する'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void _position(LatLng p) => setState(() {
    lat = p.latitude;
    lng = p.longitude;
    fields['lat']!.text = lat.toStringAsFixed(6);
    fields['lng']!.text = lng.toStringAsFixed(6);
  });

  Widget _preview() {
    VenuePolicy p;
    try {
      p = policy();
    } catch (_) {
      return const InfoBox('座標の入力を見直してください。', warning: true);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBox('公開前に施設責任者の確認が必要です。確認済みの責任者から招待された担当者も申請できます。'),
        TextButton.icon(
          onPressed: busy
              ? null
              : () async {
                  await persist(silent: true);
                  if (!mounted || saved == null || dirty || busy) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => FacilityAccessPage(
                        api: widget.api,
                        venueId: saved!.id,
                      ),
                    ),
                  );
                },
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('施設の管理権限を確認・担当者を招待'),
        ),
        PolicyCard(policy: p, forSubmitPreview: true),
        const SizedBox(height: 20),
        if (visibility == 'public')
          const InfoBox('施設情報と選択した確認項目が、承認後に一般利用者のアプリへ配信されます。', warning: true),
        if (visibility == 'public') const SizedBox(height: 12),
        CheckboxListTile(
          value: ack,
          onChanged: busy ? null : (v) => setState(() => ack = v ?? false),
          title: const Text('施設情報と指摘する項目を確認しました'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const Text('承認までは現在の公開版が維持されます。'),
      ],
    );
  }
}
