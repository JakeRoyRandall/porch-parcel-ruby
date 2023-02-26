#!/usr/bin/env ruby
require 'json'
require 'csv'
require 'cgi'
require 'set'

module PorchParcel
  Parcel = Struct.new(:id, :width, :height, :rotatable)
  Placement = Struct.new(:parcel, :x, :y, :width, :height, :rotated)
  module_function

  def validate!(data)
    raise ArgumentError, 'input must be an object' unless data.is_a?(Hash)
    sw, sh, parcels, blocked = data['shelf_width'], data['shelf_height'], data['parcels'], data.fetch('blocked', [])
    integer = ->(v) { v.is_a?(Integer) && !v.is_a?(TrueClass) && !v.is_a?(FalseClass) }
    raise ArgumentError, 'shelf dimensions must be integers' unless integer.call(sw) && integer.call(sh)
    raise ArgumentError, 'shelf dimensions must be 1..40 by 1..20' unless sw.between?(1, 40) && sh.between?(1, 20)
    raise ArgumentError, 'parcels must be an array of at most 30 items' unless parcels.is_a?(Array) && parcels.length <= 30
    raise ArgumentError, 'blocked must be an array' unless blocked.is_a?(Array)
    blocked_seen = []
    blocked.each do |cell|
      raise ArgumentError, 'blocked cells must have integer x and y' unless cell.is_a?(Hash) && integer.call(cell['x']) && integer.call(cell['y'])
      raise ArgumentError, 'blocked cell is outside shelf' unless cell['x'].between?(0, sw - 1) && cell['y'].between?(0, sh - 1)
      key = [cell['x'], cell['y']]; raise ArgumentError, 'blocked cells must be unique' if blocked_seen.include?(key); blocked_seen << key
    end
    ids = []
    parcels.each do |item|
      raise ArgumentError, 'each parcel must be an object' unless item.is_a?(Hash)
      id, width, height = item['id'], item['width'], item['height']
      raise ArgumentError, 'parcel ids must be printable names up to 32 characters' unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,31}\z/)
      raise ArgumentError, 'parcel ids must be unique' if ids.include?(id)
      raise ArgumentError, 'parcel dimensions must be positive integers' unless integer.call(width) && integer.call(height) && width > 0 && height > 0
      raise ArgumentError, 'parcel dimensions must be at most 40x40' if width > 40 || height > 40
      raise ArgumentError, 'rotatable must be boolean' if item.key?('rotatable') && ![true, false].include?(item['rotatable'])
      ids << id
    end
    true
  end

  def pack(data, rotate: false, strategy: 'first-fit', margin: 0, sort: nil)
    validate!(data)
    raise ArgumentError, 'strategy must be first-fit, area, or best-fit' unless %w[first-fit area best-fit].include?(strategy)
    raise ArgumentError, 'sort must be input, area, or long-side' if sort && !%w[input area long-side].include?(sort)
    integer = ->(v) { v.is_a?(Integer) && !v.is_a?(TrueClass) && !v.is_a?(FalseClass) }
    raise ArgumentError, 'margin must be an integer from 0 to 3' unless integer.call(margin) && margin.between?(0, 3)
    shelf = Array.new(data['shelf_height']) { Array.new(data['shelf_width']) }
    blocked_coords = data.fetch('blocked', []).map { |cell| [cell['x'], cell['y']] }
    blocked = blocked_coords.to_set
    placed = []; unplaced = []
    ordering = sort || (strategy == 'area' ? 'area' : 'input')
    parcels = data['parcels'].each_with_index.sort_by { |raw, index| ordering == 'area' ? [-(raw['width'] * raw['height']), index] : ordering == 'long-side' ? [-[raw['width'], raw['height']].max, index] : [index] }.map(&:first)
    parcels.each do |raw|
      parcel = Parcel.new(raw['id'], raw['width'], raw['height'], raw.fetch('rotatable', true)); found = nil; best_score = nil
      (0...data['shelf_height']).each do |y|
        break if found && strategy != 'best-fit'
        (0...data['shelf_width']).each do |x|
          orientations = rotate && parcel.rotatable ? [[parcel.width, parcel.height, false], [parcel.height, parcel.width, true]] : [[parcel.width, parcel.height, false]]
          orientations.each do |width, height, rotated|
            next if x + width > data['shelf_width'] || y + height > data['shelf_height']
            envelope_left = x - margin; envelope_top = y - margin
            envelope_right = x + width + margin; envelope_bottom = y + height + margin
            next if envelope_left < 0 || envelope_top < 0 || envelope_right > data['shelf_width'] || envelope_bottom > data['shelf_height']
            clear = (envelope_top...envelope_bottom).all? do |row|
              (envelope_left...envelope_right).all? do |col|
                shelf[row][col].nil? && !blocked.include?([col, row])
              end
            end
            if clear
              candidate = [x, y, width, height, rotated]
              if strategy == 'best-fit'
                right_gaps = (y...(y + height)).map do |row|
                  col = x + width + margin; count = 0
                  while col < data['shelf_width'] && shelf[row][col].nil? && !blocked.include?([col, row])
                    count += 1; col += 1
                  end
                  count
                end
                bottom_gaps = (x...(x + width)).map do |col|
                  row = y + height + margin; count = 0
                  while row < data['shelf_height'] && shelf[row][col].nil? && !blocked.include?([col, row])
                    count += 1; row += 1
                  end
                  count
                end
                score = [right_gaps.min, bottom_gaps.min, y, x, rotated ? 1 : 0]
                if best_score.nil? || (score <=> best_score) == -1
                  best_score = score; found = candidate
                end
              else
                found = candidate; break
              end
            end
          end
          break if found && strategy != 'best-fit'
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
    result = { shelf_width: data['shelf_width'], shelf_height: data['shelf_height'], grid: shelf, blocked: blocked_coords, placed: placed, unplaced: unplaced, strategy: strategy, margin: margin }
    result[:sort] = sort if sort
    result
  end

  def render(result, output = $stdout, show_orientation: false)
    header = "PORCH PARCEL // #{result[:shelf_width]}x#{result[:shelf_height]} shelf // #{result[:strategy]}"
    header += " // sort #{result[:sort]}" if result[:sort]
    header += " // margin #{result[:margin]}" if result[:margin] > 0
    output.puts header
    result[:grid].each { |row| output.puts row.map { |cell| cell ? '#' : '.' }.join }
    placements = result[:placed].map { |p| show_orientation ? "#{p.parcel.id}@#{p.x},#{p.y}(#{p.width}x#{p.height}#{p.rotated ? ',rotated' : ''})" : "#{p.parcel.id}@#{p.x},#{p.y}" }
    output.puts "Placed: #{placements.join(' ')}"
    output.puts "Unplaced: #{result[:unplaced].empty? ? 'none' : result[:unplaced].join(', ')}"
    unless result[:blocked].empty?
      usable = result[:shelf_width] * result[:shelf_height] - result[:blocked].length
      output.puts "Blocked: #{result[:blocked].length} cell(s); usable area: #{usable}"
    end
  end

  def render_json(result, output = $stdout)
    total = result[:shelf_width] * result[:shelf_height]
    payload = {
      'shelf_width' => result[:shelf_width],
      'shelf_height' => result[:shelf_height],
      'strategy' => result[:strategy],
      'margin' => result[:margin],
      'blocked' => result[:blocked].map { |x, y| {'x' => x, 'y' => y} },
      'placed' => result[:placed].map { |p| {'id' => p.parcel.id, 'x' => p.x, 'y' => p.y, 'width' => p.width, 'height' => p.height, 'rotated' => p.rotated, 'rotatable' => p.parcel.rotatable} },
      'unplaced' => result[:unplaced],
      'occupied_area' => result[:placed].sum { |p| p.width * p.height },
      'usable_area' => total - result[:blocked].length
    }
    payload['sort'] = result[:sort] if result[:sort]
    output.puts JSON.generate(payload)
  end

  def render_csv(result, input_data, output = $stdout)
    output << CSV.generate_line(%w[id x y width height rotated status], row_sep: "\r\n")
    result[:placed].each do |placement|
      output << CSV.generate_line([placement.parcel.id, placement.x, placement.y, placement.width, placement.height, placement.rotated, 'placed'], row_sep: "\r\n")
    end
    result[:unplaced].each do |id|
      raw = input_data['parcels'].find { |parcel| parcel['id'] == id }
      output << CSV.generate_line([id, '', '', raw['width'], raw['height'], '', 'unplaced'], row_sep: "\r\n")
    end
  end

  def compare(data, rotate: false, margin: 0, sort: nil)
    %w[first-fit area best-fit].to_h { |strategy| [strategy, pack(data, rotate: rotate, strategy: strategy, margin: margin, sort: sort)] }
  end

  def validate_only(data, rotate: false, margin: 0)
    validate!(data)
    pack(data.merge('parcels' => []), rotate: rotate, margin: margin)
    data['parcels'].map do |parcel|
      fit = pack(data.merge('parcels' => [parcel]), rotate: rotate, margin: margin)[:unplaced].empty?
      {'id' => parcel['id'], 'fits_alone' => fit}
    end
  end

  def render_compare(results, output = $stdout)
    output.puts "PORCH PARCEL // strategy comparison"
    output.puts "strategy\toccupied\tplaced\tunused-usable\tunplaced#{results.values.any? { |result| result[:sort] } ? "\tsort" : ''}"
    results.each do |strategy, result|
      occupied = result[:placed].sum { |p| p.width * p.height }
      unused = result[:shelf_width] * result[:shelf_height] - result[:blocked].length - occupied
      sort_note = result[:sort] ? "\t#{result[:sort]}" : ''
      output.puts "#{strategy}\t#{occupied}\t#{result[:placed].length}\t#{unused}\t#{result[:unplaced].empty? ? 'none' : result[:unplaced].join(',')}#{sort_note}"
    end
  end

  def render_compare_json(results, output = $stdout)
    payload = results.to_h do |strategy, result|
      occupied = result[:placed].sum { |p| p.width * p.height }
      metrics = {'occupied_area' => occupied, 'placed_count' => result[:placed].length, 'unused_usable_area' => result[:shelf_width] * result[:shelf_height] - result[:blocked].length - occupied, 'unplaced' => result[:unplaced]}
      metrics['sort'] = result[:sort] if result[:sort]
      [strategy, metrics]
    end
    output.puts JSON.generate('schema_version' => 1, 'comparison' => payload)
  end

  def html_compare(results)
    panels = results.map do |strategy, result|
      doc = html(result); shelf = doc[/<section class="shelf".*?<\/section>/m]; legend = doc[/<section class="legend".*?<\/section>/m]
      occupied = result[:placed].sum { |p| p.width * p.height }; unused = result[:shelf_width] * result[:shelf_height] - result[:blocked].length - occupied
      unplaced = result[:unplaced].empty? ? 'none' : result[:unplaced].map { |id| CGI.escapeHTML(id) }.join(', ')
      "<article class=\"compare-panel\"><h2>#{CGI.escapeHTML(strategy)}</h2><p>Occupied #{occupied} · placed #{result[:placed].length} · unused usable #{unused}</p>#{shelf}#{legend}<p class=\"unplaced-line\">Unplaced: #{unplaced}</p></article>"
    end.join
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Porch Parcel strategy comparison</title><style>#{html_css(results.values.first[:shelf_width], results.values.first[:shelf_height])}.compare-panels{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}.compare-panel{background:#fffaf0;border:1px solid #dbc5a8;padding:16px}.compare-panel h2{margin-top:0;color:#ad5438}.compare-panel .shelf{box-shadow:none}.unplaced-line{font:12px monospace}@media(max-width:800px){.compare-panels{grid-template-columns:1fr}}</style></head><body><main><p class=\"eyebrow\">OFFLINE DELIVERY DESK · 2020</p><h1>Porch Parcel</h1><p class=\"lede\">Three ways to stack the same chaotic little porch.</p><section class=\"compare-panels\">#{panels}</section><footer>Created retrospectively in September 2026 · fictional 2020-inspired project</footer></main></body></html>"
  end

  def svg(result)
    esc = ->(text) { CGI.escapeHTML(text.to_s) }
    sw, sh = result[:shelf_width], result[:shelf_height]; pad = 2.0; occupied = result[:placed].sum { |p| p.width * p.height }; usable = sw * sh - result[:blocked].length; legend_lines = 2 + result[:placed].length + result[:unplaced].length; canvas_width = [sw + pad * 2, 24].max; canvas_height = sh + pad * 2 + legend_lines * 1.5
    blocked = result[:blocked].map { |x, y| "<rect class=\"blocked\" x=\"#{x + pad}\" y=\"#{y + pad}\" width=\"1\" height=\"1\" aria-label=\"Blocked shelf cell at #{x},#{y}\"/>" }.join
    parcels = result[:placed].map.with_index { |p, i| "<rect class=\"parcel\" x=\"#{p.x + pad}\" y=\"#{p.y + pad}\" width=\"#{p.width}\" height=\"#{p.height}\"/><text x=\"#{p.x + pad + p.width / 2.0}\" y=\"#{p.y + pad + p.height / 2.0}\" text-anchor=\"middle\" dominant-baseline=\"middle\">#{i + 1}</text>" }.join
    legend = result[:placed].map.with_index { |p, i| "<text x=\"#{pad}\" y=\"#{sh + pad + 1.5 + i * 1.5}\">#{i + 1}. #{esc.call(p.parcel.id)} #{p.width}×#{p.height}#{p.rotated ? ' · rotated' : ''}#{p.parcel.rotatable ? '' : ' · rotation locked'} at #{p.x},#{p.y}</text>" }.join
    unplaced = result[:unplaced].map.with_index { |id, i| "<text x=\"#{pad}\" y=\"#{sh + pad + 1.5 + (result[:placed].length + i) * 1.5}\">Unplaced: #{esc.call(id)}</text>" }.join
    sort_caption = result[:sort] ? " · Sort: #{esc.call(result[:sort])}" : ''
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 #{canvas_width} #{canvas_height}\" role=\"img\" aria-labelledby=\"title desc\"><title id=\"title\">Porch Parcel #{esc.call(result[:strategy])} shelf</title><desc id=\"desc\">#{occupied} occupied area, #{usable} usable area, margin #{result[:margin]}, #{result[:placed].length} placed parcels, #{result[:unplaced].length} unplaced</desc><style>.shelf{fill:url(#grid);stroke:#744831;stroke-width:.08}.blocked{fill:#6e5c4d;stroke:#3f3027;stroke-width:.03}.parcel{fill:#e97b54;stroke:#4f3225;stroke-width:.04}text{font:0.32px monospace;fill:#3e3026}</style><defs><pattern id=\"grid\" width=\"1\" height=\"1\" patternUnits=\"userSpaceOnUse\"><rect width=\"1\" height=\"1\" fill=\"#e9d3b1\"/><path d=\"M 1 0 L 0 0 0 1\" fill=\"none\" stroke=\"#d7b993\" stroke-width=\".02\"/></pattern></defs><rect class=\"shelf\" x=\"#{pad}\" y=\"#{pad}\" width=\"#{sw}\" height=\"#{sh}\"/>#{blocked}#{parcels}<text x=\"#{pad}\" y=\"#{sh + pad + 0.8}\">Strategy: #{esc.call(result[:strategy])}#{sort_caption} · Margin: #{result[:margin]} · Occupied: #{occupied} · Usable: #{usable}</text>#{legend}#{unplaced}</svg>"
  end

  def html(result, show_orientation: true)
    esc = ->(text) { CGI.escapeHTML(text.to_s) }
    total = result[:shelf_width] * result[:shelf_height]
    occupied = result[:placed].sum { |p| p.width * p.height }
    usable = total - result[:blocked].length
    sort_label = result[:sort] ? " · Sort: #{esc.call(result[:sort])}" : ''
    strategy_tag = "<p class=\"strategy-label\">Strategy: #{esc.call(result[:strategy])}#{sort_label} · Margin: #{result[:margin]} · Usable area: #{usable}</p>"
    parcels = result[:placed].map.with_index do |p, index|
      label = "#{esc.call(p.parcel.id)} · #{p.width}×#{p.height}#{p.rotated ? ' · rotated' : ''}#{p.parcel.rotatable ? '' : ' · rotation locked'}"
      "<div class=\"parcel\" aria-label=\"#{label}\" style=\"left:#{p.x * 100.0 / result[:shelf_width]}%;top:#{p.y * 100.0 / result[:shelf_height]}%;width:#{p.width * 100.0 / result[:shelf_width]}%;height:#{p.height * 100.0 / result[:shelf_height]}%\"><span>#{index + 1}</span></div>"
    end.join
    blocked_cells = result[:blocked].map do |x, y|
      "<div class=\"blocked\" role=\"img\" aria-label=\"Blocked shelf cell at #{x},#{y}\" style=\"position:absolute;left:#{x * 100.0 / result[:shelf_width]}%;top:#{y * 100.0 / result[:shelf_height]}%;width:#{100.0 / result[:shelf_width]}%;height:#{100.0 / result[:shelf_height]}%;background:repeating-linear-gradient(45deg,#6e5c4d 0 3px,#aa927c 3px 6px);border:1px solid #3f3027;box-sizing:border-box\"></div>"
    end.join
    parcels = blocked_cells + parcels
    legend = result[:placed].map.with_index { |p, index| "<li><b>#{index + 1}. #{esc.call(p.parcel.id)}</b> #{p.width}×#{p.height}#{p.rotated ? ' · rotated' : ''}#{p.parcel.rotatable ? '' : ' · rotation locked'} at #{p.x},#{p.y}</li>" }.join
    unplaced = result[:unplaced].empty? ? '<li>none</li>' : result[:unplaced].map { |id| "<li>#{esc.call(id)}</li>" }.join
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Porch Parcel shelf</title><style>#{html_css(result[:shelf_width], result[:shelf_height])}</style></head><body><main><p class=\"eyebrow\">OFFLINE DELIVERY DESK · 2020</p><h1>Porch Parcel</h1><p class=\"lede\">A calm little shelf plan for a chaotic little porch.</p><section class=\"stats\"><div><b>#{occupied}</b><span>occupied area</span></div><div><b>#{total}</b><span>total area</span></div><div><b>#{usable}</b><span>usable area</span></div><div><b>#{result[:placed].length}</b><span>placed</span></div></section><section class=\"shelf\" aria-label=\"#{result[:shelf_width]} by #{result[:shelf_height]} shelf\">#{parcels}</section><section class=\"legend\"><h2>Parcel legend</h2>#{strategy_tag}<ul>#{legend}</ul></section><section class=\"unplaced\"><h2>Still on the porch</h2><ul>#{unplaced}</ul></section><footer>Created retrospectively in September 2026 · fictional 2020-inspired project</footer></main></body></html>"
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
    args = ARGV.dup; rotate = !!args.delete('--rotate'); show = !!args.delete('--show-orientation'); json = !!args.delete('--json'); csv = !!args.delete('--csv'); compare_mode = !!args.delete('--compare'); validate_mode = !!args.delete('--validate-only'); force = !!args.delete('--force'); strategy = 'first-fit'; strategy_explicit = false; sort = nil; margin = 0; html_path = nil; svg_path = nil
    if (strategy_index = args.index('--strategy') )
      args.delete_at(strategy_index); strategy = args.delete_at(strategy_index); raise ArgumentError, '--strategy needs a value' unless strategy
      strategy_explicit = true
    end
    if (sort_index = args.index('--sort') )
      args.delete_at(sort_index); sort = args.delete_at(sort_index); raise ArgumentError, '--sort needs a value' unless sort
    end
    if (margin_index = args.index('--margin') )
      args.delete_at(margin_index); margin_text = args.delete_at(margin_index); raise ArgumentError, '--margin needs a value' unless margin_text
      raise ArgumentError, 'margin must be an integer from 0 to 3' unless margin_text.match?(/\A\d+\z/); margin = Integer(margin_text, 10)
    end
    if (index = args.index('--html') )
      args.delete_at(index); html_path = args.delete_at(index); raise ArgumentError, '--html needs a path' unless html_path
    end
    if (index = args.index('--svg') )
      args.delete_at(index); svg_path = args.delete_at(index); raise ArgumentError, '--svg needs a path' unless svg_path
    end
    raise ArgumentError, 'unknown flag' if args.any? { |arg| arg.start_with?('--') }
    raise ArgumentError, 'exactly one input path is required' unless args.length == 1
    path = args.first
    raise ArgumentError, 'input file exceeds 1 MiB' if File.size(path) > 1024 * 1024
    data = JSON.parse(File.read(path, 1024 * 1024 + 1))
    raise ArgumentError, '--csv cannot be combined with --json, --compare, or --validate-only' if csv && (json || compare_mode || validate_mode)
    raise ArgumentError, '--compare cannot be combined with --strategy' if compare_mode && strategy_explicit
    raise ArgumentError, '--svg cannot be combined with --html or --compare' if svg_path && (html_path || compare_mode)
    raise ArgumentError, '--validate-only cannot be combined with --strategy, --sort, --compare, --html, --svg, --show-orientation, or --force' if validate_mode && (strategy_explicit || sort || compare_mode || html_path || svg_path || show || force)
    if validate_mode
      results = PorchParcel.validate_only(data, rotate: rotate, margin: margin)
      if json then puts JSON.generate('valid' => true, 'parcels' => results) else results.each { |parcel| puts "#{parcel['id']}\tfits-alone\t#{parcel['fits_alone'] ? 'yes' : 'no'}" } end
      exit 0
    end
    if compare_mode
      results = PorchParcel.compare(data, rotate: rotate, margin: margin, sort: sort)
      if json then PorchParcel.render_compare_json(results, $stdout) else PorchParcel.render_compare(results, $stdout) end
      PorchParcel.write_html(html_path, PorchParcel.html_compare(results), force: force) if html_path
    else
      result = PorchParcel.pack(data, rotate: rotate, strategy: strategy, margin: margin, sort: sort)
      if json then PorchParcel.render_json(result, $stdout) elsif csv then PorchParcel.render_csv(result, data, $stdout) else PorchParcel.render(result, $stdout, show_orientation: show) end
      if html_path
        raise ArgumentError, 'output exists; use --force to replace it' if File.exist?(html_path) && !force
        PorchParcel.write_html(html_path, PorchParcel.html(result), force: force)
      end
      if svg_path
        raise ArgumentError, 'output exists; use --force to replace it' if File.exist?(svg_path) && !force
        PorchParcel.write_html(svg_path, PorchParcel.svg(result), force: force)
      end
    end
  rescue JSON::ParserError, Errno::ENOENT, SystemCallError => error
    warn "Input error: #{error.message}"; exit 2
  rescue ArgumentError => error
    warn "Input error: #{error.message}"; exit 2
  end
end
