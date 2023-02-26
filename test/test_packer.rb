require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'stringio'
require_relative '../app/packer'

class PorchParcelTest < Minitest::Test
  def test_first_fit_geometry_is_row_major
    result = PorchParcel.pack('shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [
      {'id' => 'A', 'width' => 2, 'height' => 2}, {'id' => 'B', 'width' => 3, 'height' => 1}
    ])
    assert_equal [['A', 'A', 'B', 'B', 'B'], ['A', 'A', nil, nil, nil], [nil, nil, nil, nil, nil]], result[:grid]
    assert_equal [['A', 0, 0], ['B', 2, 0]], result[:placed].map { |p| [p.parcel.id, p.x, p.y] }
    assert_equal 'first-fit', result[:strategy]
  end
  def test_area_strategy_is_stable_and_identified
    data = {'shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [{'id' => 'small', 'width' => 1, 'height' => 1}, {'id' => 'large', 'width' => 3, 'height' => 2}, {'id' => 'medium', 'width' => 2, 'height' => 1}]}
    first = PorchParcel.pack(data)
    area = PorchParcel.pack(data, strategy: 'area')
    assert_equal ['small', 'large', 'medium'], first[:placed].map { |p| p.parcel.id }
    assert_equal ['large', 'medium', 'small'], area[:placed].map { |p| p.parcel.id }
    assert_includes PorchParcel.html(area), 'Strategy: area'
    assert_raises(ArgumentError) { PorchParcel.pack(data, strategy: 'sideways') }
  end
  def test_best_fit_is_distinct_deterministic_heuristic
    data = {'shelf_width' => 5, 'shelf_height' => 4, 'parcels' => [
      {'id' => 'a', 'width' => 1, 'height' => 1}, {'id' => 'b', 'width' => 1, 'height' => 2},
      {'id' => 'c', 'width' => 4, 'height' => 3}, {'id' => 'd', 'width' => 1, 'height' => 3}
    ]}
    first = PorchParcel.pack(data)
    best = PorchParcel.pack(data, strategy: 'best-fit')
    assert_equal ['a', 'b', 'd'], first[:placed].map { |p| p.parcel.id }
    assert_equal ['a', 'b', 'c'], best[:placed].map { |p| p.parcel.id }
    assert_operator best[:placed].sum { |p| p.width * p.height }, :>, first[:placed].sum { |p| p.width * p.height }
    assert_equal best[:grid], PorchParcel.pack(data, strategy: 'best-fit')[:grid]
  end
  def test_best_fit_considers_later_positions_and_respects_clearance
    data = {'shelf_width' => 4, 'shelf_height' => 2, 'blocked' => [{'x' => 0, 'y' => 0}], 'parcels' => [{'id' => 'a', 'width' => 1, 'height' => 1}, {'id' => 'b', 'width' => 1, 'height' => 1}]}
    result = PorchParcel.pack(data, strategy: 'best-fit')
    assert_equal [3, 1], [result[:placed][0].x, result[:placed][0].y]
    assert_equal [3, 0], [result[:placed][1].x, result[:placed][1].y]
    occupied = result[:grid].flatten.compact
    assert_equal occupied.length, occupied.count { |id| %w[a b].include?(id) }
    assert_equal [[0, 0]], result[:blocked]
  end
  def test_area_strategy_can_place_more_area_than_input_order
    data = {'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => [
      {'id' => 'A', 'width' => 1, 'height' => 1}, {'id' => 'B', 'width' => 1, 'height' => 1},
      {'id' => 'C', 'width' => 1, 'height' => 1}, {'id' => 'D', 'width' => 1, 'height' => 2}
    ]}
    first = PorchParcel.pack(data); area = PorchParcel.pack(data, strategy: 'area')
    assert_equal 3, first[:placed].length; assert_equal 3, area[:placed].length
    assert_operator area[:placed].sum { |p| p.width * p.height }, :>, first[:placed].sum { |p| p.width * p.height }
  end
  def test_sort_long_side_changes_order_and_is_stable
    data = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [
      {'id' => 'small', 'width' => 1, 'height' => 1}, {'id' => 'bar', 'width' => 3, 'height' => 1}, {'id' => 'tie-a', 'width' => 2, 'height' => 2}, {'id' => 'tie-b', 'width' => 2, 'height' => 2}
    ]}
    input = PorchParcel.pack(data); sorted = PorchParcel.pack(data, sort: 'long-side')
    refute_equal input[:placed].map { |p| [p.parcel.id, p.x, p.y] }, sorted[:placed].map { |p| [p.parcel.id, p.x, p.y] }
    assert_equal sorted[:grid], PorchParcel.pack(data, sort: 'long-side')[:grid]
  end
  def test_sort_validation_and_validate_only_rejection
    data = {'shelf_width' => 2, 'shelf_height' => 1, 'parcels' => []}
    assert_raises(ArgumentError) { PorchParcel.pack(data, sort: 'random') }
  end
  def test_explicit_sort_is_reported_without_changing_strategy_label
    data = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'small', 'width' => 1, 'height' => 1}, {'id' => 'bar', 'width' => 3, 'height' => 1}]}
    result = PorchParcel.pack(data, strategy: 'area', sort: 'input'); assert_equal 'area', result[:strategy]; assert_equal 'input', result[:sort]
    output = StringIO.new; PorchParcel.render_json(result, output); parsed = JSON.parse(output.string); assert_equal 'area', parsed['strategy']; assert_equal 'input', parsed['sort']
    default_output = StringIO.new; PorchParcel.render_json(PorchParcel.pack(data, strategy: 'area'), default_output); refute_includes JSON.parse(default_output.string).keys, 'sort'
    compared = StringIO.new; PorchParcel.render_compare(PorchParcel.compare(data, sort: 'long-side'), compared); header = compared.string.lines[1].chomp; assert_equal 6, header.split("\t").length; compared.string.lines.drop(2).each { |line| assert_equal 6, line.chomp.split("\t").length }
  end
  def test_exact_edge_fit
    result = PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'edge', 'width' => 4, 'height' => 2}])
    assert_empty result[:unplaced]; assert_equal [0, 0], [result[:placed][0].x, result[:placed][0].y]
  end
  def test_rotation_places_parcel_that_only_fits_turning
    data = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}
    assert_equal ['turn'], PorchParcel.pack(data)[:unplaced]
    result = PorchParcel.pack(data, rotate: true)
    refute_empty result[:placed]; assert result[:placed][0].rotated; assert_equal [3, 2], [result[:placed][0].width, result[:placed][0].height]
  end
  def test_rotation_lock_keeps_only_original_orientation
    data = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'locked', 'width' => 2, 'height' => 3, 'rotatable' => false}]}
    result = PorchParcel.pack(data, rotate: true)
    assert_equal ['locked'], result[:unplaced]
    assert_raises(ArgumentError) { PorchParcel.pack(data.merge('parcels' => [data['parcels'][0].merge('rotatable' => 'yes')]), rotate: true) }
  end
  def test_rotation_lock_is_reported_in_json_html_and_svg
    result = PorchParcel.pack({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => [{'id' => 'locked', 'width' => 1, 'height' => 1, 'rotatable' => false}]})
    assert_equal false, JSON.parse(StringIO.new.tap { |io| PorchParcel.render_json(result, io) }.string)['placed'][0]['rotatable']
    assert_includes PorchParcel.html(result), 'rotation locked'
    assert_includes PorchParcel.svg(result), 'rotation locked'
  end
  def test_validate_only_reuses_rotation_margin_and_blocked_fit_rules
    data = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [
      {'id' => 'turn', 'width' => 2, 'height' => 3}, {'id' => 'locked', 'width' => 2, 'height' => 3, 'rotatable' => false}
    ]}
    assert_equal [{'id' => 'turn', 'fits_alone' => true}, {'id' => 'locked', 'fits_alone' => false}], PorchParcel.validate_only(data, rotate: true)
    margin = PorchParcel.validate_only({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal false, margin[0]['fits_alone']
  end
  def test_cli_validate_only_json_and_conflicts
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json'); File.write(input, JSON.generate('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => [{'id' => 'x', 'width' => 2, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      parsed = JSON.parse(`ruby #{script} --validate-only --json #{input}`)
      assert_equal false, parsed['parcels'][0]['fits_alone']
      conflict = `ruby #{script} --validate-only --html #{File.join(dir, 'x.html')} #{input} 2>&1`; assert_includes conflict, 'cannot be combined'
      assert_includes `ruby #{script} --validate-only --show-orientation #{input} 2>&1`, 'cannot be combined'
      assert_includes `ruby #{script} --validate-only --force #{input} 2>&1`, 'cannot be combined'
      assert_includes `ruby #{script} --validate-only --sort area #{input} 2>&1`, 'cannot be combined'
      empty = File.join(dir, 'empty.json'); File.write(empty, JSON.generate('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => []))
      assert_includes `ruby #{script} --validate-only --margin 4 #{empty} 2>&1`, 'margin must be an integer'
    end
  end
  def test_original_orientation_wins_tie
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 3, 'parcels' => [{'id' => 'tie', 'width' => 2, 'height' => 2}]}, rotate: true)
    refute result[:placed][0].rotated
  end
  def test_rotation_has_no_overlaps
    result = PorchParcel.pack({'shelf_width' => 4, 'shelf_height' => 4, 'parcels' => [
      {'id' => 'A', 'width' => 3, 'height' => 2}, {'id' => 'B', 'width' => 2, 'height' => 3}
    ]}, rotate: true)
    occupied = result[:grid].flatten.compact; assert_equal occupied.uniq.sort, %w[A B].sort
  end
  def test_unplaced_when_no_rectangle_remains
    result = PorchParcel.pack('shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'A', 'width' => 2, 'height' => 2}, {'id' => 'B', 'width' => 2, 'height' => 1}])
    assert_equal ['B'], result[:unplaced]
  end
  def test_blocked_cells_reduce_capacity_and_are_reported_in_html
    data = {'shelf_width' => 2, 'shelf_height' => 2, 'blocked' => [{'x' => 1, 'y' => 0}], 'parcels' => [{'id' => 'A', 'width' => 2, 'height' => 2}]}
    result = PorchParcel.pack(data)
    assert_equal [[1, 0]], result[:blocked]
    assert_equal ['A'], result[:unplaced]
    page = PorchParcel.html(result)
    assert_includes page, 'usable area'
    assert_includes page, 'Usable area: 3'
    assert_includes page, 'Blocked shelf cell at 1,0'
    assert_includes page, 'repeating-linear-gradient'
    assert_includes page, 'position:absolute'
    output = StringIO.new
    PorchParcel.render(result, output)
    assert_includes output.string, 'Blocked: 1 cell(s); usable area: 3'
  end
  def test_unblocked_cli_render_keeps_original_summary_shape
    data = {'shelf_width' => 1, 'shelf_height' => 1, 'parcels' => []}
    result = PorchParcel.pack(data)
    output = StringIO.new; PorchParcel.render(result, output)
    explicit = StringIO.new; PorchParcel.render(PorchParcel.pack(data, margin: 0), explicit)
    assert_equal output.string, explicit.string
    assert_equal 'PORCH PARCEL // 1x1 shelf // first-fit', output.string.lines.first.chomp
    refute_includes output.string, 'Blocked:'
  end
  def test_cli_explicit_zero_margin_matches_default_text
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json')
      File.write(input, JSON.generate('shelf_width' => 2, 'shelf_height' => 2, 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      default = `ruby #{script} #{input}`
      explicit = `ruby #{script} --margin 0 #{input}`
      assert_equal default, explicit
    end
  end
  def test_json_render_is_deterministic_and_contains_placement_geometry
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}, rotate: true)
    output = StringIO.new
    PorchParcel.render_json(result, output)
    payload = JSON.parse(output.string)
    assert_equal %w[shelf_width shelf_height strategy margin blocked placed unplaced occupied_area usable_area], payload.keys
    assert_equal [], payload['blocked']
    assert_equal ['turn'], payload['placed'].map { |p| p['id'] }
    assert_equal true, payload['placed'][0]['rotated']
    assert_equal 6, payload['occupied_area']
    assert_equal 6, payload['usable_area']
  end
  def test_cli_json_stdout_is_parseable_and_errors_stay_on_stderr
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json')
      File.write(input, JSON.generate('shelf_width' => 2, 'shelf_height' => 2, 'blocked' => [{'x' => 1, 'y' => 0}], 'parcels' => [{'id' => 'box', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      stdout = `ruby #{script} --json #{input}`
      payload = JSON.parse(stdout)
      assert_equal 2, payload['shelf_width']
      assert_equal 'box', payload['placed'][0]['id']
      error = `ruby #{script} --json #{dir}/missing.json 2>&1`
      assert_includes error, 'Input error'
      refute_includes error, '{"shelf_width"'
    end
  end
  def test_csv_export_has_fixed_quoted_placement_rows
    data = {'shelf_width' => 2, 'shelf_height' => 1, 'parcels' => [{'id' => 'box-1', 'width' => 1, 'height' => 1}, {'id' => 'too-big', 'width' => 3, 'height' => 1}]}
    result = PorchParcel.pack(data); output = StringIO.new; PorchParcel.render_csv(result, data, output)
    rows = CSV.parse(output.string); assert_equal %w[id x y width height rotated status], rows.first; assert_equal ['box-1', '0', '0', '1', '1', 'false', 'placed'], rows[1]; assert_equal ['too-big', '', '', '3', '1', '', 'unplaced'], rows[2]
    assert output.string.end_with?("\r\n")
  end
  def test_cli_csv_rejects_json_compare_and_validate_only
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json'); File.write(input, JSON.generate('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => [])); script = File.expand_path('../app/packer.rb', __dir__)
      assert_includes `ruby #{script} --csv --json #{input} 2>&1`, 'cannot be combined'; assert_includes `ruby #{script} --csv --compare #{input} 2>&1`, 'cannot be combined'; assert_includes `ruby #{script} --csv --validate-only #{input} 2>&1`, 'cannot be combined'
    end
  end
  def test_margin_requires_clear_shelf_boundary_and_separates_parcels
    tight = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 1, 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal ['A'], tight[:unplaced]
    separated = PorchParcel.pack({'shelf_width' => 5, 'shelf_height' => 3, 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}, {'id' => 'B', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal [[1, 1], [3, 1]], separated[:placed].map { |p| [p.x, p.y] }
    assert_equal 1, separated[:margin]
  end
  def test_margin_supports_rotated_parcel_and_blocked_obstacle
    rotated = PorchParcel.pack({'shelf_width' => 4, 'shelf_height' => 5, 'parcels' => [{'id' => 'turn', 'width' => 3, 'height' => 2}]}, rotate: true, margin: 1)
    assert_equal ['turn'], rotated[:placed].map { |p| p.parcel.id }
    assert rotated[:placed][0].rotated
    blocked = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 3, 'blocked' => [{'x' => 1, 'y' => 1}], 'parcels' => [{'id' => 'A', 'width' => 1, 'height' => 1}]}, margin: 1)
    assert_equal ['A'], blocked[:unplaced]
  end
  def test_margin_is_reported_in_all_output_formats_and_validated
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 3, 'parcels' => []}, margin: 2)
    text = StringIO.new; PorchParcel.render(result, text)
    assert_includes text.string, 'margin 2'
    json = StringIO.new; PorchParcel.render_json(result, json)
    assert_equal 2, JSON.parse(json.string)['margin']
    assert_includes PorchParcel.html(result), 'Margin: 2'
    assert_raises(ArgumentError) { PorchParcel.pack({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => []}, margin: 4) }
    assert_raises(ArgumentError) { PorchParcel.pack({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => []}, margin: 1.0) }
  end
  def test_rotation_can_fit_around_blocked_cell
    data = {'shelf_width' => 3, 'shelf_height' => 3, 'blocked' => [{'x' => 0, 'y' => 0}, {'x' => 1, 'y' => 0}], 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}
    result = PorchParcel.pack(data, rotate: true)
    assert_equal ['turn'], result[:placed].map { |p| p.parcel.id }
    assert result[:placed][0].rotated
    refute_equal [0, 0], [result[:placed][0].x, result[:placed][0].y]
  end
  def test_blocked_schema_rejects_duplicates_and_out_of_bounds
    base = {'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => []}
    assert_raises(ArgumentError) { PorchParcel.pack(base.merge('blocked' => [{'x' => 1, 'y' => 1}, {'x' => 1, 'y' => 1}])) }
    assert_raises(ArgumentError) { PorchParcel.pack(base.merge('blocked' => [{'x' => 3, 'y' => 0}])) }
    assert_raises(ArgumentError) { PorchParcel.pack(base.merge('blocked' => [{'x' => 1.0, 'y' => 0}])) }
  end
  def test_malformed_schema_is_rejected
    bad = {'shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}, {'id' => 'x', 'width' => 1, 'height' => 1}]}
    assert_raises(ArgumentError) { PorchParcel.pack(bad) }
    assert_raises(ArgumentError) { PorchParcel.pack('shelf_width' => 4.0, 'shelf_height' => 2, 'parcels' => []) }
    assert_raises(ArgumentError) { PorchParcel.pack('shelf_width' => 41, 'shelf_height' => 2, 'parcels' => []) }
    assert_raises(ArgumentError) { PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => "bad\nline", 'width' => 1, 'height' => 1}]) }
  end
  def test_cli_rejects_bad_paths_args_and_oversize_without_traceback
    Dir.mktmpdir do |dir|
      script = File.expand_path('../app/packer.rb', __dir__)
      missing = `ruby #{script} #{dir}/missing.json 2>&1`; assert_includes missing, 'Input error'; refute_includes missing, 'Traceback'
      directory = `ruby #{script} #{dir} 2>&1`; assert_includes directory, 'Input error'; refute_includes directory, 'Traceback'
      too_big = File.join(dir, 'big.json'); File.write(too_big, 'x' * (1024 * 1024 + 1))
      oversized = `ruby #{script} #{too_big} 2>&1`; assert_includes oversized, 'Input error'; refute_includes oversized, 'Traceback'
      extra = `ruby #{script} one.json two.json 2>&1`; assert_includes extra, 'exactly one input path'; refute_includes extra, 'Traceback'
      unknown = `ruby #{script} --wat one.json 2>&1`; assert_includes unknown, 'unknown flag'; refute_includes unknown, 'Traceback'
    end
  end
  def test_html_report_contains_geometry_labels_and_area
    result = PorchParcel.pack('shelf_width' => 4, 'shelf_height' => 2, 'parcels' => [{'id' => 'box1', 'width' => 2, 'height' => 1}, {'id' => 'box2', 'width' => 1, 'height' => 2}])
    page = PorchParcel.html(result)
    assert_includes page, '<!doctype html>'; assert_includes page, 'box1'; assert_includes page, '2×1'; assert_includes page, 'occupied area'; assert_includes page, 'width:50.0%'; assert_includes page, 'height:100.0%'
    square = PorchParcel.html(PorchParcel.pack('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => []))
    assert_includes square, 'aspect-ratio:1/1'; assert_includes square, 'background-size:calc(100% / 1) calc(100% / 1)'
  end
  def test_cli_html_export_and_existing_file_guard
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json'); output = File.join(dir, 'report.html')
      File.write(input, JSON.generate('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      first = `ruby #{script} --html #{output} #{input}`; assert File.file?(output); assert_includes File.read(output), 'x'
      second = `ruby #{script} --html #{output} #{input} 2>&1`; assert_includes second, 'output exists'
      forced = `ruby #{script} --html #{output} --force #{input}`; assert File.file?(output); refute_includes forced, 'Traceback'
    end
  end
  def test_compare_reports_all_strategies_and_metrics
    data = {'shelf_width' => 5, 'shelf_height' => 4, 'parcels' => [
      {'id' => 'a', 'width' => 1, 'height' => 1}, {'id' => 'b', 'width' => 1, 'height' => 2},
      {'id' => 'c', 'width' => 4, 'height' => 3}, {'id' => 'd', 'width' => 1, 'height' => 3}
    ]}
    results = PorchParcel.compare(data)
    assert_equal %w[first-fit area best-fit], results.keys
    assert_equal 15, results['best-fit'][:placed].sum { |p| p.width * p.height }
    report = StringIO.new; PorchParcel.render_compare(results, report)
    assert_includes report.string, "strategy\toccupied\tplaced\tunused-usable\tunplaced"
    assert_includes report.string, 'best-fit'
    json = StringIO.new; PorchParcel.render_compare_json(results, json)
    parsed = JSON.parse(json.string); assert_equal %w[first-fit area best-fit], parsed['comparison'].keys
    assert_equal 15, parsed['comparison']['best-fit']['occupied_area']
    page = PorchParcel.html_compare(results)
    assert_equal 3, page.scan('class="compare-panel"').length
    assert_includes page, 'best-fit'
    rotated_page = PorchParcel.html_compare(PorchParcel.compare({'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}, rotate: true))
    assert_includes rotated_page, 'turn'
    assert_includes rotated_page, '3×2 · rotated'
    assert_includes rotated_page, 'class="legend"'
  end
  def test_compare_zero_and_all_blocked_are_consistent
    empty = PorchParcel.compare({'shelf_width' => 2, 'shelf_height' => 2, 'parcels' => []})
    assert empty.values.all? { |r| r[:placed].empty? && r[:unplaced].empty? }
    blocked = PorchParcel.compare({'shelf_width' => 2, 'shelf_height' => 2, 'blocked' => [{'x' => 0, 'y' => 0}, {'x' => 1, 'y' => 0}, {'x' => 0, 'y' => 1}, {'x' => 1, 'y' => 1}], 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}]})
    assert blocked.values.all? { |r| r[:placed].empty? && r[:unplaced] == ['x'] }
  end
  def test_svg_export_contains_scalable_geometry_legend_and_rotation
    result = PorchParcel.pack({'shelf_width' => 3, 'shelf_height' => 2, 'parcels' => [{'id' => 'turn', 'width' => 2, 'height' => 3}]}, rotate: true)
    svg = PorchParcel.svg(result)
    assert_includes svg, '<svg'
    assert_includes svg, 'viewBox="0 0 24 10.5"'
    blocked_svg = PorchParcel.svg(PorchParcel.pack({'shelf_width' => 1, 'shelf_height' => 1, 'blocked' => [{'x' => 0, 'y' => 0}], 'parcels' => []}))
    assert_includes blocked_svg, 'Blocked shelf cell at 0,0'
    assert_includes svg, 'turn 3×2 · rotated'
    assert_includes svg, 'occupied area'
    require 'rexml/document'; document = REXML::Document.new(svg)
    assert_equal 'svg', document.root.name
  end
  def test_cli_svg_existing_file_guard_and_flag_conflicts
    Dir.mktmpdir do |dir|
      input = File.join(dir, 'input.json'); output = File.join(dir, 'shelf.svg')
      File.write(input, JSON.generate('shelf_width' => 1, 'shelf_height' => 1, 'parcels' => [{'id' => 'x', 'width' => 1, 'height' => 1}]))
      script = File.expand_path('../app/packer.rb', __dir__)
      `ruby #{script} --svg #{output} #{input}`; assert File.file?(output)
      second = `ruby #{script} --svg #{output} #{input} 2>&1`; assert_includes second, 'output exists'
      conflict = `ruby #{script} --svg #{output} --html #{File.join(dir, 'other.html')} #{input} 2>&1`; assert_includes conflict, 'cannot be combined'
    end
  end
  def test_svg_narrow_shelf_allocates_canvas_for_long_unplaced_legend
    parcels = 30.times.map { |i| {'id' => "parcel-#{i}-long-label", 'width' => 40, 'height' => 20} }
    svg = PorchParcel.svg(PorchParcel.pack({'shelf_width' => 1, 'shelf_height' => 1, 'parcels' => parcels}))
    assert_includes svg, 'viewBox="0 0 24 53.0"'
    assert_includes svg, 'Unplaced: parcel-29-long-label'
  end
end
