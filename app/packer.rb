#!/usr/bin/env ruby
require 'json'
require 'cgi'

module PorchParcel
  Parcel = Struct.new(:id, :width, :height)
  Placement = Struct.new(:parcel, :x, :y, :width, :height, :rotated)
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
      raise ArgumentError, 'parcel dimensions must be at most 40x40' if width > 40 || height > 40
      ids << id
    end
    true
  end

  def pack(data, rotate: false)
    validate!(data)
    shelf = Array.new(data['shelf_height']) { Array.new(data['shelf_width']) }
    placed = []; unplaced = []
    data['parcels'].each do |raw|
      parcel = Parcel.new(raw['id'], raw['width'], raw['height']); found = nil
      (0...data['shelf_height']).each do |y|
        break if found
        (0...data['shelf_width']).each do |x|
          [[parcel.width, parcel.height, false], [parcel.height, parcel.width, true]].take(rotate ? 2 : 1).each do |width, height, rotated|
            next if x + width > data['shelf_width'] || y + height > data['shelf_height']
            cells = (y...(y + height)).flat_map { |row| (x...(x + width)).map { |col| shelf[row][col] } }
            if cells.all?(&:nil?)
              found = [x, y, width, height, rotated]; break
            end
          end
          break if found
        end
      end
      if found
        x, y, width, height, rotated = found
        (y...(y + height)).each { |row| (x...(x + width)).each { |col| shelf[row][col] = parcel.id } }
        placed << Placement.new(parcel, x, y, width, height, rotated)
      else
        unplaced << parcel.id
      end
    end
    { shelf_width: data['shelf_width'], shelf_height: data['shelf_height'], grid: shelf, placed: placed, unplaced: unplaced }
  end

  def render(result, output = $stdout, show_orientation: false)
    output.puts "PORCH PARCEL // #{result[:shelf_width]}x#{result[:shelf_height]} shelf"
    result[:grid].each { |row| output.puts row.map { |cell| cell ? '#' : '.' }.join }
    placements = result[:placed].map { |p| show_orientation ? "#{p.parcel.id}@#{p.x},#{p.y}(#{p.width}x#{p.height}#{p.rotated ? ',rotated' : ''})" : "#{p.parcel.id}@#{p.x},#{p.y}" }
    output.puts "Placed: #{placements.join(' ')}"
    output.puts "Unplaced: #{result[:unplaced].empty? ? 'none' : result[:unplaced].join(', ')}"
  end

  def html(result, show_orientation: true)
    esc = ->(text) { CGI.escapeHTML(text.to_s) }
    total = result[:shelf_width] * result[:shelf_height]
    occupied = result[:placed].sum { |p| p.width * p.height }
    parcels = result[:placed].map.with_index do |p, index|
      label = "#{esc.call(p.parcel.id)} · #{p.width}×#{p.height}#{p.rotated ? ' · rotated' : ''}"
      "<div class=\"parcel\" aria-label=\"#{label}\" style=\"left:#{p.x * 100.0 / result[:shelf_width]}%;top:#{p.y * 100.0 / result[:shelf_height]}%;width:#{p.width * 100.0 / result[:shelf_width]}%;height:#{p.height * 100.0 / result[:shelf_height]}%\"><span>#{index + 1}</span></div>"
    end.join
    legend = result[:placed].map.with_index { |p, index| "<li><b>#{index + 1}. #{esc.call(p.parcel.id)}</b> #{p.width}×#{p.height}#{p.rotated ? ' · rotated' : ''} at #{p.x},#{p.y}</li>" }.join
    unplaced = result[:unplaced].empty? ? '<li>none</li>' : result[:unplaced].map { |id| "<li>#{esc.call(id)}</li>" }.join
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Porch Parcel shelf</title><style>#{html_css(result[:shelf_width], result[:shelf_height])}</style></head><body><main><p class=\"eyebrow\">OFFLINE DELIVERY DESK · 2020</p><h1>Porch Parcel</h1><p class=\"lede\">A calm little shelf plan for a chaotic little porch.</p><section class=\"stats\"><div><b>#{occupied}</b><span>occupied area</span></div><div><b>#{total}</b><span>total area</span></div><div><b>#{result[:placed].length}</b><span>placed</span></div></section><section class=\"shelf\" aria-label=\"#{result[:shelf_width]} by #{result[:shelf_height]} shelf\">#{parcels}</section><section class=\"legend\"><h2>Parcel legend</h2><ul>#{legend}</ul></section><section class=\"unplaced\"><h2>Still on the porch</h2><ul>#{unplaced}</ul></section><footer>Created retrospectively in September 2026 · fictional 2020-inspired project</footer></main></body></html>"
  end

  def html_css(width, height)
    "body{margin:0;background:#f5ead8;color:#3e3026;font:16px Georgia,serif}main{max-width:900px;margin:0 auto;padding:48px 24px}.eyebrow{font:11px monospace;letter-spacing:.14em;color:#9d6544}h1{font-size:clamp(48px,9vw,92px);line-height:.9;margin:12px 0;color:#ad5438}.lede{font-size:20px;color:#705843}.stats{display:flex;flex-wrap:wrap;gap:12px;margin:30px 0}.stats div{background:#fffaf0;border:1px solid #dbc5a8;padding:14px 18px;min-width:100px}.stats b{display:block;font-size:27px;color:#ad5438}.stats span{font:11px monospace;text-transform:uppercase;color:#806d58}.shelf{position:relative;width:100%;aspect-ratio:#{width}/#{height};background-color:#e9d3b1;background-image:linear-gradient(#d7b993 1px,transparent 1px),linear-gradient(90deg,#d7b993 1px,transparent 1px);background-size:calc(100% / #{width}) calc(100% / #{height});border:8px solid #744831;box-sizing:border-box;box-shadow:0 10px 0 #c79e75}.parcel{position:absolute;background:#e97b54;border:2px solid #4f3225;box-sizing:border-box}.parcel span{display:block;width:18px;height:18px;margin:2px;background:#fff4d6;border-radius:50%;font:11px/18px monospace;text-align:center}.legend{margin-top:34px;border-top:1px solid #cdb493}.legend h2,.unplaced h2{font-size:28px}.legend li,.unplaced li{font:14px monospace;margin:6px 0}.unplaced{margin-top:32px;border-top:1px solid #cdb493}footer{margin-top:40px;color:#806d58;font:11px monospace}"
  end

  def write_html(path, content, force: false)
    if force
      File.write(path, content)
    else
      File.open(path, 'wx') { |file| file.write(content) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    args = ARGV.dup; rotate = !!args.delete('--rotate'); show = !!args.delete('--show-orientation'); force = !!args.delete('--force'); html_path = nil
    if (index = args.index('--html') )
      args.delete_at(index); html_path = args.delete_at(index); raise ArgumentError, '--html needs a path' unless html_path
    end
    raise ArgumentError, 'unknown flag' if args.any? { |arg| arg.start_with?('--') }
    raise ArgumentError, 'exactly one input path is required' unless args.length == 1
    path = args.first
    raise ArgumentError, 'input file exceeds 1 MiB' if File.size(path) > 1024 * 1024
    data = JSON.parse(File.read(path, 1024 * 1024 + 1))
    result = PorchParcel.pack(data, rotate: rotate)
    PorchParcel.render(result, $stdout, show_orientation: show)
    if html_path
      raise ArgumentError, 'output exists; use --force to replace it' if File.exist?(html_path) && !force
      PorchParcel.write_html(html_path, PorchParcel.html(result), force: force)
    end
  rescue JSON::ParserError, Errno::ENOENT, SystemCallError => error
    warn "Input error: #{error.message}"; exit 2
  rescue ArgumentError => error
    warn "Input error: #{error.message}"; exit 2
  end
end
