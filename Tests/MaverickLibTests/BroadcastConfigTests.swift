import MaverickModels
import XCTest
import Yams

final class BroadcastConfigTests: XCTestCase {
    func testMultilineBroadcastConfigurationDecodes() throws {
        let yaml = """
        metaDescription: Test
        title: Test
        description: Test
        url: https://example.com
        batchSize: 5
        feedSize: 20
        broadcasting:
          enabled: false
          autoPublishAfter: 2026-09-01T00:00:00Z
          admin:
            usernameSecret: admin-user
            passwordSecret: admin-password
          state:
            type: r2
            encryptionKeySecret: encryption
            r2:
              bucket: state
              keyPrefix: example.com
              accountIDSecret: account
              accessKeyIDSecret: access
              secretAccessKeySecret: secret
          providers:
            - id: bluesky
              type: bluesky
              account: example.bsky.social
              credentialSecret: app-password
              postTemplate: |-
                {{title}}

                {{description}}

                {{url}}
        """

        let site = try YAMLDecoder().decode(SiteConfig.self, from: yaml)

        XCTAssertEqual(site.broadcasting?.providers.first?.postTemplate,
                       "{{title}}\n\n{{description}}\n\n{{url}}")
        XCTAssertEqual(site.broadcasting?.autoPublishAfter, ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z"))
        XCTAssertEqual(site.broadcasting?.state.r2?.bucket, "state")
    }
}
