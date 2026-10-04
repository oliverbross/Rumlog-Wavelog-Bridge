import Foundation
import Testing
@testable import BridgeCore

@Test func parsesObservedAppInfoShape() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <AppInfo>
      <Application>RUMlogNG</Application>
      <AppVersion>RUMlogNG 6.5.1</AppVersion>
      <StationName>Test Mac</StationName>
      <dbname>synthetic.rlog</dbname>
      <ShownDxcc></ShownDxcc>
      <HdgToDxcc>-1</HdgToDxcc>
      <CurrentBand>40m</CurrentBand>
    </AppInfo>
    """

    let message = try RumlogXMLParser().parse(Data(xml.utf8))
    #expect(message.kind == .appInfo)
    #expect(message["application"] == "RUMlogNG")
    #expect(message["appversion"] == "RUMlogNG 6.5.1")
    #expect(message["dbname"] == "synthetic.rlog")
    #expect(message["currentband"] == "40m")
}

@Test func parsesContactInfoAndBuildsStableIdentity() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <contactinfo>
      <app>RUMlogNG</app>
      <timestamp>2026-10-04 07:48:00</timestamp>
      <call>VK0TEST/P</call>
      <band>7,0</band>
      <txfreq>710000</txfreq>
      <mode>SSB</mode>
      <ID>0123456789abcdef0123456789abcdef</ID>
    </contactinfo>
    """

    let message = try RumlogXMLParser().parse(Data(xml.utf8))
    #expect(message.kind == .contactInfo)
    #expect(message.contactID == "0123456789abcdef0123456789abcdef")
    #expect(message.callsign == "VK0TEST/P")

    let identity = try #require(SemanticQSOIdentity(message: message))
    #expect(identity.call == "VK0TEST/P")
    #expect(identity.band == "7.0")
    #expect(identity.sha256.count == 64)
}

@Test func parsesReplaceIdentityHints() throws {
    let xml = """
    <contactreplace>
      <timestamp>2026-10-04 08:00:00</timestamp>
      <call>N0NEW</call>
      <oldtimestamp>2026-10-04 07:59:00</oldtimestamp>
      <oldcall>N0OLD</oldcall>
      <band>14.0</band>
      <mode>CW</mode>
      <ID>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</ID>
    </contactreplace>
    """

    let message = try RumlogXMLParser().parse(Data(xml.utf8))
    #expect(message.kind == .contactReplace)
    #expect(message.oldCallsign == "N0OLD")
    #expect(message.oldTimestamp == "2026-10-04 07:59:00")
}

@Test func parsesDelete() throws {
    let xml = """
    <contactdelete>
      <timestamp>2026-10-04 08:00:00</timestamp>
      <call>N0TEST</call>
      <band>14.0</band>
      <ID>bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</ID>
    </contactdelete>
    """

    let message = try RumlogXMLParser().parse(Data(xml.utf8))
    #expect(message.kind == .contactDelete)
    #expect(message.contactID == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
}

@Test func rejectsMalformedXML() {
    #expect(throws: RumlogXMLParserError.self) {
        try RumlogXMLParser().parse(Data("<contactinfo>".utf8))
    }
}
