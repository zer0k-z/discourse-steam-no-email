# frozen_string_literal: true

describe DiscourseSteamNoEmail::SyntheticEmail do
  let(:authenticator) { Auth::SteamAuthenticator.new }
  let(:steamid) { "76561198012345678" }
  let(:synthetic_email) { "steam_#{steamid}@steam.invalid" }

  let(:auth_hash) do
    OmniAuth::AuthHash.new(provider: "steam", uid: steamid, info: { nickname: "somegamer" })
  end

  before do
    # EnableSteamLoginsValidator refuses to enable the setting without a key.
    SiteSetting.steam_web_api_key = "0" * 32
    SiteSetting.enable_steam_logins = true
  end

  it "is prepended to the upstream authenticator" do
    expect(Auth::SteamAuthenticator.ancestors).to include(described_class)
  end

  describe "#after_authenticate" do
    it "assigns a deterministic synthetic email and skips email validation" do
      result = authenticator.after_authenticate(auth_hash)

      expect(result.email).to eq(synthetic_email)
      expect(result.email_valid).to eq(true)
      expect(result.skip_email_validation).to eq(true)
    end

    it "resolves to the same user on repeat logins by the same steamid" do
      user = Fabricate(:user)
      UserAssociatedAccount.create!(
        user: user,
        provider_name: "steam",
        provider_uid: steamid,
        last_used: 1.year.ago,
      )

      expect(authenticator.after_authenticate(auth_hash).user.id).to eq(user.id)
    end

    it "never matches an existing account by the synthetic email" do
      Fabricate(:user, email: synthetic_email, skip_email_validation: true)

      expect(authenticator.after_authenticate(auth_hash).user).to eq(nil)
    end
  end

  describe "account creation" do
    it "creates an active user with the synthetic email and no password" do
      result = authenticator.after_authenticate(auth_hash)
      user = User.new(username: "somegamer", email: result.email)

      UserAuthenticator.new(user, { authentication: result.session_data }).start
      user.save!

      expect(user).to be_active
      expect(user.email).to eq(synthetic_email)
      expect(user.password_required?).to eq(false)
    end
  end

  describe "installer hint" do
    it "is suppressed when Steam logins are enabled" do
      SiteSetting.enable_steam_logins = false
      SiteSetting.has_login_hint = true

      SiteSetting.enable_steam_logins = true

      expect(SiteSetting.has_login_hint).to eq(false)
    end
  end

  describe "outbound email" do
    it "skips mail to the synthetic address while emails are enabled site-wide" do
      expect(SiteSetting.disable_emails).to eq("no")
      user = Fabricate(:user, email: synthetic_email, skip_email_validation: true)
      message = Mail::Message.new(to: user.email, body: "hello", charset: "UTF-8")

      expect { Email::Sender.new(message, :digest, user).send }.to change {
        SkippedEmailLog.where(
          reason_type: SkippedEmailLog.reason_types[:sender_message_to_invalid],
        ).count
      }.by(1)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
