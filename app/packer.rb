#!/usr/bin/env ruby
require 'json'

module PorchParcel
  Parcel = Struct.new(:id, :width, :height)
  Placement = Struct.new(:parcel, :x, :y)
  module_function

  def validate!(data)
    raise ArgumentError, 'input must be an object' unless data.is_a?(Hash)
    sw, sh, parcels = data['shelf_width'], data['shelf_height'], data['parcels']
    integer = ->(v) { v.is_a?(Integer) && !v.is_a?(TrueClass) && !v.is_a?(FalseClass) }
    raise ArgumentError, 'shelf dimensions must be integers' unless integer.call(sw) && integer.call(sh)
    raise ArgumentError, 'shelf dimensions must be 1..40 by 1..20' unless sw.between?(1, 40) && sh.between?(1, 20)
    raise ArgumentError, 'parcels must be an array of at most 30 items' unless parcels.is_a?(Array) && parcels.length <= 30
    ids = []
    parcels.each do |item|
      raise ArgumentError, 'each parcel must be an object' unless item.is_a?(Hash)
      id, width, height = item['id'], item['width'], item['height']
      raise ArgumentError, 'parcel ids must be printable names up to 32 characters' unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,31}\z/)
      raise ArgumentError, 'parcel ids must be unique' if ids.include?(id)
      raise ArgumentError, 'parcel dimensions must be positive integers' unless integer.call(width) && integer.call(height) && width > 0 && height > 0
      raise ArgumentError, 'parcel exceeds shelf bounds' if width > sw || height > sh
      ids << id
    end
    true
  end

  def pack(data)
    validate!(data)
    shelf = Array.new(data['shelf_height']) { Array.new(data['shelf_width']) }
    placed = []; unplaced = []
    data['parcels'].each do |raw|
      parcel = Parcel.new(raw['id'], raw['width'], raw['height']); found = nil
      (0..(data['shelf_height'] - parcel.height)).each do |y|
        break if found
        (0..(data['shelf_width'] - parcel.width)).each do |x|
          cells = (y...(y + parcel.height)).flat_map { |row| (x...(x + parcel.width)).map { |col| shelf[row][col] } }
          if cells.all?(&:nil?)
            found = [x, y]; break
          end
        end
      end
      if found
        x, y = found
        (y...(y + parcel.height)).each { |row| (x...(x + parcel.width)).each { |col| shelf[row][col] = parcel.id } }
        placed << Placement.new(parcel, x, y)
      else
        unplaced << parcel.id
      end
    end
    { shelf_width: data['shelf_width'], shelf_height: data['shelf_height'], grid: shelf, placed: placed, unplaced: unplaced }
  end

  def render(result, output = $stdout)
    output.puts "PORCH PARCEL // #{result[:shelf_width]}x#{result[:shelf_height]} shelf"
    result[:grid].each { |row| output.puts row.map { |cell| cell ? '#' : '.' }.join }
    output.puts "Placed: #{result[:placed].map { |p| "#{p.parcel.id}@#{p.x},#{p.y}" }.join(' ')}"
    output.puts "Unplaced: #{result[:unplaced].empty? ? 'none' : result[:unplaced].join(', ')}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise ArgumentError, 'exactly one input path is required' unless ARGV.length == 1
    path = ARGV[0]
    raise ArgumentError, 'input file exceeds 1 MiB' if File.size(path) > 1024 * 1024
    data = JSON.parse(File.read(path, 1024 * 1024 + 1))
    PorchParcel.render(PorchParcel.pack(data))
  rescue JSON::ParserError, Errno::ENOENT, SystemCallError => error
    warn "Input error: #{error.message}"; exit 2
  rescue ArgumentError => error
    warn "Input error: #{error.message}"; exit 2
  end
end
