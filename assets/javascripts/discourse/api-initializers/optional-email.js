import EmberObject from "@ember/object";
import { isEmpty } from "@ember/utils";
import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";
import { isPlaceholderEmail } from "discourse/plugins/discourse-steam-no-email/discourse/lib/placeholder-email";

export default apiInitializer((api) => {
  api.modifyClass(
    "controller:signup",
    (SuperClass) =>
      class extends SuperClass {
        get suppliedPlaceholder() {
          const supplied = this.authOptions?.email;
          return isPlaceholderEmail(supplied) ? supplied : null;
        }

        // Field is locked whenever its value matches the address the provider supplied.
        // Here that address is a hidden placeholder that the user is invited to replace,
        // so matching it must not lock the field.
        get emailDisabled() {
          return this.suppliedPlaceholder ? false : super.emailDisabled;
        }

        get emailValidation() {
          if (!this.suppliedPlaceholder) {
            return super.emailValidation;
          }

          const typed = this.accountEmail;

          // Blank is a valid choice here: the server fills in the placeholder.
          if (isEmpty(typed)) {
            return EmberObject.create({ ok: true, reason: null });
          }

          // @steam.invalid is not a real domain.
          if (isPlaceholderEmail(typed)) {
            return EmberObject.create({
              failed: true,
              ok: false,
              element: document.querySelector("#new-account-email"),
              reason: i18n("steam_no_email.placeholder_not_allowed"),
            });
          }

          return super.emailValidation;
        }
      }
  );

  // The change-email form could prefill with the synthetic email.
  // That would be confusing, and the user might try to submit it, which would
  // fail validation. Clear the field if it has a placeholder value.
  api.modifyClass(
    "route:preferences.email",
    (SuperClass) =>
      class extends SuperClass {
        setupController(controller) {
          super.setupController(...arguments);

          if (isPlaceholderEmail(controller.newEmail)) {
            controller.setProperties({ oldEmail: "", newEmail: "" });
          }
        }
      }
  );
});
