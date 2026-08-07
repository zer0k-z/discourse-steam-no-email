# frozen_string_literal: true

# name: discourse-steam-no-email
# about: Gives Steam logins a synthetic placeholder email so signup never asks for a real address
# version: 0.0.1
# authors: zer0.k

register_asset "stylesheets/steam-no-email.scss"

after_initialize do
  if !defined?(::Auth::SteamAuthenticator)
    raise "discourse-steam-no-email requires the discourse-steam-login plugin to be installed and loaded first"
  end

  module ::DiscourseSteamNoEmail
    SYNTHETIC_EMAIL_DOMAIN = "steam.invalid"

    def self.synthetic_email_for(steamid)
      "steam_#{steamid}@#{SYNTHETIC_EMAIL_DOMAIN}"
    end

    def self.synthetic_email?(email)
      email.to_s.end_with?("@#{SYNTHETIC_EMAIL_DOMAIN}")
    end

    module SyntheticEmail
      # Synthetic emails are not real, so they cannot be used to match existing accounts.
      def match_by_email
        false
      end
      # Prevent the authenticator from trying to verify a placeholder address.
      def primary_email_verified?(auth_token)
        true
      end
      # Set synthetic email on the account so signup can complete without a real address.
      def after_authenticate(auth_token, existing_account: nil)
        result = super
        result.email = ::DiscourseSteamNoEmail.synthetic_email_for(auth_token[:uid])
        result.email_valid = true
        result.skip_email_validation = true
        result
      end
    end
  end
  # Apply the synthetic email behavior to the authenticator so it is used for all Steam logins.
  ::Auth::SteamAuthenticator.prepend(::DiscourseSteamNoEmail::SyntheticEmail)

  module ::DiscourseSteamNoEmail
    module AssignPlaceholderEmail
      # Intercept ::UsersController#create to assign a synthetic email if the user left the field blank.
      # This allows signup to complete without a real address.
      def create
        # Key type depends on how far the session has been round-tripped.
        authentication = server_session[:authentication]
        supplied = authentication.is_a?(Hash) && (authentication["email"] || authentication[:email])

        if ::DiscourseSteamNoEmail.synthetic_email?(supplied)
          if params[:email].blank?
            params[:email] = supplied
          elsif !::DiscourseSteamNoEmail.synthetic_email?(params[:email])
            # The user typed an address of their own. Steam vouched for their
            # identity but not for that address so core will reject it.
            # We need to downgrade the authentication so core will require them to verify it.
            downgraded = authentication.with_indifferent_access
            downgraded[:email_valid] = false
            downgraded[:skip_email_validation] = false
            server_session[:authentication] = downgraded.to_h
          end
        end

        super
      end
    end
  end

  ::UsersController.prepend(::DiscourseSteamNoEmail::AssignPlaceholderEmail)

  module ::DiscourseSteamNoEmail
    module ActivationEmailGuard
      def update_activation_email
        if ::DiscourseSteamNoEmail.synthetic_email?(params[:email])
          return(render_json_error(I18n.t("steam_no_email.reserved_address"), status: 422))
        end

        super
      end
    end
  end

  ::UsersController.prepend(::DiscourseSteamNoEmail::ActivationEmailGuard)

  module ::DiscourseSteamNoEmail
    module ResendActivationGuard
      def send_activation_email
        user_key = session[::SessionController::ACTIVATE_USER_KEY]
        user = ::User.find_by(id: user_key.to_i) if user_key.present?

        if user && ::DiscourseSteamNoEmail.synthetic_email?(user.email)
          return(render_json_error(I18n.t("steam_no_email.no_address_to_activate"), status: 422))
        end

        super
      end
    end
  end

  ::UsersController.prepend(::DiscourseSteamNoEmail::ResendActivationGuard)

  module ::DiscourseSteamNoEmail
    module SignupDestination
      def to_client_hash
        hash = super

        if hash.is_a?(Hash) && !user &&
             hash[:destination_url].to_s.chomp("/") == ::Discourse.base_path("/").chomp("/")
          hash = hash.except(:destination_url)
        end

        hash
      end
    end
  end

  ::Auth::Result.prepend(::DiscourseSteamNoEmail::SignupDestination)

  module ::DiscourseSteamNoEmail
    module PlaceholderEmailChange
      # Allow users to change away from a synthetic email without needing to verify it first.
      def change_to(email, add: false)
        change_req = super
        # Skip for secondary emails and bail if the change request is nil.
        return change_req if add || change_req.blank?

        # If the change state is not authorizing the old email, we don't need to do anything special.
        if change_req.change_state != ::EmailChangeRequest.states[:authorizing_old]
          return change_req
        end

        # If the old email isn't a synthetic placeholder, we don't need to do anything special either.
        return change_req if !::DiscourseSteamNoEmail.synthetic_email?(change_req.old_email)

        # Send the confirmation email to the new address, see EmailUpdater#confirm.
        unreachable_token = change_req.old_email_token

        change_req.update!(
          change_state: ::EmailChangeRequest.states[:authorizing_new],
          old_email_token: nil,
          new_email_token:
            @user.email_tokens.create!(
              email: change_req.new_email,
              scope: ::EmailToken.scopes[:email_update],
            ),
        )
        unreachable_token&.destroy!

        send_email("confirm_new_email", change_req.new_email_token)

        change_req
      end
    end
  end

  ::EmailUpdater.prepend(::DiscourseSteamNoEmail::PlaceholderEmailChange)

  # Suppress the bootstrap and sends users to the login page since
  # signing in is already enough to claim the configured admin account.
  suppress_login_hint =
    lambda do
      SiteSetting.has_login_hint = false if SiteSetting.enable_steam_logins &&
        SiteSetting.has_login_hint
    end

  on(:site_setting_changed) do |name, _old_value, _new_value|
    suppress_login_hint.call if name == :enable_steam_logins
  end

  begin
    suppress_login_hint.call
  rescue ActiveRecord::ActiveRecordError
    # suppress_login_hint.call might be called before the database is ready.
    # rescue the error so the boot doesn't crash.
  end
end
