require "ipaddr"
require "socket"

# Rack middleware for testing on the local Wi-Fi: only this computer and devices on the same
# Wi-Fi subnet get through; everyone else gets 403. Enabled in development (config/environments/development.rb).
#
# The subnet is read from the Wi-Fi interface (wl*) at boot, e.g. 192.168.50.164/24 -> 192.168.50.0/24.
# Override with LAN_NETWORKS="192.168.1.0/24,10.0.0.0/24". Restart the server after changing networks.
#
# Uses REMOTE_ADDR (the TCP peer), not X-Forwarded-For, so the check cannot be bypassed with headers.
class LocalNetworkOnly
  LOOPBACK = [ IPAddr.new("127.0.0.0/8"), IPAddr.new("::1/128") ].freeze

  def self.wifi_interfaces
    Socket.getifaddrs.select { |ifa| ifa.name.start_with?("wl") && ifa.addr&.ipv4? && ifa.netmask }
  end

  # This computer's Wi-Fi addresses (for config.hosts)
  def self.wifi_addresses
    wifi_interfaces.map { |ifa| ifa.addr.ip_address }
  end

  def self.networks
    configured = ENV["LAN_NETWORKS"].to_s.split(",").map(&:strip).reject(&:empty?)
    lan = if configured.any?
      configured.map { |cidr| IPAddr.new(cidr) }
    else
      wifi_interfaces.map { |ifa| IPAddr.new("#{ifa.addr.ip_address}/#{ifa.netmask.ip_address}") }
    end
    LOOPBACK + lan
  end

  def initialize(app, networks: self.class.networks)
    @app = app
    @networks = networks
    Rails.logger&.info "[LocalNetworkOnly] allowed: #{networks.map { |n| "#{n}/#{n.prefix}" }.join(', ')}"
  end

  def call(env)
    return @app.call(env) if allowed?(env["REMOTE_ADDR"])

    [ 403, { "content-type" => "text/plain; charset=utf-8" },
      [ "403 Forbidden: KhisAgent is only available on the local Wi-Fi network.\n" ] ]
  end

  private

  def allowed?(remote_addr)
    ip = IPAddr.new(remote_addr.to_s)
    ip = ip.native if ip.ipv4_mapped?
    @networks.any? { |network| network.family == ip.family && network.include?(ip) }
  rescue IPAddr::Error
    false
  end
end
