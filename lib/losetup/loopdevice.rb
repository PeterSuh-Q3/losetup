# Implementation of losetup userspace utility in Ruby. Inspired by Sergey Kirillov's python implementation.
# Copyright (C) 2011 - 2015  Abhijith G

require 'bit-struct'

module Losetup
  class LoopDevice
    LOOPMAJOR = 7
    # ioctls
    LOOP_SET_FD = 0x4C00
    LOOP_CLR_FD = 0x4C01
    LOOP_SET_STATUS = 0x4C02
    LOOP_GET_STATUS = 0x4C03
    LOOP_SET_STATUS64 = 0x4C04
    LOOP_GET_STATUS64 = 0x4C05
    # flags
    LO_FLAGS_READ_ONLY  = 1
    LO_FLAGS_USE_AOPS   = 2
    LO_FLAGS_AUTOCLEAR  = 4

    class Status64 < BitStruct
      unsigned :lo_device,           64,   :endian => :little
      unsigned :lo_inode,            64,   :endian => :little
      unsigned :lo_rdevice,          64,   :endian => :little
      unsigned :lo_offset,           64,   :endian => :little
      unsigned :lo_sizelimit,        64,   :endian => :little
      unsigned :lo_number,           32,   :endian => :little
      unsigned :lo_encrypt_type,     32,   :endian => :little
      unsigned :lo_encrypt_key_size, 32,   :endian => :little
      unsigned :lo_flags,            32,   :endian => :little
      char     :lo_filename,         64*8, :endian => :little
      char     :lo_crypt_name,       64*8, :endian => :little
      char     :lo_encrypt_key,      32*8, :endian => :little
      char     :lo_init,             64*2, :endian => :little
    end

    def initialize(dev = nil)
      if dev.nil?
        @device = LoopDevice.get_unused_loop_device
        self
      else
        @device = dev
        if self.used?
          @status = status
          self
        end
      end
    end

    def status
      s = Status64.new
      File.open(@device, "r") do |dev|
        dev.ioctl(LOOP_GET_STATUS64, s)
      end
      @status = s
    end

    def mount(target, offset = 0, size_limit = 0)
      s = Status64.new
      s.lo_filename  = target
      s.lo_offset    = offset
      s.lo_sizelimit = size_limit
      File.open(@device) do |dev|
        dev.ioctl(LOOP_SET_STATUS64, s)
      end
      @status = s
      self
    end

    def create(target, next_loop = false)
      begin
        File.open(@device) do |dev|
          File.open(target) do |tf|
            dev.ioctl(LOOP_SET_FD, tf.fileno)
          end
        end
        mount(target)
      rescue Errno::EBUSY
        if next_loop
          if ld = LoopDevice.new
            ld.create(target)
          end
        else
          raise
        end
      end
    end

    def remove
      File.open(@device) do |dev|
        dev.ioctl(LOOP_CLR_FD)
      end
    end

    def used?
      begin
        status
        return true
      rescue Errno::ENXIO
        return false
      end
    end

    def self.find_all
      Dir.glob("/dev/loop*").sort - ["/dev/loop-control"]
    end

    def self.get_unused_loop_device
      loops = find_all
      return nil if loops.empty?
      loops.each do |dev|
        return dev unless LoopDevice.new(dev).used?
      end
    end

    def self.loop?(dev)
      stat = File.stat(dev)
      major = lambda { |x| (x >> 8) & 0xff }
      return (File.blockdev?(dev) and (major.call(stat.rdev) == LOOPMAJOR))
    end

    # Create getter methods
    def self.create_methods
      white_list = [ :encrypt_key_size, :init, :rdevice,
                     :flags, :offset, :device, :sizelimit, :filename,
                     :number, :crypt_name, :encrypt_type, :encrypt_key,
                     :inode]

      instance = LoopDevice.new
      white_list.reject! { |meth| instance.respond_to?(meth) }

      white_list.each do |method_name|
        define_method(method_name) do
          attr = "lo_" + method_name.to_s
          v = @status.send(attr)
          if v.is_a? String
            v.strip!
          else
            v
          end
        end
      end
    end

    # Create helper methods during load time
    self.create_methods

  end
end
