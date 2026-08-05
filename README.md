# discourse-steam-no-email

Lets a Discourse instance run with Steam as the only login method and no email address ever required at signup.

## Requirements

- [`discourse-steam-login`](https://meta.discourse.org/t/discourse-steam-login/18153) installed and loaded first. The plugin raises on boot if it isn't present.
- A Steam Web API key (`steam_web_api_key`) required by `discourse-steam-login` itself before Steam login can be enabled at all.

## Why this exists

Discourse can't run with *no* email on an account. This plugin adds a synthetic `steam_<steamid64>@steam.invalid` email unless the user chooses to add a real address at signup.

## Configuration

This plugin adds no settings of its own, only from core or `discourse-steam-login`:

| Setting | Value | Usage |
|---|---|---|
| `enable_steam_logins` | `true` | Turns Steam login on. |
| `steam_web_api_key` | your key | Required before `enable_steam_logins` can be turned on. |
| `enable_local_logins` | `false` | Removes password-based signup/login, making Steam the only path in. |

Leave `disable_emails` at its default (`"no"`).
## Bootstrapping the first admin

There's no email to type into the standard "create the first admin" installer flow, and no password to set Steam is the only way in. Use Discourse's existing developer-email mechanism instead:

1. Note your own SteamID64 (the long numeric ID, e.g. `76561198012345678`).
2. Set the `DISCOURSE_DEVELOPER_EMAILS` environment variable (or `developer_emails` in `config/discourse.conf`) to `steam_<your-steamid64>@steam.invalid`.
3. Log in once via Steam. Discourse promotes the matching account to admin automatically on that login (`make_developer_admin`), and grants it moderator status as the first admin (`bootstrap_first_admin`).
4. Remove the `developer_emails` entry once you're done.

## Note

- Invite-by-email is broken while Steam is the only login method: the invite page requires the authenticated account's email to match the invited address (`invites/show.js` `emailValidation`), but this plugin always supplies a synthetic one, so they never match and the signup form doesn't even render (`shouldDisplayForm`). Invite-by-link is unaffected and works normally.
- The admin user list and other staff-only views still show `@steam.invalid` addresses as-is — this is expected, not a bug, but staff should know what they're looking at.
- `allowed_email_domains` / `blocked_email_domains` interaction with the `steam.invalid` domain hasn't been tested.
