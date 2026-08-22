# Post broadcasting

`MaverickBroadcast` publishes long-form posts to independently registered providers while keeping an encrypted, durable delivery ledger in Cloudflare R2. A feed rebuild, post edit, container restart, or template change does not resend a delivered URL.

## Safety model

The canonical post URL is the permanent source identifier. The first initialization records every existing URL as `observed` without sending. A later URL is automatically queued only when its publication date is on or after `autoPublishAfter`. Titleless posts marked `microblog: true` are recorded as `skipped` in v1; the Micro.blog feed ping is unrelated and can remain configured.

Each provider delivery moves through `observed`, `queued`, `sending`, `delivered`, `skipped`, `failed`, or `ambiguous`. Maverick commits `sending` to R2 before the provider request and commits the receipt afterward. An interrupted `sending` delivery becomes `ambiguous` on startup and requires an explicit admin action, preventing an automatic duplicate.

R2 is authoritative. `/app/Data/broadcast-state.json.enc` is only an encrypted cache and never authorizes a send. Startup with a missing R2 object pointer is `uninitialized`; startup with unreadable R2 state, a bad checksum, or the wrong encryption key fails closed while normal website serving continues.

## Configuration

```yaml
broadcasting:
  enabled: false
  autoPublishAfter: 2026-09-01T00:00:00Z
  admin:
    usernameSecret: maverick-admin-username
    passwordSecret: maverick-admin-password
  state:
    type: r2
    bucket: maverick-state
    keyPrefix: example.com
    accountIDSecret: cloudflare-r2-account-id
    accessKeyIDSecret: cloudflare-r2-access-key-id
    secretAccessKeySecret: cloudflare-r2-secret-access-key
    encryptionKeySecret: maverick-state-encryption-key
  providers:
    - id: bluesky
      type: bluesky
      account: example.bsky.social
      credentialSecret: bluesky-app-password
      linkPreview: true
      postTemplate: |-
        {{title}}

        {{description}}

        {{url}}
```

Use YAML `|-` blocks for multiline templates. Available substitutions are `title`, `description`, `excerpt`, `url`, `siteTitle`, and `tags`. `tags` renders as a space-separated list. Only substituted `description` and `excerpt` text is shortened to fit a provider limit. If the title, URL, and fixed template text cannot fit, delivery is held as failed for review.

TextBundle `info.json` can override broadcasting globally or per provider:

```json
{
  "io_taphouse_maverick_broadcast": {
    "skip": false,
    "providers": {
      "linkedin": {
        "skip": false,
        "template": "{{title}}\n\n{{description}}\n\n{{url}}"
      }
    }
  }
}
```

JSON metadata necessarily escapes newlines; the SiteConfig YAML templates do not.

## Secrets and authorization

Secret names resolve to files under `/run/secrets`. Keep that directory out of Git and mount it read-only.

- R2 needs account ID, bucket-scoped Object Read & Write access-key ID and secret, plus a separately backed-up 32-byte base64 encryption key.
- Bluesky uses the account handle and an app password. Maverick discovers its PDS and creates deterministic records with a URL facet and optional external card.
- Mastodon uses an instance URL and a token with `write:statuses`. Maverick reads instance limits and sends a stable `Idempotency-Key`.
- LinkedIn uses authorization-code OAuth with `openid profile w_member_social`. Configure its redirect URI as `https://SITE/_admin/broadcast/linkedin/callback`. The access token and member URN are stored only inside the encrypted R2 ledger. The admin page reports expiration and offers reconnect.

The broadcaster admin is at `/_admin/broadcast`. In production all `/_admin` routes require HTTPS, Basic authentication, rate limiting, and CSRF validation. The LinkedIn callback omits Basic authentication but requires a persisted, ten-minute, single-use OAuth state.

## Rollout

1. Deploy with `broadcasting.enabled: false` and provision all secrets.
2. Open `/_admin/broadcast` and initialize the observed-post baseline. This creates the first encrypted R2 snapshot without publishing.
3. Test each provider connection and complete LinkedIn authorization.
4. Preview representative posts. Use manual backfill only for intentional old-post publishing.
5. Disable Micro.blog cross-posting, set `broadcasting.enabled: true`, and deploy. Keep the Micro.blog feed ping if desired.

On a replacement server, mount the same R2 credentials and encryption key and start with automatic broadcasting disabled. The coordinator must load and verify `latest.json` and its referenced snapshot before it becomes ready. Check provider connections, reconnect LinkedIn if required, and only then enable automatic delivery. Copying `/app/Data` is optional.
