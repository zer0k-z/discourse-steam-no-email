import Component from "@glimmer/component";
import { getOwner } from "@ember/owner";
import { next } from "@ember/runloop";
import { i18n } from "discourse-i18n";
import { isPlaceholderEmail } from "discourse/plugins/discourse-steam-no-email/discourse/lib/placeholder-email";

// The signup form arrives pre-filled with the address the authenticator
// supplied, which the user never chose and would only find confusing. Emptying
// it presents the field as genuinely optional; the controller puts the supplied
// address back at submit time if it is still blank.
export default class SteamOptionalEmail extends Component {
  signupController = getOwner(this).lookup("controller:signup");

  constructor() {
    super(...arguments);

    // Deferred: the surrounding template reads accountEmail while this component
    // renders, and updating it in the same pass would be a backtracking render.
    next(() => {
      if (this.isDestroying || this.isDestroyed) {
        return;
      }

      if (isPlaceholderEmail(this.signupController.accountEmail)) {
        this.signupController.accountEmail = "";
      }
    });
  }

  get suppliedByProvider() {
    return isPlaceholderEmail(this.signupController.authOptions?.email);
  }

  <template>
    {{#if this.suppliedByProvider}}
      <span class="more-info steam-optional-email">
        {{i18n "steam_no_email.optional_hint"}}
      </span>
    {{/if}}
  </template>
}
