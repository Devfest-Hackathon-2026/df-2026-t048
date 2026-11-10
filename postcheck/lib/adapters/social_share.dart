import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import '../domain/social_share.dart';
import 'share_export.dart';
import 'story_image.dart';

typedef OpenShareUrl = Future<bool> Function(Uri);
typedef RenderStory = Future<Uint8List> Function(ExportArtifact, StoryLayout);

final class SocialShareAdapter implements SocialExportPort {
  SocialShareAdapter({
    ExportPort? exporter,
    OpenShareUrl? openUrl,
    Future<void> Function(String)? copyText,
    RenderStory? renderStory,
    Future<bool> Function(Uint8List, String)? openInstagramStory,
    this.instagramAppId = const String.fromEnvironment('INSTAGRAM_APP_ID'),
  }) : exporter = exporter ?? ShareExportAdapter(),
       openUrl =
           openUrl ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication)),
       copyText =
           copyText ?? ((text) => Clipboard.setData(ClipboardData(text: text))),
       renderStory = renderStory ?? const StoryImageComposer().compose,
       openInstagramStory = openInstagramStory ?? _openStory;
  final ExportPort exporter;
  final OpenShareUrl openUrl;
  final Future<void> Function(String) copyText;
  final RenderStory renderStory;
  final Future<bool> Function(Uint8List, String) openInstagramStory;
  final String instagramAppId;

  static Future<bool> _openStory(Uint8List png, String appId) async {
    try {
      return await const MethodChannel('postcheck/privacy').invokeMethod<bool>(
            'shareInstagramStory',
            {'image': png, 'appId': appId},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Uint8List> previewStory(ExportArtifact artifact, StoryLayout layout) =>
      renderStory(artifact, layout);

  @override
  Future<ShareHandoff> shareTo(
    ExportArtifact artifact,
    ShareDestination destination, {
    StoryLayout storyLayout = StoryLayout.card,
    String? officialLineId,
    double? anchorX,
    double? anchorY,
  }) async {
    if (destination == ShareDestination.lineOfficial) {
      final id = officialLineId?.trim() ?? '';
      if (!RegExp(r'^@[A-Za-z0-9._-]{1,100}$').hasMatch(id)) {
        throw InvalidLineAccount();
      }
      final url = Uri.parse(
        'https://line.me/R/oaMessage/${Uri.encodeComponent(id)}/?${Uri.encodeComponent(artifact.caption)}',
      );
      if (url.toString().length > 7000) {
        throw InvalidLineAccount();
      }
      if (!await openUrl(url)) throw InvalidLineAccount();
      return ShareHandoff.officialLineText;
    }
    if (destination == ShareDestination.instagramStory) {
      final png = await renderStory(artifact, storyLayout);
      if (instagramAppId.isNotEmpty &&
          await openInstagramStory(png, instagramAppId)) {
        return ShareHandoff.instagramStory;
      }
      if (artifact.caption.isNotEmpty) await copyText(artifact.caption);
      await exporter.share(
        ExportArtifact(caption: '', imageBytes: png),
        anchorX: anchorX,
        anchorY: anchorY,
      );
      return ShareHandoff.storySheet;
    }
    // URL intents accept text/links, not a local image attachment. For photos,
    // use the OS sheet and let the person select the requested social app.
    if (artifact.imageBytes == null && artifact.caption.isNotEmpty) {
      final url = switch (destination) {
        ShareDestination.x => Uri.https('x.com', '/intent/tweet', {
          'text': artifact.caption,
        }),
        ShareDestination.line => Uri.https('line.me', '/R/share', {
          'text': artifact.caption,
        }),
        ShareDestination.threads => Uri.https(
          'www.threads.com',
          '/intent/post',
          {'text': artifact.caption},
        ),
        _ => null,
      };
      if (url != null && url.toString().length <= 7000) {
        try {
          if (await openUrl(url)) return ShareHandoff.composer;
        } on PlatformException {
          /* Fall back to local system sharing. */
        }
      }
    }
    final copy =
        destination != ShareDestination.other && artifact.caption.isNotEmpty;
    if (copy) await copyText(artifact.caption);
    await exporter.share(artifact, anchorX: anchorX, anchorY: anchorY);
    return copy ? ShareHandoff.captionCopiedSheet : ShareHandoff.sheet;
  }
}
