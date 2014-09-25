# Copyright 2012-2014 Aerospike, Inc.
#
# Portions may be licensed to Aerospike, Inc. under one or more contributor
# license agreements.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

module Apik

  protected

  class NodeValidator

    attr_reader :host, :aliases, :name, :useNewInfo

    def initialize(host, timeout)
      @useNewInfo = true
      @host = host

      set_aliases(host)
      set_address(timeout)

      self
    end

    def set_aliases(host)
      addresses = Resolv.getaddresses(host.name)
      aliases = []
      addresses.each do |addr|
        aliases << Host.new(addr, host.port)
      end

      @aliases = aliases

      Apik.logger.debug("Node Validator has #{aliases.length} nodes.")
    end

    def set_address(timeout)
      @aliases.each do |aliass|
        begin
          conn = Connection.new(aliass.name, aliass.port, 1)
          conn.set_timeout(timeout)

          infoMap= Info.request(conn, 'node', 'build')
          if nodeName = infoMap['node']
            @name = nodeName

            # Check new info protocol support for >= 2.6.6 build
            if buildVersion = infoMap['build']
              v1, v2, v3 = parse_version_string(buildVersion)
              @useNewInfo = v1.to_i > 2 || (v1.to_i == 2 && (v2.to_i > 6 || (v2.to_i == 6 && v3.to_i >= 6)))
            end
          end
        ensure
          conn.close
        end

      end
    end

    protected

    # parses a version string
    @@version_regexp = /(?<v1>\d+)\.(?<v2>\d+)\.(?<v3>\d+).*/

    def parse_version_string(version)
      if v = @@version_regexp.match(version)
        return v['v1'], v['v2'], v['v3']
      end

      raise Apik::Exceptions::Aerospike.new("Invalid build version string in Info: #{version}")
    end

  end # class

end #module