# frozen_string_literal: true

describe EmailUpdater do
  fab!(:user) { Fabricate(:user, admin: true) }

  let(:new_email) { "player@example.com" }

  def placeholder!
    user.primary_email.update_column(:email, "steam_894923402340234@steam.invalid")
    user.reload
  end

  def change_to(address)
    updater = EmailUpdater.new(guardian: user.guardian, user: user)
    updater.change_to(address)
    updater
  end

  it "asks only for the new address to be confirmed" do
    placeholder!

    change_req = change_to(new_email).change_req

    expect(change_req.change_state).to eq(EmailChangeRequest.states[:authorizing_new])
    expect(change_req.old_email_token).to eq(nil)
    expect(change_req.new_email_token.email).to eq(new_email)
  end

  it "sends the confirmation to the new address, not the placeholder" do
    placeholder!

    change_to(new_email)

    job = Jobs::CriticalUserEmail.jobs.last["args"].first
    expect(job["type"]).to eq("confirm_new_email")
    expect(job["to_address"]).to eq(new_email)
  end

  it "replaces the primary address once the new one is confirmed" do
    placeholder!

    updater = change_to(new_email)
    expect(updater.confirm(updater.change_req.new_email_token.token)).to eq(:complete)

    expect(user.reload.email).to eq(new_email)
    expect(user.user_emails.count).to eq(1)
  end

  it "still confirms a real old address first" do
    user.primary_email.update_column(:email, "old@example.com")
    user.reload

    change_req = change_to(new_email).change_req

    expect(change_req.change_state).to eq(EmailChangeRequest.states[:authorizing_old])
    expect(change_req.old_email_token.email).to eq("old@example.com")
  end
end
