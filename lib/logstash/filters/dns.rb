# DNS Filter
#
# This filter will resolve any IP addresses from a field of your choosing.
#

require "logstash/filters/base"
require "logstash/namespace"

# The DNS filter performs a lookup (either an A record/CNAME record lookup
# or a reverse lookup at the PTR record) on records specified under the
# "reverse" and "resolve" arrays.
#
# The config should look like this:
#
#     filter {
#       dns {
#         type => 'type'
#         reverse => [ "@source_host", "field_with_address" ]
#         resolve => [ "field_with_fqdn" ]
#         action => "replace"
#       }
#     }
#
# Caveats: at the moment, there's no way to tune the timeout with the 'resolv'
# core library.  It does seem to be fixed in here:
#
#   http://redmine.ruby-lang.org/issues/5100
#
# but isn't currently in JRuby.
class LogStash::Filters::DNS < LogStash::Filters::Base

  config_name "dns"
  plugin_status "unstable"

  # Reverse resolve one or more fields.
  config :reverse, :validate => :array

  # Forward resolve one or more fields.
  config :resolve, :validate => :array

  # Determine what action to do: append or replace the values in the fields
  # specified under "reverse" and "resolve."
  config :action, :validate => [ "append", "replace" ], :require => true

  public
  def register
    require "resolv"

    @ip_validator = Resolv::AddressRegex
  end # def register

  public
  def filter(event)
    return unless filter?(event)

    resolve(event) if @resolve
    reverse(event) if @reverse

    filter_matched(event)
  end

  private
  def resolve(event)
    @resolve.each do |field|
      is_array = false
      raw = event[field]
      if raw.is_a?(Array)
        is_array = true
        if raw.length > 1
          @logger.warn("DNS: skipping resolve, can't deal with multiple values", :field => field, :value => raw)
          return
        end
        raw = raw.first
      end

      begin
        address = Resolv.getaddress(raw)
      rescue Resolv::ResolvError
        @logger.debug("DNS: couldn't resolve the hostname.",
                      :field => field, :value => raw)
        return
      rescue Resolv::ResolvTimeout
        @logger.debug("DNS: timeout on resolving the hostname.",
                      :field => field, :value => raw)
        return
      rescue SocketError => e
        @logger.debug("DNS: Encountered SocketError.",
                      :field => field, :value => raw)
        return
      rescue NoMethodError => e
        # see JRUBY-5647
        @logger.debug("DNS: couldn't resolve the hostname.",
                      :field => field, :value => raw,
                      :extra => "NameError instead of ResolvError")
        return
      end

      if @action == "replace"
        if is_array
          event[field] = [address]
        else
          event[field] = address
        end
      else
        if !is_array
          event[field] = [event[field], address]
        else
          event[field] << address
        end
      end

    end
  end

  private
  def reverse(event)
    @reverse.each do |field|
      raw = event[field]
      is_array = false
      if raw.is_a?(Array)
          is_array = true
          if raw.length > 1
            @logger.warn("DNS: skipping reverse, can't deal with multiple values", :field => field, :value => raw)
            return
          end
          raw = raw.first
      end

      if ! @ip_validator.match(raw)
        @logger.debug("DNS: not an address",
                      :field => field, :value => event[field])
        return
      end
      begin
        hostname = Resolv.getname(raw)
      rescue Resolv::ResolvError
        @logger.debug("DNS: couldn't resolve the address.",
                      :field => field, :value => raw)
        return
      rescue Resolv::ResolvTimeout
        @logger.debug("DNS: timeout on resolving address.",
                      :field => field, :value => raw)
        return
      rescue SocketError => e
        @logger.debug("DNS: Encountered SocketError.",
                      :field => field, :value => raw)
        return
      end

      if @action == "replace"
        if is_array
          event[field] = [hostname]
        else
          event[field] = hostname
        end
      else
        if !is_array
          event[field] = [event[field], hostname]
        else
          event[field] << hostname
        end
      end
    end
  end
end # class LogStash::Filters::DNS
