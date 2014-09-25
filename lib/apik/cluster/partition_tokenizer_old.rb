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

require 'base64'

module Apik

  protected

  class PartitionTokenizerOld

    def initialize(conn)
      # Use low-level info methods and parse byte array directly for maximum performance.
      # Send format:    replicas-master\n
      # Receive format: replicas-master\t<ns1>:<base 64 encoded bitmap>;<ns2>:<base 64 encoded bitmap>... \n
      infoMap = Info.request(conn, REPLICAS_NAME)

      info = infoMap[REPLICAS_NAME]

      @length = info ? info.length : 0

      if !info || @length == 0
        raise Apik::Exceptions::Connection.new("#{replicasName} is empty")
      end

      @buffer = info
      @offset = 0

      self
    end

    def update_partition(nmap, node)
      amap = nil
      copied = false

      while partition = getNext
        exists = nmap[partition.namespace]

        if !exists
          if !copied
            # Make shallow copy of map.
            amap = {}
            nmap.each {|k, v| amap[k] = v}
            copied = true
          end

          nodeArray = Atomic.new(Array.new(Apik::Node::PARTITIONS))
          amap[partition.namespace] = nodeArray
        end

        Apik.logger.debug("#{partition.to_s}, #{node.name}")
        nodeArray.update{|v| v[partition.Partition_id] = node; v }
      end

      copied ? amap : nil
    end

    private

    def getNext
      beginning = @offset

      while @offset < @length
        if @buffer[@offset] == ":"
          # Parse namespace.
          namespace = @buffer[beginning...@offset].strip!

          if namespace.length <= 0 || namespace.length >= 32
            response = getTruncatedResponse
            raise Apik::Exceptions::Parse.new(
              "Invalid partition namespace #{namespace}. Response=#{response}"
            )
          end

          @offset+=1
          beginning = @offset

          # Parse partition id.
          while @offset < @length
            b = @buffer[@offset]

            break if b == ";" || b == "\n"
            @offset+=1
          end

          if @offset == beginning
            response = getTruncatedResponse
            raise Apik::Exceptions::Parse.new(
              "Empty partition id for namespace #{namespace}. Response=#{response}"
            )
          end

          partitionId = @buffer[beginning...@offset].to_i
          if partitionId < 0 || partitionId >= Apik::Node::PARTITIONS
            response = getTruncatedResponse
            partitionString = @buffer[beginning...@offset]
            aise Apik::Exceptions::Parse.new(
              "Invalid partition id #{partitionString} for namespace #{namespace}. Response=#{response}"
            )
          end

          @offset+=1
          beginning = @offset

          return Partition.new(namespace, partitionId)
        end
        @offset+=1
      end
      return nil
    end


    def getTruncatedResponse
      max = @length
      @length = max if @length > 200
      @buffer[0...max]
    end


  end # class

end # module