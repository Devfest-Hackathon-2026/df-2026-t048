import 'package:postcheck_rules/postcheck_rules.dart';
import 'package:test/test.dart';
void main(){
 test('release time and expiry respect exact UTC boundary',(){final release=DateTime.utc(2026,11,19,15);final p=VenuePolicy(name:'test',words:['fiction'],releaseAt:release,validUntil:release.add(const Duration(days:1)));expect(p.activeWords(release.subtract(const Duration(microseconds:1))),['fiction']);expect(p.activeWords(release),isEmpty);expect(p.validAt(release.add(const Duration(days:1))),false);expect(VenuePolicy.fromJson(p.toJson()).releaseAt,release);});
 test('QR only accepts controlled venue identifiers',(){expect(venueIdFromQR('postcheck://venue/demo-exhibition'),'demo-exhibition');for(final url in ['https://evil.example','postcheck://venue/a/b','postcheck://venue/a?admin=1','postcheck://venue/a%2Fb','postcheck://venue/']){expect(venueIdFromQR(url),isNull);}});
 test('unknown permission never becomes allowed',(){expect(RulePermission.parse('new-value'),RulePermission.unknown);});
}
