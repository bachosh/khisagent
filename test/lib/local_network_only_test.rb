require "test_helper"
require "local_network_only"

class LocalNetworkOnlyTest < ActiveSupport::TestCase
  setup do
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    networks = LocalNetworkOnly::LOOPBACK + [ IPAddr.new("192.168.50.0/24") ]
    @middleware = LocalNetworkOnly.new(app, networks: networks)
  end

  def status_for(ip, headers = {})
    @middleware.call(Rack::MockRequest.env_for("/", { "REMOTE_ADDR" => ip }.merge(headers))).first
  end

  test "allows this computer and the Wi-Fi subnet" do
    assert_equal 200, status_for("127.0.0.1")
    assert_equal 200, status_for("::1")
    assert_equal 200, status_for("192.168.50.23")
    assert_equal 200, status_for("::ffff:192.168.50.23")
  end

  test "refuses other networks, even with a spoofed forwarding header" do
    assert_equal 403, status_for("192.168.51.10")
    assert_equal 403, status_for("10.8.0.2")
    assert_equal 403, status_for("8.8.8.8", "HTTP_X_FORWARDED_FOR" => "192.168.50.5")
    assert_equal 403, status_for("garbage")
  end
end
