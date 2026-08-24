# Post broadcasting

`MaverickBroadcast` publishes long-form posts to independently registered providers while keeping an encrypted, durable delivery ledger in Cloudflare R2. A feed rebuild, post edit, container restart, or template change does not resend a delivered URL.

## Safety model

The canonical post URL is the permanent source identifier. The first initialization records every existing URL as `observed` without sending. A later URL is automatically queued only when its publication date is on or after `autoPublishAfter`. Titleless posts marked `microblog: true` are recorded as `skipped` in v1; the Micro.blog feed ping is unrelated and can remain configured.

Each provider delivery moves through `observed`, `queued`, `sending`, `delivered`, `skipped`, `failed`, or `ambiguous`. Maverick commits `sending` to R2 before the provider request and commits the receipt afterward. An interrupted `sending` delivery becomes `ambiguous` on startup and requires an explicit admin action, preventing an automatic duplicate.

R2 is authoritative. `/app/Data/broadcast-state.json.enc` is only an encrypted cache and never authorizes a send. Startup with a missing R2 object pointer is `uninitialized`; startup with unreadable R2 state, a bad checksum, or the wrong encryption key fails closed while normal website serving continues.

## Local admin testing

Local development can use the encrypted `FileStateStore`; it implements the same revision, checksum, immutable-snapshot, pointer, and ambiguous-send behavior without Cloudflare. Maverick rejects `type: local` when running in the production environment.

If `_dev` has not been populated yet, run `mise run dev` once. Then start the broadcaster from the Maverick repository root:

```sh
mise run broadcast-dev
```

The setup task installs a development SiteConfig in `_dev`, creates ignored `.maverick-secrets` and `.maverick-data` directories, generates an admin password and encryption key, and prints the login information. Open `http://127.0.0.1:8080/_admin/broadcast` and initialize the observed-post baseline. The generated configuration keeps automatic broadcasting disabled and sets its publication boundary to 2100.

If port 8080 is occupied, choose another port for both the generated site URL and server:

```sh
MAVERICK_DEV_PORT=8081 mise run broadcast-dev
```

Provider credentials are deliberately absent. Previews still work with provider-specific limits, while connection tests report the missing credential. To test a real provider, add only its referenced secret file under `_dev/.maverick-secrets`. Manual Backfill and Rebroadcast actions can publish even while automatic broadcasting is disabled, so use test accounts before exercising those actions.

The generated local state configuration is:

```yaml
state:
  type: local
  path: _dev/.maverick-data/broadcast-state
  encryptionKeySecret: maverick-state-encryption-key
```

To repeat first-run initialization, stop Maverick and move or remove only `_dev/.maverick-data/broadcast-state`. Keeping that directory and restarting Maverick tests restoration without reposting.

## Configuration

```yaml
broadcasting:
  enabled: false
  autoPublishAfter: 2026-09-01T00:00:00Z
  admin:
    usernameSecret: maverick-admin-username
    passwordSecret: maverick-admin-password
    trustForwardedClientIP: false
  state:
    type: r2
    encryptionKeySecret: maverick-state-encryption-key
    r2:
      bucket: maverick-state
      keyPrefix: example.com
      accountIDSecret: cloudflare-r2-account-id
      accessKeyIDSecret: cloudflare-r2-access-key-id
      secretAccessKeySecret: cloudflare-r2-secret-access-key
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

The login limiter uses the direct peer IP by default and never includes its ephemeral port. Set `trustForwardedClientIP: true` only when Maverick is reachable exclusively through a trusted reverse proxy that replaces, rather than appends to, client-supplied forwarding headers.

## Cloudflare R2 setup

Cloudflare is not needed for `mise run broadcast-dev`. It is needed before a production rollout:

1. Create a private R2 bucket; no public URL, custom domain, CORS rule, or Worker is required.
2. Create an R2 API token with Object Read & Write permission restricted to that bucket.
3. Record the Cloudflare account ID, generated access-key ID, and generated secret access key as separate 1Password fields.
4. Generate a separate encryption key with `openssl rand -base64 32` and back it up in 1Password. Do not store this key in R2.
5. Configure the nested `r2` block shown above, provision the secret files, deploy with broadcasting disabled, and initialize the baseline from the production admin.

The access-key secret is displayed only when Cloudflare creates the token, so save it immediately. Losing either the R2 ledger or the separate encryption key intentionally makes broadcasting fail closed.

## Rollout

1. Deploy with `broadcasting.enabled: false` and provision all secrets.
2. Open `/_admin/broadcast` and initialize the observed-post baseline. This creates the first encrypted R2 snapshot without publishing.
3. Test each provider connection and complete LinkedIn authorization.
4. Preview representative posts. Use manual backfill only for intentional old-post publishing.
5. Disable Micro.blog cross-posting, set `broadcasting.enabled: true`, and deploy. Keep the Micro.blog feed ping if desired.

On a replacement server, mount the same R2 credentials and encryption key and start with automatic broadcasting disabled. The coordinator must load and verify `latest.json` and its referenced snapshot before it becomes ready. Check provider connections, reconnect LinkedIn if required, and only then enable automatic delivery. Copying `/app/Data` is optional.
