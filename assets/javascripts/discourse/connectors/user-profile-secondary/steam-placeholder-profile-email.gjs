import Component from "@glimmer/component";
import { isPlaceholderEmail } from "discourse/plugins/discourse-steam-no-email/discourse/lib/placeholder-email";

// Hide the synthetic email address on the user profile page.
export default class SteamPlaceholderProfileEmail extends Component {
  static shouldRender({ model }) {
    return isPlaceholderEmail(model?.email);
  }

  <template>
    <span class="steam-placeholder-profile-email"></span>
  </template>
}
