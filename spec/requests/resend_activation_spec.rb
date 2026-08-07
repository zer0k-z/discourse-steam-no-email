# frozen_string_literal: true

describe UsersController do
  before do
    UsersController.any_instance.stubs(:honeypot_value).returns(nil)
    UsersController.any_instance.stubs(:challenge_value).returns(nil)
  end

  # Signing up is what puts the id in the session, which is the only thing the
  # resend endpoint trusts.
  let(:signed_up_user) do
    post "/u.json",
         params: {
           username: "steamyplayer",
           password: "strongpassword",
           email: "player@example.com",
         }

    User.find_by(username: "steamyplayer")
  end

  describe "#send_activation_email" do
    it "refuses to report success for a placeholder address" do
      user = signed_up_user
      user.primary_email.update_column(:email, "steam_894923402340234@steam.invalid")

      expect {
        post "/u/action/send_activation_email.json", params: { username: user.username }
      }.not_to change { Jobs::CriticalUserEmail.jobs.size }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("steam_no_email.no_address_to_activate"),
      )
    end

    it "still sends to a real address" do
      user = signed_up_user

      expect_enqueued_with(
        job: :critical_user_email,
        args: {
          type: :signup,
          to_address: user.email,
        },
      ) { post "/u/action/send_activation_email.json", params: { username: user.username } }

      expect(response.status).to eq(200)
    end
  end

  describe "#update_activation_email" do
    it "refuses to hand out a steamid that is not the account's own" do
      user = signed_up_user
      victim = "steam_76561190000000000@steam.invalid"

      expect { put "/u/update-activation-email.json", params: { email: victim } }.not_to change {
        Jobs::CriticalUserEmail.jobs.size
      }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(I18n.t("steam_no_email.reserved_address"))
      expect(user.reload.email).to eq("player@example.com")
      expect(User.with_email(victim).exists?).to eq(false)
    end

    it "still accepts a real address" do
      user = signed_up_user

      put "/u/update-activation-email.json", params: { email: "elsewhere@example.com" }

      expect(response.status).to eq(200)
      expect(user.reload.email).to eq("elsewhere@example.com")
    end
  end
end
