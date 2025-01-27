# encoding: utf-8

# Copyright 2014-2020 Aerospike, Inc.
#
# Portions may be licensed to Aerospike, Inc. under one or more contributor
# license agreements.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

require 'aerospike/aerospike_exception'

module Aerospike
  # Polymorphic value classes used to efficiently serialize objects into the wire protocol.
  class Value #:nodoc:

    def self.of(value, allow_64bits = false)
      case value
      when Integer
        if !allow_64bits
          if value.bit_length < 64
            res = IntegerValue.new(value)
          else
            # big nums > 2**63 are not supported
            raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::TYPE_NOT_SUPPORTED, "Value type #{value.class} not supported with more than 64 bits.")
          end
        else
          # used in bitwise operations
          if value.bit_length <= 64
            res = IntegerValue.new(value)
          else
            # nums with more than 64 bits are not supported
            raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::TYPE_NOT_SUPPORTED, "Value type #{value.class} not supported with more than 64 bits.")
          end
        end
      when Float
        res = FloatValue.new(value)
      when String
        res = StringValue.new(value)
      when Symbol
        res = StringValue.new(value.to_s)
      when Value
        res = value
      when Hash
        res = MapValue.new(value)
      when Array
        res = ListValue.new(value)
      when GeoJSON
        res = GeoJSONValue.new(value)
      when nil
        res = NULL
      when TrueClass, FalseClass
        res = BoolValue.new(value)
      else
        # throw an exception for anything that is not supported.
        raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::TYPE_NOT_SUPPORTED, "Value type #{value.class} not supported.")
      end

      res
    end

    def self.validate_hash_key(value)
      case value
      when Integer
        if value.bit_length >= 64
          raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::TYPE_NOT_SUPPORTED, "Value type #{value.class} not supported as hash key.")
        end
      when Float
      when String
      when Symbol
      when nil
      else
        # throw an exception for anything that is not supported.
        raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::TYPE_NOT_SUPPORTED, "Value type #{value.class} not supported as hash key.")
      end
    end

  end # Value

  # Empty value.
  class NullValue < Value #:nodoc:

    def initialize
      self
    end

    def type
      Aerospike::ParticleType::NULL
    end

    def get
      nil
    end

    def to_s
      ''
    end

    def estimate_size
      0
    end

    def write(buffer, offset)
      0
    end

    def pack(packer)
      packer.write_nil
    end

    def to_bytes
      ''
    end
  end

  NULL = NullValue.new.freeze


  # Infinity value.
  class InfinityValue < Value #:nodoc:
    def initialize
      self
    end

    def type
      raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::PARAMETER_ERROR, "Invalid particle type: INF")
    end

    def get
      nil
    end

    def to_s
      "INF"
    end

    def estimate_size
      0
    end

    def write(buffer, offset)
      0
    end

    def pack(packer)
      packer.pack(self)
    end

    def to_bytes
      ''
    end

    def to_msgpack_ext
      1.chr
    end
  end

  INFINITY = Value::INFINITY = InfinityValue.new.freeze

  # Wildcard value.
  class WildcardValue < Value #:nodoc:
    def initialize
      self
    end

    def type
      raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::PARAMETER_ERROR, "Invalid particle type: wildcard")
    end

    def get
      nil
    end

    def to_s
      "*"
    end

    def estimate_size
      0
    end

    def write(buffer, offset)
      0
    end

    def pack(packer)
      packer.pack(self)
    end

    def to_bytes
      ''
    end

    def to_msgpack_ext
      0.chr
    end
  end

  WILDCARD = Value::WILDCARD = WildcardValue.new.freeze

  # Byte array value.
  class BytesValue < Value #:nodoc:

    def initialize(value)
      @bytes = value
      @bytes.force_encoding('binary')

      self
    end

    def type
      Aerospike::ParticleType::BLOB
    end

    def get
      @bytes
    end

    def to_s
      @bytes.to_s
    end

    def to_bytes
      @bytes
    end

    def estimate_size
      @bytes.bytesize
    end

    def write(buffer, offset)
      buffer.write_binary(@bytes, offset)
    end

    def pack(packer)
      packer.write(Aerospike::ParticleType::BLOB.chr + @bytes)
    end

  end # BytesValue

  #######################################

  # value string.
  class StringValue < Value #:nodoc:

    def initialize(val)
      @value = val || ''
      self
    end

    def estimate_size
      @value.bytesize
    end

    def write(buffer, offset)
      bytes = @value.encode(Aerospike.encoding).force_encoding(Encoding::BINARY)
      buffer.write_binary(bytes, offset)
    end

    def pack(packer)
      packer.write(Aerospike::ParticleType::STRING.chr + @value)
    end

    def type
      Aerospike::ParticleType::STRING
    end

    def get
      @value
    end

    def to_bytes
      @value
    end

    def to_s
      @value
    end

    def to_sym
      @value.to_sym
    end

  end # StringValue

  #######################################

  # Integer value.
  class IntegerValue < Value #:nodoc:

    def initialize(val)
      @value = val || 0
      self
    end

    def estimate_size
      8
    end

    def write(buffer, offset)
      buffer.write_int64(@value, offset)
      8
    end

    def pack(packer)
      packer.write(@value)
    end

    def type
      Aerospike::ParticleType::INTEGER
    end

    def get
      @value
    end

    def to_bytes
      # Convert integer to big endian unsigned 64 bits.
      # @see http://ruby-doc.org/core-2.3.0/Array.html#method-i-pack
      [@value].pack('Q>')
    end

    def to_s
      @value.to_s
    end

  end # IntegerValue

  #######################################

  # Float value.
  class FloatValue < Value #:nodoc:

    def initialize(val)
      @value = val || 0.0
      self
    end

    def estimate_size
      8
    end

    def write(buffer, offset)
      buffer.write_double(@value, offset)
      8
    end

    def pack(packer)
      packer.write(@value)
    end

    def type
      Aerospike::ParticleType::DOUBLE
    end

    def get
      @value
    end

    def to_bytes
      [@value].pack('G')
    end

    def to_s
      @value.to_s
    end

  end # FloatValue

  #######################################

  # List value.
  # Supported by Aerospike 3 servers only.
  class ListValue < Value #:nodoc:

    def initialize(list)
      @list = list || []
    end

    def estimate_size
      bytes.bytesize
    end

    def write(buffer, offset)
      buffer.write_binary(bytes, offset)
      bytes.bytesize
    end

    def pack(packer)
      packer.write_array_header(@list.length)
      for val in @list
        Value.of(val).pack(packer)
      end
    end

    def type
      Aerospike::ParticleType::LIST
    end

    def get
      @list
    end

    def to_bytes
      bytes
    end

    def to_s
      @list.map{|v| v.to_s}.to_s
    end

    private

    def bytes
      return @bytes if @bytes

      Packer.use do |packer|
        pack(packer)
        @bytes = packer.bytes
      end

      @bytes
    end

  end

  # #######################################/

  # Map value.
  # Supported by Aerospike 3 servers only.
  class MapValue < Value #:nodoc:

    def initialize(vmap)
      @vmap = vmap || {}
    end

    def estimate_size
      bytes.bytesize
    end

    def write(buffer, offset)
      buffer.write_binary(bytes, offset)
      bytes.bytesize
    end

    def pack(packer)
      packer.write_map_header(@vmap.length)
      for key, val in @vmap
        Value.validate_hash_key(key)

        Value.of(key).pack(packer)
        Value.of(val).pack(packer)
      end
    end

    def type
      Aerospike::ParticleType::MAP
    end

    def get
      @vmap
    end

    def to_bytes
      bytes
    end

    def to_s
      @vmap.map{|k, v| "#{k.to_s} => #{v.to_s}" }.to_s
    end

    private

    def bytes
      return @bytes if @bytes

      Packer.use do |packer|
        pack(packer)
        @bytes = packer.bytes
      end

      @bytes
    end

  end

  # #######################################/

  # GeoJSON value.
  # Supported by Aerospike server version 3.7 and later.
  class GeoJSONValue < Value #:nodoc:

    def initialize(json)
      @json = json
      @bytes = json.to_json
      self
    end

    def estimate_size
      # flags + ncells + jsonstr
      1 + 2 + @bytes.bytesize
    end

    def write(buffer, offset)
      buffer.write_byte(0, offset) # flags
      buffer.write_uint16(0, offset + 1) # ncells
      return 1 + 2 + buffer.write_binary(@bytes, offset + 3) # JSON string
    end

    def pack(packer)
      packer.write(Aerospike::ParticleType::GEOJSON.chr + @bytes)
    end

    def type
      Aerospike::ParticleType::GEOJSON
    end

    def get
      @json
    end

    def to_bytes
      @bytes
    end

    def to_s
      @json
    end

  end

  # #######################################/

  # HLLValue value. Encapsulates a HyperLogLog value.
  # Supported by Aerospike server version 4.9 and later.
  class HLLValue < Value #:nodoc:

    def initialize(value)
      @bytes = value
      @bytes.force_encoding('binary')

      self
    end

    def type
      Aerospike::ParticleType::HLL
    end

    def get
      self
    end

    def to_s
      @bytes.to_s
    end

    def to_bytes
      @bytes
    end

    def estimate_size
      @bytes.bytesize
    end

    def write(buffer, offset)
      buffer.write_binary(@bytes, offset)
    end

    def pack(packer)
      packer.write(Aerospike::ParticleType::BLOB.chr + @bytes)
    end

  end

  #######################################

  def self.encoding
    @_encoding ||= Encoding::UTF_8
  end

  def self.encoding=(encoding)
    @_encoding = encoding
  end

  protected

  def self.bytes_to_particle(type, buf, offset, length) # :nodoc:

    case type
    when Aerospike::ParticleType::STRING
      bytes = buf.read(offset, length)
      bytes.force_encoding(Aerospike.encoding)

    when Aerospike::ParticleType::INTEGER
      buf.read_int64(offset)

    when Aerospike::ParticleType::DOUBLE
      buf.read_double(offset)

    when Aerospike::ParticleType::BOOL
      buf.read_bool(offset, length)

    when Aerospike::ParticleType::BLOB
      buf.read(offset,length)

    when Aerospike::ParticleType::LIST
      Unpacker.use do |unpacker|
        data = buf.read(offset, length)
        unpacker.unpack(data)
      end

    when Aerospike::ParticleType::MAP
      Unpacker.use do |unpacker|
        data = buf.read(offset, length)
        unpacker.unpack(data)
      end

    when Aerospike::ParticleType::GEOJSON
      # ignore the flags for now
      ncells = buf.read_int16(offset + 1)
      hdrsz = 1 + 2 + (ncells * 8)
      Aerospike::GeoJSON.new(buf.read(offset + hdrsz, length - hdrsz))

    when Aerospike::ParticleType::HLL
      bytes = buf.read(offset,length)
      Aerospike::HLLValue.new(bytes)

    else
      nil
    end
  end

  def self.bytes_to_key_value(type, buf, offset, len) # :nodoc:

    case type
    when Aerospike::ParticleType::STRING
      StringValue.new(buf.read(offset, len))

    when Aerospike::ParticleType::INTEGER
      IntegerValue.new(buf.read_var_int64(offset, len))

    when Aerospike::ParticleType::BLOB
      BytesValue.new(buf.read(offset,len))

    else
      nil
    end
  end

  private

  #######################################

  # Boolean value.
  # Supported by Aerospike server 5.6+ only.
  class BoolValue < Value #:nodoc:

    def initialize(val)
      @value = val || false
      self
    end

    def estimate_size
      1
    end

    def write(buffer, offset)
      val = @value ? 1 : 0
      buffer.write_byte(val.ord, offset)
      1
    end

    def pack(packer)
      packer.write(@value)
    end

    def type
      Aerospike::ParticleType::BOOL
    end

    def get
      @value
    end

    def to_bytes
      @value.ord
    end

    def to_s
      @value.to_s
    end

  end # BoolValue
end # module
