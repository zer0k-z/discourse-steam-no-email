# frozen_string_literal: true

# Mirrors discourse-steam-login's OpenID integration spec, but asserts the
# behaviour this plugin introduces: the callback yields a usable synthetic
# email instead of a blank one, so signup never has to ask for an address.
describe "Steam OpenID 2.0 with a synthetic email" do
  let(:web_api_key) { "abcdef11223344" }
  let(:steam_user_id) { "894923402340234" }
  let(:synthetic_email) { "steam_#{steam_user_id}@steam.invalid" }

  before do
    OpenID::Util.logger.level = 100
    SiteSetting.steam_web_api_key = web_api_key
    SiteSetting.enable_steam_logins = true

    cert = OpenSSL::X509::Certificate.new
    cert.add_extension(OpenSSL::X509::Extension.new("subjectAltName", "DNS:steamcommunity.com"))
    StubSocket::StubIO.any_instance.stubs(:peer_cert).returns(cert)

    discovery_xrds = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <xrds:XRDS xmlns:xrds="xri://$xrds" xmlns="xri://$xrd*($v*2.0)">
        <XRD>
          <Service priority="0">
            <Type>http://specs.openid.net/auth/2.0/signon</Type>
            <URI>https://steamcommunity.com/openid/login</URI>
          </Service>
        </XRD>
      </xrds:XRDS>
    XML

    stub_request(:get, "http://steamcommunity.com/openid").to_return(
      status: 200,
      body: discovery_xrds,
      headers: {
        "Content-Type" => "text/xml",
      },
    )
    stub_request(:get, "https://steamcommunity.com/openid/id/#{steam_user_id}").to_return(
      status: 200,
      body: discovery_xrds,
    )
    stub_request(:post, "https://steamcommunity.com/openid/login").to_return(
      status: 200,
      body: "ns:http://specs.openid.net/auth/2.0\nis_valid:true\n",
      headers: {
        "Content-Type" => "text/plain",
      },
    )
    stub_request(
      :get,
      "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=#{web_api_key}&steamids=#{steam_user_id}",
    ).with(headers: { "Host" => "api.steampowered.com" }).to_return(
      status: 200,
      body:
        JSON.dump(
          response: {
            players: [{ steamid: steam_user_id, personaname: "SteamyPlayer", profilestate: 1 }],
          },
        ),
    )
  end

  def complete_steam_callback
    post "/auth/steam"
    expect(response.status).to eq(303)

    # The OpenID nonce store rejects replays, so each example needs its own.
    nonce = "#{1.minute.ago.iso8601}#{SecureRandom.base64(21)}"

    post "/auth/steam/callback",
         params: {
           _method: "post",
           "openid.ns": "http://specs.openid.net/auth/2.0",
           "openid.mode": "id_res",
           "openid.op_endpoint": "https://steamcommunity.com/openid/login",
           "openid.claimed_id": "https://steamcommunity.com/openid/id/#{steam_user_id}",
           "openid.identity": "https://steamcommunity.com/openid/id/#{steam_user_id}",
           "openid.return_to": "http://test.localhost/auth/steam/callback?_method=post",
           "openid.response_nonce": nonce,
           "openid.assoc_handle": "1234567890",
           "openid.signed":
             "signed,op_endpoint,claimed_id,identity,return_to,response_nonce,assoc_handle",
           "openid.sig": "ZseI1sqVHGU/f5Ye7Tcn7T3QMIg=",
         }

    JSON.parse(cookies[:authentication_data]).deep_symbolize_keys!
  end

  context "when signing up after the callback" do
    before { UsersController.any_instance.stubs(:honeypot_or_challenge_fails?).returns(false) }

    it "assigns the placeholder when the form leaves the field blank" do
      complete_steam_callback

      post "/u.json", params: { username: "SteamyPlayer", email: "" }

      expect(response.parsed_body["success"]).to eq(true)
      user = User.find_by(username: "SteamyPlayer")
      expect(user.email).to eq(synthetic_email)
      expect(user).to be_active
    end

    it "accepts an address the user typed themselves" do
      complete_steam_callback

      post "/u.json", params: { username: "SteamyPlayer", email: "player@example.com" }

      expect(response.parsed_body["success"]).to eq(true)
      user = User.find_by(username: "SteamyPlayer")
      expect(user.email).to eq("player@example.com")
      # Steam vouched for the identity, not the address, so the account waits
      # on the activation email rather than starting out active.
      expect(user).not_to be_active
      expect(user.password_required?).to eq(false)
      expect(UserAssociatedAccount.exists?(provider_name: "steam", user_id: user.id)).to eq(true)
    end

    it "refuses a signup naming a steamid the request did not authenticate as" do
      complete_steam_callback

      foreign = "steam_76561190000000000@steam.invalid"
      post "/u.json", params: { username: "squatter", email: foreign }

      expect(response.parsed_body["success"]).to eq(false)
      expect(User.with_email(foreign).exists?).to eq(false)
      expect(User.where("id > 0")).to be_empty
    end
  end

  it "hands the signup flow a valid synthetic email instead of a blank one" do
    authentication_data = complete_steam_callback

    expect(authentication_data[:email]).to eq(synthetic_email)
    expect(authentication_data[:email_valid]).to eq(true)
    expect(authentication_data[:username]).to eq("SteamyPlayer")
  end
end
