import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { isPlaceholderEmail } from "discourse/plugins/discourse-steam-no-email/discourse/lib/placeholder-email";

// Stands in for the account page's email row whenever the stored address is a placeholder.
export default class SteamPlaceholderEmail extends Component {
  static shouldRender({ email }) {
    return isPlaceholderEmail(email);
  }

  @service siteSettings;

  // Mirrors the first two gates of the server's `can_edit_email?`; the rest
  // concern viewing someone else's preferences, which staff always pass.
  get canAddEmail() {
    return (
      this.siteSettings.email_editable &&
      !this.siteSettings.auth_overrides_email
    );
  }

  <template>
    <div
      class="control-group steam-placeholder-email"
      data-setting-name="user-email"
    >
      <label class="control-label">{{i18n "user.email.title"}}</label>

      <div class="controls">
        {{#if this.canAddEmail}}
          <LinkTo
            @route="preferences.email"
            class="btn btn-default btn-small pad-left"
          >
            {{dIcon "plus"}}
            <span>{{i18n "steam_no_email.add_email"}}</span>
          </LinkTo>
        {{/if}}
      </div>

      <div class="instructions">
        {{i18n "steam_no_email.no_email_instructions"}}
      </div>
    </div>
  </template>
}
